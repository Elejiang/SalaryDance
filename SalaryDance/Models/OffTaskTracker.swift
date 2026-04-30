import Foundation
import Combine

/// 用户手动开启的一段摸鱼状态，end 为空表示当前仍在摸鱼中。
struct OffTaskSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}

/// 单个工作日的摸鱼结算结果，金额按该工作日有效计薪区间实时折算。
struct OffTaskDailySummary: Equatable, Identifiable {
    var id: String { dayKey }

    let workday: Date
    let dayKey: String
    let paidSeconds: TimeInterval
    let amount: Double
    let sessionCount: Int
    let isWorkFinished: Bool

    var hasRecords: Bool {
        sessionCount > 0 || paidSeconds > 0 || amount > 0
    }
}

/// 跨工作日聚合后的摸鱼统计。
struct OffTaskAggregateSummary: Equatable {
    let paidSeconds: TimeInterval
    let amount: Double
    let sessionCount: Int
    let dayCount: Int
}

/// 单次摸鱼记录的可展示结算，保留原始时间范围用于编辑。
struct OffTaskSessionSummary: Equatable, Identifiable {
    var id: UUID { session.id }

    let session: OffTaskSession
    let workday: Date
    let paidSeconds: TimeInterval
    let amount: Double
    let isActive: Bool
}

/// 摸鱼开关的当前可用性，按钮、提示和快捷键入口共用同一套判断。
struct OffTaskStartAvailability: Equatable {
    let canStart: Bool
    let shortMessage: String
    let helpMessage: String

    static let available = OffTaskStartAvailability(
        canStart: true,
        shortMessage: "未开启",
        helpMessage: "当前为计薪工作时间，可开启摸鱼。"
    )

    static let outsideWorkTime = OffTaskStartAvailability(
        canStart: false,
        shortMessage: "工作窗口外不可开启",
        helpMessage: "当前不在计薪工作窗口内，不能开启摸鱼。"
    )

    static func unpaidBreak(_ name: String) -> OffTaskStartAvailability {
        OffTaskStartAvailability(
            canStart: false,
            shortMessage: "\(name)未计薪，不能开启",
            helpMessage: "当前是\(name)时间，且休息时间未计入计薪时长。开启“休息时间计入计薪时长”后，可在休息期间开启摸鱼。"
        )
    }

    static let unpaidTime = OffTaskStartAvailability(
        canStart: false,
        shortMessage: "当前不计薪，不能开启",
        helpMessage: "当前时间不会累计薪资，不能开启摸鱼。"
    )
}

/// 负责持久化摸鱼状态并把摸鱼区间换算成对应薪资。
final class OffTaskTracker: ObservableObject {
    static let shared = OffTaskTracker()

    @Published private(set) var sessions: [OffTaskSession] = [] {
        didSet {
            save()
        }
    }

    private struct SummaryAccumulator {
        var paidSeconds: TimeInterval = 0
        var amount: Double = 0
        var sessionCount: Int = 0
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "off_task_sessions"

    private init() {
        sessions = Self.loadSessions(defaults: defaults, key: storageKey)
    }

    var isActive: Bool {
        activeSession != nil
    }

    var activeSessionStart: Date? {
        activeSession?.start
    }

    private var activeSession: OffTaskSession? {
        sessions.last { $0.end == nil }
    }

    func startAvailability(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> OffTaskStartAvailability {
        guard let window = SalaryWorkTimeline.activeWindow(containing: now, config: config, calendar: calendar) else {
            return .outsideWorkTime
        }

        if let breakName = SalaryWorkTimeline.unpaidBreakName(containing: now, in: window, config: config, calendar: calendar) {
            return .unpaidBreak(breakName)
        }

        guard SalaryWorkTimeline.paidInterval(containing: now, in: window, config: config, calendar: calendar) != nil else {
            return .unpaidTime
        }

        return .available
    }

    func canStart(now: Date = Date(), config: SalaryConfig) -> Bool {
        startAvailability(now: now, config: config).canStart
    }

    func toggle(now: Date = Date(), config: SalaryConfig) {
        if isActive {
            stop(now: now)
        } else {
            start(now: now, config: config)
        }
    }

    /// 摸鱼状态只允许在真实工作窗口内开启，避免下班后误点产生无薪记录。
    func start(now: Date = Date(), config: SalaryConfig) {
        guard !isActive,
              canStart(now: now, config: config) else {
            return
        }
        sessions.append(OffTaskSession(start: now))
    }

    func stop(now: Date = Date()) {
        guard let index = sessions.lastIndex(where: { $0.end == nil }) else { return }
        var updated = sessions

        if now <= updated[index].start {
            updated.remove(at: index)
        } else {
            updated[index].end = now
        }

        sessions = updated
    }

    @discardableResult
    func updateSessionTimeRange(id: UUID, start: Date, end: Date?) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let keepsOpenSession = end == nil && sessions[index].end == nil
        guard end.map({ $0 > start }) ?? (keepsOpenSession ? Date() > start : true) else {
            return false
        }

        var updated = sessions
        updated[index].start = start
        updated[index].end = end
        sessions = updated.sorted { $0.start < $1.start }
        return true
    }

    @discardableResult
    func deleteSession(id: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return false
        }

        var updated = sessions
        updated.remove(at: index)
        sessions = updated
        return true
    }

    /// 定时刷新时收束跨过下班时间的打开区间；已关闭区间不再改写。
    func syncWithWorkState(now: Date = Date(), config: SalaryConfig) {
        closeOpenSessionIfNeeded(now: now, config: config)

        if isActive {
            objectWillChange.send()
        }
    }

    func currentSummary(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> OffTaskDailySummary {
        let workday = SalaryWorkTimeline.relevantWorkday(for: now, config: config, calendar: calendar)
        return summary(for: workday, config: config, now: now, calendar: calendar)
    }

    func summary(for workday: Date, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> OffTaskDailySummary {
        let day = calendar.startOfDay(for: workday)
        let map = summaryMap(config: config, now: now, calendar: calendar)
        let accumulator = map[day] ?? SummaryAccumulator()
        let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar)

        return OffTaskDailySummary(
            workday: day,
            dayKey: Self.dayKey(for: day, calendar: calendar),
            paidSeconds: accumulator.paidSeconds,
            amount: accumulator.amount,
            sessionCount: accumulator.sessionCount,
            isWorkFinished: window.map { now >= $0.end } ?? false
        )
    }

    func recentSummaries(limit: Int = 14, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> [OffTaskDailySummary] {
        let currentWorkday = SalaryWorkTimeline.relevantWorkday(for: now, config: config, calendar: calendar)
        let map = summaryMap(config: config, now: now, calendar: calendar)
        let days = Set(map.keys).union([calendar.startOfDay(for: currentWorkday)])

        return days
            .sorted(by: >)
            .prefix(limit)
            .map { day in
                summary(for: day, config: config, now: now, calendar: calendar)
            }
    }

    func salaryCycleSummary(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> OffTaskAggregateSummary {
        let period = config.salaryCyclePeriod(containing: now, calendar: calendar)
        return summary(from: period.start, toExclusive: period.endExclusive, config: config, now: now, calendar: calendar)
    }

    func summary(from start: Date, toExclusive endExclusive: Date, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> OffTaskAggregateSummary {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: endExclusive)
        guard endDay > startDay else {
            return OffTaskAggregateSummary(paidSeconds: 0, amount: 0, sessionCount: 0, dayCount: 0)
        }

        let map = summaryMap(config: config, now: now, calendar: calendar)
        let included = map.filter { day, _ in
            day >= startDay && day < endDay
        }
        return aggregate(included.map(\.value))
    }

    func totalSummary(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> OffTaskAggregateSummary {
        let values = summaryMap(config: config, now: now, calendar: calendar).values
        return aggregate(Array(values))
    }

    func sessionSummaries(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> [OffTaskSessionSummary] {
        sessions
            .map { sessionSummary(for: $0, config: config, now: now, calendar: calendar) }
            .sorted { lhs, rhs in
                (lhs.session.end ?? now) > (rhs.session.end ?? now)
            }
    }

    private func closeOpenSessionIfNeeded(now: Date, config: SalaryConfig, calendar: Calendar = .current) {
        guard let index = sessions.lastIndex(where: { $0.end == nil }) else { return }
        let session = sessions[index]
        guard let stopDate = automaticStopDate(for: session.start, now: now, config: config, calendar: calendar),
              stopDate > session.start else {
            return
        }

        var updated = sessions
        updated[index].end = stopDate
        sessions = updated
    }

    /// 找到开启摸鱼时所在计薪区间；休息未计薪时，跨入午休/晚饭会自动结算到休息开始。
    private func automaticStopDate(for start: Date, now: Date, config: SalaryConfig, calendar: Calendar) -> Date? {
        let startDay = calendar.startOfDay(for: start)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: startDay) ?? startDay
        let days = candidateWorkdays(from: previousDay, to: now, calendar: calendar)

        for day in days {
            guard let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar),
                  start >= window.start,
                  start < window.end else {
                continue
            }

            guard let paidInterval = SalaryWorkTimeline.paidInterval(containing: start, in: window, config: config, calendar: calendar) else {
                return now > start ? now : nil
            }

            return now >= paidInterval.end ? paidInterval.end : nil
        }

        return nil
    }

    private func summaryMap(config: SalaryConfig, now: Date, calendar: Calendar) -> [Date: SummaryAccumulator] {
        sessions.reduce(into: [:]) { result, session in
            let end = session.end ?? now
            guard end > session.start else { return }

            for day in candidateWorkdays(from: session.start, to: end, calendar: calendar) {
                guard let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar) else { continue }

                let windowOverlapStart = max(session.start, window.start)
                let windowOverlapEnd = min(end, window.end)
                guard windowOverlapEnd > windowOverlapStart else { continue }

                let paidSeconds = SalaryWorkTimeline.paidOverlapSeconds(
                    from: session.start,
                    to: end,
                    in: window,
                    config: config,
                    calendar: calendar
                )

                var accumulator = result[window.workday] ?? SummaryAccumulator()
                accumulator.paidSeconds += paidSeconds
                accumulator.amount += paidSeconds * window.salaryPerSecond
                accumulator.sessionCount += 1
                result[window.workday] = accumulator
            }
        }
    }

    private func sessionSummary(for session: OffTaskSession, config: SalaryConfig, now: Date, calendar: Calendar) -> OffTaskSessionSummary {
        let end = session.end ?? now
        var paidSeconds: TimeInterval = 0
        var amount: Double = 0
        var matchedWorkday: Date?

        if end > session.start {
            for day in candidateWorkdays(from: session.start, to: end, calendar: calendar) {
                guard let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar) else { continue }

                let windowOverlapStart = max(session.start, window.start)
                let windowOverlapEnd = min(end, window.end)
                guard windowOverlapEnd > windowOverlapStart else { continue }

                let seconds = SalaryWorkTimeline.paidOverlapSeconds(
                    from: session.start,
                    to: end,
                    in: window,
                    config: config,
                    calendar: calendar
                )
                paidSeconds += seconds
                amount += seconds * window.salaryPerSecond
                matchedWorkday = matchedWorkday ?? window.workday
            }
        }

        return OffTaskSessionSummary(
            session: session,
            workday: matchedWorkday ?? SalaryWorkTimeline.relevantWorkday(for: session.start, config: config, calendar: calendar),
            paidSeconds: paidSeconds,
            amount: amount,
            isActive: session.end == nil
        )
    }

    /// 跨夜窗口要求额外检查开始自然日的前一天，否则凌晨区间会丢失归属的工作日。
    private func candidateWorkdays(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let firstDay = calendar.date(byAdding: .day, value: -1, to: startDay) ?? startDay

        var days: [Date] = []
        var cursor = firstDay
        while cursor <= endDay {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return days
    }

    private func aggregate(_ values: [SummaryAccumulator]) -> OffTaskAggregateSummary {
        let paidSeconds = values.reduce(0) { $0 + $1.paidSeconds }
        let amount = values.reduce(0) { $0 + $1.amount }
        let sessionCount = values.reduce(0) { $0 + $1.sessionCount }
        let dayCount = values.filter { $0.sessionCount > 0 || $0.paidSeconds > 0 || $0.amount > 0 }.count

        return OffTaskAggregateSummary(
            paidSeconds: paidSeconds,
            amount: amount,
            sessionCount: sessionCount,
            dayCount: dayCount
        )
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func loadSessions(defaults: UserDefaults, key: String) -> [OffTaskSession] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([OffTaskSession].self, from: data) else {
            return []
        }

        return decoded
            .filter { session in
                guard let end = session.end else { return true }
                return end > session.start
            }
            .sorted { $0.start < $1.start }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}
