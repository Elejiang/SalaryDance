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
    let countedInStatistics: Bool
    let settlementNote: String?
}

/// 合并摸鱼记录前的预览分组，展示哪些同工作日重叠区间会被压成一条原始记录。
struct OffTaskMergePreviewCluster: Equatable, Identifiable {
    let id: String
    let workday: Date
    let originalSessions: [OffTaskSession]
    let mergedSession: OffTaskSession

    var removedRecordCount: Int {
        max(0, originalSessions.count - 1)
    }
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
            summaryMapCache = nil
            save()
        }
    }

    private struct SummaryAccumulator {
        var paidSeconds: TimeInterval = 0
        var amount: Double = 0
        var sessionCount: Int = 0
    }

    private struct SummaryMapCache {
        let sessions: [OffTaskSession]
        let config: SalaryConfig
        let nowTick: Int
        let calendarIdentifier: Calendar.Identifier
        let calendarTimeZone: TimeZone
        let result: [Date: SummaryAccumulator]
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "off_task_sessions"
    private var summaryMapCache: SummaryMapCache?

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

    static func sessionValidationMessage(start: Date, end: Date, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> String? {
        guard end > start else {
            return "结束时间必须晚于开始时间"
        }

        guard end <= now else {
            return "结束时间不能超过当前时间"
        }

        guard let window = SalaryWorkTimeline.activeWindow(containing: start, config: config, calendar: calendar) else {
            return "开始时间必须在有效工作窗口内"
        }

        guard end <= window.end else {
            return "摸鱼结束时间不能超过当天下班时间"
        }

        return nil
    }

    @discardableResult
    func addSession(start: Date, end: Date, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        guard Self.sessionValidationMessage(start: start, end: end, now: now, config: config, calendar: calendar) == nil else {
            return false
        }

        sessions.append(OffTaskSession(start: start, end: end))
        sessions.sort { $0.start < $1.start }
        return true
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
    func updateSessionTimeRange(id: UUID, start: Date, end: Date?, now: Date = Date(), config: SalaryConfig? = nil, calendar: Calendar = .current) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let keepsOpenSession = end == nil && sessions[index].end == nil
        if let end {
            if let config {
                guard Self.sessionValidationMessage(start: start, end: end, now: now, config: config, calendar: calendar) == nil else {
                    return false
                }
            } else {
                guard end > start else {
                    return false
                }
            }
        } else {
            guard keepsOpenSession ? now > start : true else {
                return false
            }
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

    @discardableResult
    func deleteSessions(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        let originalCount = sessions.count
        let updated = sessions.filter { !ids.contains($0.id) }
        guard updated.count != originalCount else { return 0 }

        sessions = updated
        return originalCount - updated.count
    }

    func overlappingMergeCountByWorkday(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> Int {
        overlappingMergePreviewByWorkday(config: config, now: now, calendar: calendar).reduce(0) { $0 + $1.removedRecordCount }
    }

    func overlappingMergePreviewByWorkday(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> [OffTaskMergePreviewCluster] {
        mergedOverlappingSessionsByWorkday(config: config, now: now, calendar: calendar).previewClusters
    }

    @discardableResult
    func mergeOverlappingSessionsByWorkday(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let result = mergedOverlappingSessionsByWorkday(config: config, now: now, calendar: calendar)
        let mergedCount = result.previewClusters.reduce(0) { $0 + $1.removedRecordCount }
        guard mergedCount > 0 else { return 0 }

        sessions = result.sessions
        return mergedCount
    }

    /// 导入替换的是用户原始记录，先在内存中完整校验并规范排序，避免落入多个进行中记录等无法稳定展示的状态。
    func replaceSessionsForImport(_ imported: [OffTaskSession]) throws {
        sessions = try Self.normalizedImportedSessions(imported)
    }

    static func normalizedImportedSessions(_ imported: [OffTaskSession]) throws -> [OffTaskSession] {
        var usedIDs = Set<UUID>()
        var activeSessionCount = 0
        var normalized: [OffTaskSession] = []

        for session in imported {
            if let end = session.end, end <= session.start {
                throw SalaryDataTransferError.invalidOffTaskData("存在结束时间不晚于开始时间的摸鱼记录")
            }

            if session.end == nil {
                activeSessionCount += 1
            }

            var uniqueSession = session
            if usedIDs.contains(uniqueSession.id) {
                uniqueSession.id = UUID()
            }
            usedIDs.insert(uniqueSession.id)
            normalized.append(uniqueSession)
        }

        guard activeSessionCount <= 1 else {
            throw SalaryDataTransferError.invalidOffTaskData("最多只能有一条进行中的摸鱼记录")
        }

        return normalized.sorted { $0.start < $1.start }
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
        return dailySummary(for: day, accumulator: map[day] ?? SummaryAccumulator(), config: config, now: now, calendar: calendar)
    }

    func recentSummaries(limit: Int = 14, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> [OffTaskDailySummary] {
        let currentWorkday = SalaryWorkTimeline.relevantWorkday(for: now, config: config, calendar: calendar)
        let map = summaryMap(config: config, now: now, calendar: calendar)
        let days = Set(map.keys).union([calendar.startOfDay(for: currentWorkday)])

        return days
            .sorted(by: >)
            .prefix(limit)
            .map { day in
                dailySummary(for: day, accumulator: map[day] ?? SummaryAccumulator(), config: config, now: now, calendar: calendar)
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

    func previewSessionSummary(start: Date, end: Date, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> OffTaskSessionSummary {
        sessionSummary(for: OffTaskSession(start: start, end: end), config: config, now: now, calendar: calendar)
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

    private func dailySummary(
        for day: Date,
        accumulator: SummaryAccumulator,
        config: SalaryConfig,
        now: Date,
        calendar: Calendar
    ) -> OffTaskDailySummary {
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

    private func summaryMap(config: SalaryConfig, now: Date, calendar: Calendar) -> [Date: SummaryAccumulator] {
        let nowTick = summaryMapNowTick(now: now)
        if let cached = summaryMapCache,
           cached.sessions == sessions,
           cached.config == config,
           cached.nowTick == nowTick,
           cached.calendarIdentifier == calendar.identifier,
           cached.calendarTimeZone == calendar.timeZone {
            return cached.result
        }

        let result: [Date: SummaryAccumulator] = sessions.reduce(into: [:]) { result, session in
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
                guard paidSeconds > 0 else { continue }

                var accumulator = result[window.workday] ?? SummaryAccumulator()
                accumulator.paidSeconds += paidSeconds
                accumulator.amount += paidSeconds * window.salaryPerSecond
                accumulator.sessionCount += 1
                result[window.workday] = accumulator
            }
        }

        summaryMapCache = SummaryMapCache(
            sessions: sessions,
            config: config,
            nowTick: nowTick,
            calendarIdentifier: calendar.identifier,
            calendarTimeZone: calendar.timeZone,
            result: result
        )
        return result
    }

    private func summaryMapNowTick(now: Date) -> Int {
        // 已结束记录与当前时间无关；进行中记录才需要按秒刷新实时累计。
        guard sessions.contains(where: { $0.end == nil }) else { return 0 }
        return Int(now.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private func sessionSummary(for session: OffTaskSession, config: SalaryConfig, now: Date, calendar: Calendar) -> OffTaskSessionSummary {
        let end = session.end ?? now
        var paidSeconds: TimeInterval = 0
        var amount: Double = 0
        var matchedWorkday: Date?
        var workWindowOverlapSeconds: TimeInterval = 0
        var unpaidBreakOverlapSeconds: TimeInterval = 0

        if end > session.start {
            for day in candidateWorkdays(from: session.start, to: end, calendar: calendar) {
                guard let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar) else { continue }

                let windowOverlap = SalaryWorkTimeline.workWindowOverlapSeconds(from: session.start, to: end, in: window)
                guard windowOverlap > 0 else { continue }
                workWindowOverlapSeconds += windowOverlap
                unpaidBreakOverlapSeconds += SalaryWorkTimeline.unpaidBreakOverlapSeconds(
                    from: session.start,
                    to: end,
                    in: window,
                    config: config,
                    calendar: calendar
                )

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

        let countedInStatistics = paidSeconds > 0
        return OffTaskSessionSummary(
            session: session,
            workday: matchedWorkday ?? SalaryWorkTimeline.relevantWorkday(for: session.start, config: config, calendar: calendar),
            paidSeconds: paidSeconds,
            amount: amount,
            isActive: session.end == nil,
            countedInStatistics: countedInStatistics,
            settlementNote: Self.settlementNote(
                countedInStatistics: countedInStatistics,
                workWindowOverlapSeconds: workWindowOverlapSeconds,
                unpaidBreakOverlapSeconds: unpaidBreakOverlapSeconds,
                config: config
            )
        )
    }

    private static func settlementNote(
        countedInStatistics: Bool,
        workWindowOverlapSeconds: TimeInterval,
        unpaidBreakOverlapSeconds: TimeInterval,
        config: SalaryConfig
    ) -> String? {
        if !config.countsBreakTimeAsPaidWork, unpaidBreakOverlapSeconds > 0 {
            if countedInStatistics {
                return "当前休息时间未计薪，午休/晚饭重叠部分已从统计中扣除。"
            }
            return "当前休息时间未计薪，这条记录保留在历史中，但不计入摸鱼薪资、时长和次数。"
        }

        if !countedInStatistics {
            if workWindowOverlapSeconds > 0 {
                return "当前计薪规则下没有可结算时长，记录保留但不计入统计。"
            }
            return "当前计薪规则下不在有效工作窗口内，记录保留但不计入统计。"
        }

        return nil
    }

    private func mergedOverlappingSessionsByWorkday(
        config: SalaryConfig,
        now: Date,
        calendar: Calendar
    ) -> (sessions: [OffTaskSession], previewClusters: [OffTaskMergePreviewCluster]) {
        var workdayBySessionID: [UUID: Date] = [:]
        for session in sessions {
            let summary = sessionSummary(for: session, config: config, now: now, calendar: calendar)
            workdayBySessionID[session.id] = calendar.startOfDay(for: summary.workday)
        }
        let grouped = Dictionary(grouping: sessions) { session in
            workdayBySessionID[session.id] ?? calendar.startOfDay(for: session.start)
        }

        var mergedSessions: [OffTaskSession] = []
        var previewClusters: [OffTaskMergePreviewCluster] = []

        for workday in grouped.keys.sorted() {
            let group = (grouped[workday] ?? []).sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return (lhs.end ?? now) < (rhs.end ?? now)
                }
                return lhs.start < rhs.start
            }
            var current: OffTaskSession?
            var currentOriginals: [OffTaskSession] = []

            for session in group {
                guard let existing = current else {
                    current = session
                    currentOriginals = [session]
                    continue
                }

                if Self.sessionsOverlap(existing, session, now: now) {
                    current = Self.mergedSession(existing, session)
                    currentOriginals.append(session)
                } else {
                    Self.appendMergeResult(
                        existing,
                        workday: workday,
                        originals: currentOriginals,
                        to: &mergedSessions,
                        previewClusters: &previewClusters
                    )
                    current = session
                    currentOriginals = [session]
                }
            }

            if let current {
                Self.appendMergeResult(
                    current,
                    workday: workday,
                    originals: currentOriginals,
                    to: &mergedSessions,
                    previewClusters: &previewClusters
                )
            }
        }

        return (mergedSessions.sorted { $0.start < $1.start }, previewClusters)
    }

    private static func appendMergeResult(
        _ session: OffTaskSession,
        workday: Date,
        originals: [OffTaskSession],
        to mergedSessions: inout [OffTaskSession],
        previewClusters: inout [OffTaskMergePreviewCluster]
    ) {
        mergedSessions.append(session)

        guard originals.count > 1 else { return }
        previewClusters.append(
            OffTaskMergePreviewCluster(
                id: originals.map(\.id.uuidString).joined(separator: "-"),
                workday: workday,
                originalSessions: originals,
                mergedSession: session
            )
        )
    }

    private static func sessionsOverlap(_ lhs: OffTaskSession, _ rhs: OffTaskSession, now: Date) -> Bool {
        let lhsEnd = lhs.end ?? now
        let rhsEnd = rhs.end ?? now
        guard lhsEnd > lhs.start, rhsEnd > rhs.start else { return false }
        return lhs.start < rhsEnd && rhs.start < lhsEnd
    }

    private static func mergedSession(_ lhs: OffTaskSession, _ rhs: OffTaskSession) -> OffTaskSession {
        let includesActiveSession = lhs.end == nil || rhs.end == nil
        let id = lhs.end == nil ? lhs.id : (rhs.end == nil ? rhs.id : lhs.id)
        let start = min(lhs.start, rhs.start)
        let end: Date?

        if includesActiveSession {
            end = nil
        } else {
            end = max(lhs.end ?? lhs.start, rhs.end ?? rhs.start)
        }

        return OffTaskSession(id: id, start: start, end: end)
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

/// 用户提前下班后产生的一段未继续工作的时间，金额按当前薪资规则实时折算为提前下班赚到的金额。
struct ClockOutSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var workday: Date
    var start: Date
    var end: Date

    init(id: UUID = UUID(), workday: Date, start: Date, end: Date) {
        self.id = id
        self.workday = workday
        self.start = start
        self.end = end
    }
}

/// 用户在真实下班后选择的一段晚下班时间，end 是用户计划的晚下班结束时间。
struct OvertimeSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var workday: Date
    var start: Date
    var end: Date

    init(id: UUID = UUID(), workday: Date, start: Date, end: Date) {
        self.id = id
        self.workday = workday
        self.start = start
        self.end = end
    }
}

enum WorkSessionRecordKind: String, Codable, Equatable, Hashable, CaseIterable {
    case clockOut
    case overtime

    var title: String {
        switch self {
        case .clockOut:
            return "提前下班"
        case .overtime:
            return "晚下班"
        }
    }
}

struct WorkSessionRecordIdentifier: Equatable, Hashable {
    let kind: WorkSessionRecordKind
    let id: UUID
}

/// 设置页历史明细使用的统一记录视图，金额仍按当前薪资配置实时换算。
struct WorkSessionRecordSummary: Equatable, Identifiable {
    let id: String
    let recordIdentifier: WorkSessionRecordIdentifier
    let kind: WorkSessionRecordKind
    let workday: Date
    let start: Date
    let end: Date
    let seconds: TimeInterval
    let amount: Double
    let isActive: Bool
}

/// 单个工作日的提前下班和晚下班统计，金额按当前薪资配置实时重算。
/// 提前下班金额表示提前下班仍赚到的薪资；晚下班金额表示默认无收入时按当天薪资折算的晚下班亏损。
struct WorkSessionDailySummary: Equatable, Identifiable {
    var id: String { dayKey }

    let workday: Date
    let dayKey: String
    let clockOutSeconds: TimeInterval
    let clockOutAmount: Double
    let clockOutCount: Int
    let overtimeSeconds: TimeInterval
    let overtimeAmount: Double
    let overtimeCount: Int

    var hasClockOutRecords: Bool {
        clockOutCount > 0 || clockOutSeconds > 0 || clockOutAmount > 0
    }

    var hasOvertimeRecords: Bool {
        overtimeCount > 0 || overtimeSeconds > 0 || overtimeAmount > 0
    }

    var hasRecords: Bool {
        hasClockOutRecords || hasOvertimeRecords
    }
}

/// 跨工作日聚合后的提前下班和晚下班统计。
struct WorkSessionAggregateSummary: Equatable {
    let clockOutSeconds: TimeInterval
    let clockOutAmount: Double
    let clockOutCount: Int
    let clockOutDayCount: Int
    let overtimeSeconds: TimeInterval
    let overtimeAmount: Double
    let overtimeCount: Int
    let overtimeDayCount: Int

    var hasRecords: Bool {
        clockOutCount > 0 || overtimeCount > 0
    }
}

struct ClockOutAvailability: Equatable {
    let canClockOut: Bool
    let shortMessage: String
    let helpMessage: String

    static let available = ClockOutAvailability(
        canClockOut: true,
        shortMessage: "可提前下班",
        helpMessage: "当前仍在工作窗口内，可提前下班。"
    )

    static let outsideWorkTime = ClockOutAvailability(
        canClockOut: false,
        shortMessage: "工作窗口外",
        helpMessage: "只有上班时间内可以提前下班。"
    )

    static let alreadyClockedOut = ClockOutAvailability(
        canClockOut: false,
        shortMessage: "已提前下班",
        helpMessage: "今日已记录提前下班，可先撤回。"
    )

    static let alreadyOvertime = ClockOutAvailability(
        canClockOut: false,
        shortMessage: "已晚下班",
        helpMessage: "该工作日已有晚下班记录，不能再提前下班。"
    )
}

struct OvertimeAvailability: Equatable {
    let canStart: Bool
    let shortMessage: String
    let helpMessage: String

    static let available = OvertimeAvailability(
        canStart: true,
        shortMessage: "可晚下班",
        helpMessage: "当前已到真实下班时间，可记录晚下班。"
    )

    static let beforeWorkFinished = OvertimeAvailability(
        canStart: false,
        shortMessage: "未到下班",
        helpMessage: "真实下班后才可以记录晚下班。"
    )

    static let active = OvertimeAvailability(
        canStart: false,
        shortMessage: "晚下班中",
        helpMessage: "已有进行中的晚下班记录，可先撤回。"
    )

    static let alreadyClockedOut = OvertimeAvailability(
        canStart: false,
        shortMessage: "已提前下班",
        helpMessage: "该工作日已有提前下班记录，不能再记录晚下班。"
    )

    static let alreadyRecorded = OvertimeAvailability(
        canStart: false,
        shortMessage: "已记录晚下班",
        helpMessage: "该工作日已有晚下班记录，可在记录页编辑或延长。"
    )
}

/// 负责持久化提前下班和晚下班记录，并把原始时间换算成统计时长与金额。
final class WorkSessionTracker: ObservableObject {
    static let shared = WorkSessionTracker()

    @Published private(set) var clockOutSessions: [ClockOutSession] = [] {
        didSet {
            saveClockOutSessions()
        }
    }

    @Published private(set) var overtimeSessions: [OvertimeSession] = [] {
        didSet {
            saveOvertimeSessions()
        }
    }

    private struct SummaryAccumulator {
        var clockOutSeconds: TimeInterval = 0
        var clockOutAmount: Double = 0
        var clockOutCount: Int = 0
        var overtimeSeconds: TimeInterval = 0
        var overtimeAmount: Double = 0
        var overtimeCount: Int = 0
    }

    private let defaults = UserDefaults.standard
    private let clockOutStorageKey = "clock_out_sessions"
    private let overtimeStorageKey = "overtime_sessions"

    private init() {
        clockOutSessions = Self.loadClockOutSessions(defaults: defaults, key: clockOutStorageKey)
        overtimeSessions = Self.loadOvertimeSessions(defaults: defaults, key: overtimeStorageKey)
    }

    var isOvertimeActive: Bool {
        activeOvertimeSession() != nil
    }

    func activeOvertimeSession(now: Date = Date(), config: SalaryConfig? = nil, calendar: Calendar = .current) -> OvertimeSession? {
        overtimeSessions.last { session in
            now >= session.start && now < session.end
        }
    }

    func clockOutAvailability(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> ClockOutAvailability {
        guard let window = SalaryWorkTimeline.activeWindow(containing: now, config: config, calendar: calendar),
              now < window.end else {
            return .outsideWorkTime
        }

        if clockOutSession(for: window.workday, calendar: calendar) != nil {
            return .alreadyClockedOut
        }

        if latestOvertimeSession(for: window.workday, calendar: calendar) != nil {
            return .alreadyOvertime
        }

        return .available
    }

    func overtimeAvailability(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> OvertimeAvailability {
        if activeOvertimeSession(now: now, config: config, calendar: calendar) != nil {
            return .active
        }

        guard let window = SalaryWorkTimeline.latestFinishedWindow(endingAtOrBefore: now, config: config, calendar: calendar) else {
            return .beforeWorkFinished
        }

        let relevantWorkday = SalaryWorkTimeline.relevantWorkday(for: now, config: config, calendar: calendar)
        guard calendar.isDate(relevantWorkday, inSameDayAs: window.workday) else {
            return .beforeWorkFinished
        }

        if clockOutSession(for: window.workday, calendar: calendar) != nil {
            return .alreadyClockedOut
        }

        if latestOvertimeSession(for: window.workday, calendar: calendar) != nil {
            return .alreadyRecorded
        }

        return .available
    }

    func clockOut(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) {
        guard clockOutAvailability(now: now, config: config, calendar: calendar).canClockOut,
              let window = SalaryWorkTimeline.activeWindow(containing: now, config: config, calendar: calendar),
              now < window.end else {
            return
        }

        clockOutSessions.append(
            ClockOutSession(
                workday: calendar.startOfDay(for: window.workday),
                start: now,
                end: window.end
            )
        )
        clockOutSessions.sort { $0.start < $1.start }
    }

    @discardableResult
    func addClockOutSession(clockOutAt: Date, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        guard clockOutValidationMessage(clockOutAt: clockOutAt, now: now, config: config, calendar: calendar) == nil,
              let window = SalaryWorkTimeline.activeWindow(containing: clockOutAt, config: config, calendar: calendar) else {
            return false
        }

        clockOutSessions.append(
            ClockOutSession(
                workday: calendar.startOfDay(for: window.workday),
                start: clockOutAt,
                end: window.end
            )
        )
        clockOutSessions.sort { $0.start < $1.start }
        return true
    }

    @discardableResult
    func updateClockOutSession(id: UUID, clockOutAt: Date, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        guard clockOutValidationMessage(clockOutAt: clockOutAt, now: now, config: config, calendar: calendar, excluding: id) == nil,
              let index = clockOutSessions.firstIndex(where: { $0.id == id }),
              let window = SalaryWorkTimeline.activeWindow(containing: clockOutAt, config: config, calendar: calendar) else {
            return false
        }

        var updated = clockOutSessions
        updated[index] = ClockOutSession(
            id: id,
            workday: calendar.startOfDay(for: window.workday),
            start: clockOutAt,
            end: window.end
        )
        clockOutSessions = updated.sorted { $0.start < $1.start }
        return true
    }

    @discardableResult
    func undoClockOut(for workday: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: workday)
        guard let index = clockOutSessions.lastIndex(where: { calendar.isDate($0.workday, inSameDayAs: day) }) else {
            return false
        }

        clockOutSessions.remove(at: index)
        return true
    }

    @discardableResult
    func deleteClockOutSessions(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        let originalCount = clockOutSessions.count
        let updated = clockOutSessions.filter { !ids.contains($0.id) }
        guard updated.count != originalCount else { return 0 }

        clockOutSessions = updated
        return originalCount - updated.count
    }

    func startOvertime(minutes: Int, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) {
        let normalizedMinutes = minutes
        guard normalizedMinutes > 0 else {
            return
        }

        guard let window = SalaryWorkTimeline.latestFinishedWindow(endingAtOrBefore: now, config: config, calendar: calendar),
              clockOutSession(for: window.workday, calendar: calendar) == nil else {
            return
        }

        if let existing = latestOvertimeSession(for: window.workday, calendar: calendar) {
            let base = max(existing.end, now)
            guard let extendedEnd = calendar.date(byAdding: .minute, value: normalizedMinutes, to: base),
                  extendedEnd > existing.end,
                  Self.overtimeEndsBeforeNextWorkWindow(end: extendedEnd, after: window, config: config, calendar: calendar) else {
                return
            }
            upsertOvertimeSession(
                workday: window.workday,
                start: existing.start,
                end: extendedEnd,
                calendar: calendar
            )
            return
        }

        guard overtimeAvailability(now: now, config: config, calendar: calendar).canStart,
              let end = calendar.date(byAdding: .minute, value: normalizedMinutes, to: now),
              end > now,
              Self.overtimeEndsBeforeNextWorkWindow(end: end, after: window, config: config, calendar: calendar) else {
            return
        }

        overtimeSessions.append(
            OvertimeSession(
                workday: calendar.startOfDay(for: window.workday),
                start: now,
                end: end
            )
        )
        overtimeSessions.sort { $0.start < $1.start }
    }

    @discardableResult
    func addOvertimeSession(workday: Date, durationMinutes: Int, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        guard overtimeValidationMessage(workday: workday, durationMinutes: durationMinutes, now: now, config: config, calendar: calendar) == nil,
              let window = SalaryWorkTimeline.workWindow(startingOn: workday, config: config, calendar: calendar),
              let end = calendar.date(byAdding: .minute, value: durationMinutes, to: window.end) else {
            return false
        }

        upsertOvertimeSession(
            workday: window.workday,
            start: window.end,
            end: end,
            calendar: calendar
        )
        return true
    }

    @discardableResult
    func updateOvertimeSession(id: UUID, workday: Date, durationMinutes: Int, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        guard overtimeValidationMessage(workday: workday, durationMinutes: durationMinutes, now: now, config: config, calendar: calendar, excluding: id) == nil,
              overtimeSessions.contains(where: { $0.id == id }),
              let window = SalaryWorkTimeline.workWindow(startingOn: workday, config: config, calendar: calendar),
              let end = calendar.date(byAdding: .minute, value: durationMinutes, to: window.end) else {
            return false
        }

        upsertOvertimeSession(
            id: id,
            workday: calendar.startOfDay(for: window.workday),
            start: window.end,
            end: end,
            replacing: id,
            calendar: calendar
        )
        return true
    }

    func clockOutValidationMessage(clockOutAt: Date, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current, excluding id: UUID? = nil) -> String? {
        if let message = Self.clockOutValidationMessage(clockOutAt: clockOutAt, now: now, config: config, calendar: calendar) {
            return message
        }

        guard let window = SalaryWorkTimeline.activeWindow(containing: clockOutAt, config: config, calendar: calendar) else {
            return "实际下班时间必须在有效工作窗口内"
        }

        let day = calendar.startOfDay(for: window.workday)
        if clockOutSession(for: day, excluding: id, calendar: calendar) != nil {
            return "该工作日已有提前下班记录"
        }

        if latestOvertimeSession(for: day, calendar: calendar) != nil {
            return "该工作日已有晚下班记录，不能再记录提前下班"
        }

        return nil
    }

    func overtimeValidationMessage(workday: Date, durationMinutes: Int, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current, excluding id: UUID? = nil) -> String? {
        if let message = Self.overtimeValidationMessage(workday: workday, durationMinutes: durationMinutes, now: now, config: config, calendar: calendar) {
            return message
        }

        let day = calendar.startOfDay(for: workday)
        guard let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar),
              let end = calendar.date(byAdding: .minute, value: durationMinutes, to: window.end) else {
            return "晚下班日期必须是有效工作日"
        }

        if clockOutSession(for: window.workday, calendar: calendar) != nil {
            return "该工作日已有提前下班记录，不能再记录晚下班"
        }

        let existing = overtimeSessions(on: window.workday, excluding: id, calendar: calendar)
        if let latestEnd = existing.map(\.end).max(),
           end <= latestEnd {
            return "该工作日已有不短于当前时长的晚下班记录"
        }

        return nil
    }

    static func clockOutValidationMessage(clockOutAt: Date, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> String? {
        guard clockOutAt <= now else {
            return "实际下班时间不能超过当前时间"
        }

        guard let window = SalaryWorkTimeline.activeWindow(containing: clockOutAt, config: config, calendar: calendar) else {
            return "实际下班时间必须在有效工作窗口内"
        }

        guard clockOutAt < window.end else {
            return "实际下班时间必须早于当天应下班时间"
        }

        return nil
    }

    static func overtimeValidationMessage(workday: Date, durationMinutes: Int, now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> String? {
        let day = calendar.startOfDay(for: workday)

        guard durationMinutes > 0 else {
            return "晚下班时长必须大于 0"
        }

        guard let window = SalaryWorkTimeline.workWindow(startingOn: day, config: config, calendar: calendar) else {
            return "晚下班日期必须是有效工作日"
        }

        guard let end = calendar.date(byAdding: .minute, value: durationMinutes, to: window.end),
              end > window.end else {
            return "晚下班结束时间必须晚于当天应下班时间"
        }

        let isToday = calendar.isDate(window.workday, inSameDayAs: now)
        guard end <= now || isToday else {
            return "只能提前预定当天晚下班"
        }

        guard overtimeEndsBeforeNextWorkWindow(end: end, after: window, config: config, calendar: calendar) else {
            return "晚下班结束时间不能进入下一次上班窗口"
        }

        return nil
    }

    private static func overtimeEndsBeforeNextWorkWindow(end: Date, after window: SalaryWorkWindow, config: SalaryConfig, calendar: Calendar) -> Bool {
        guard let nextWindow = SalaryWorkTimeline.nextWorkWindow(startingAtOrAfter: window.end, config: config, calendar: calendar) else {
            return true
        }
        return end <= nextWindow.start
    }

    @discardableResult
    func endActiveOvertime(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        guard let active = activeOvertimeSession(now: now, config: config, calendar: calendar),
              let index = overtimeSessions.firstIndex(where: { $0.id == active.id }) else {
            return false
        }

        let minimumEnd = active.start.addingTimeInterval(1)
        overtimeSessions[index].end = max(now, minimumEnd)
        overtimeSessions.sort { $0.start < $1.start }
        return true
    }

    @discardableResult
    func undoLatestOvertime(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        let workday = activeOvertimeSession(now: now, config: config, calendar: calendar)?.workday
            ?? currentRecordWorkday(now: now, config: config, calendar: calendar)
        let day = calendar.startOfDay(for: workday)

        guard let index = overtimeSessions.lastIndex(where: { calendar.isDate($0.workday, inSameDayAs: day) }) else {
            return false
        }

        overtimeSessions.remove(at: index)
        return true
    }

    @discardableResult
    func deleteOvertimeSessions(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }

        let originalCount = overtimeSessions.count
        let updated = overtimeSessions.filter { !ids.contains($0.id) }
        guard updated.count != originalCount else { return 0 }

        overtimeSessions = updated
        return originalCount - updated.count
    }

    @discardableResult
    func deleteRecords(ids: Set<WorkSessionRecordIdentifier>) -> Int {
        guard !ids.isEmpty else { return 0 }

        let clockOutIDs = Set(ids.compactMap { $0.kind == .clockOut ? $0.id : nil })
        let overtimeIDs = Set(ids.compactMap { $0.kind == .overtime ? $0.id : nil })
        return deleteClockOutSessions(ids: clockOutIDs) + deleteOvertimeSessions(ids: overtimeIDs)
    }

    func clockOutSession(for workday: Date, calendar: Calendar = .current) -> ClockOutSession? {
        clockOutSession(for: workday, excluding: nil, calendar: calendar)
    }

    private func clockOutSession(for workday: Date, excluding id: UUID?, calendar: Calendar) -> ClockOutSession? {
        let day = calendar.startOfDay(for: workday)
        return clockOutSessions.last { session in
            calendar.isDate(session.workday, inSameDayAs: day) && session.id != id
        }
    }

    func latestOvertimeSession(for workday: Date, calendar: Calendar = .current) -> OvertimeSession? {
        latestOvertimeSession(for: workday, excluding: nil, calendar: calendar)
    }

    private func latestOvertimeSession(for workday: Date, excluding id: UUID?, calendar: Calendar) -> OvertimeSession? {
        overtimeSessions(on: workday, excluding: id, calendar: calendar).max { lhs, rhs in
            if lhs.end == rhs.end {
                return lhs.start < rhs.start
            }
            return lhs.end < rhs.end
        }
    }

    private func overtimeSessions(on workday: Date, excluding id: UUID?, calendar: Calendar) -> [OvertimeSession] {
        let day = calendar.startOfDay(for: workday)
        return overtimeSessions.filter { session in
            calendar.isDate(session.workday, inSameDayAs: day) && session.id != id
        }
    }

    private func upsertOvertimeSession(
        id preferredID: UUID? = nil,
        workday: Date,
        start: Date,
        end: Date,
        replacing replacedID: UUID? = nil,
        calendar: Calendar
    ) {
        let day = calendar.startOfDay(for: workday)
        let existingForDay = overtimeSessions(on: day, excluding: replacedID, calendar: calendar)
        let mergedID = preferredID ?? existingForDay.first?.id ?? UUID()
        let mergedStart = ([start] + existingForDay.map(\.start)).min() ?? start
        let mergedEnd = ([end] + existingForDay.map(\.end)).max() ?? end

        var updated = overtimeSessions.filter { session in
            if let replacedID, session.id == replacedID {
                return false
            }
            return !calendar.isDate(session.workday, inSameDayAs: day)
        }

        updated.append(
            OvertimeSession(
                id: mergedID,
                workday: day,
                start: mergedStart,
                end: mergedEnd
            )
        )
        overtimeSessions = updated.sorted { $0.start < $1.start }
    }

    func currentSummary(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> WorkSessionDailySummary {
        summary(for: currentRecordWorkday(now: now, config: config, calendar: calendar), config: config, now: now, calendar: calendar)
    }

    func summary(for workday: Date, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> WorkSessionDailySummary {
        let day = calendar.startOfDay(for: workday)
        let accumulator = summaryMap(config: config, now: now, calendar: calendar)[day] ?? SummaryAccumulator()
        return dailySummary(for: day, accumulator: accumulator, calendar: calendar)
    }

    func summary(from start: Date, toExclusive endExclusive: Date, config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> WorkSessionAggregateSummary {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: endExclusive)
        guard endDay > startDay else {
            return Self.emptyAggregate
        }

        let values = summaryMap(config: config, now: now, calendar: calendar).filter { day, _ in
            day >= startDay && day < endDay
        }.map(\.value)

        return aggregate(values)
    }

    func totalSummary(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> WorkSessionAggregateSummary {
        aggregate(Array(summaryMap(config: config, now: now, calendar: calendar).values))
    }

    func recordSummaries(config: SalaryConfig, now: Date = Date(), calendar: Calendar = .current) -> [WorkSessionRecordSummary] {
        var records: [WorkSessionRecordSummary] = []

        for session in clockOutSessions {
            let settlement = clockOutSettlement(for: session, config: config, calendar: calendar)
            records.append(
                WorkSessionRecordSummary(
                    id: "clockOut-\(session.id.uuidString)",
                    recordIdentifier: WorkSessionRecordIdentifier(kind: .clockOut, id: session.id),
                    kind: .clockOut,
                    workday: calendar.startOfDay(for: session.workday),
                    start: session.start,
                    end: session.end,
                    seconds: settlement.seconds,
                    amount: settlement.amount,
                    isActive: false
                )
            )
        }

        for session in overtimeSessions {
            let settlement = overtimeSettlement(for: session, now: now, config: config, calendar: calendar)
            records.append(
                WorkSessionRecordSummary(
                    id: "overtime-\(session.id.uuidString)",
                    recordIdentifier: WorkSessionRecordIdentifier(kind: .overtime, id: session.id),
                    kind: .overtime,
                    workday: calendar.startOfDay(for: session.workday),
                    start: session.start,
                    end: session.end,
                    seconds: settlement.seconds,
                    amount: settlement.amount,
                    isActive: now >= session.start && now < session.end
                )
            )
        }

        return records.sorted { lhs, rhs in
            let lhsEnd = lhs.isActive ? now : lhs.end
            let rhsEnd = rhs.isActive ? now : rhs.end
            if lhsEnd == rhsEnd {
                return lhs.start > rhs.start
            }
            return lhsEnd > rhsEnd
        }
    }

    func shouldShowPopoverPanel(now: Date = Date(), config: SalaryConfig, calendar: Calendar = .current) -> Bool {
        let summary = currentSummary(config: config, now: now, calendar: calendar)
        return clockOutAvailability(now: now, config: config, calendar: calendar).canClockOut
            || clockOutSession(for: summary.workday, calendar: calendar) != nil
            || overtimeAvailability(now: now, config: config, calendar: calendar).canStart
            || latestOvertimeSession(for: summary.workday, calendar: calendar) != nil
            || summary.hasRecords
    }

    func replaceSessionsForImport(clockOut importedClockOutSessions: [ClockOutSession], overtime importedOvertimeSessions: [OvertimeSession]) throws {
        clockOutSessions = try Self.normalizedImportedClockOutSessions(importedClockOutSessions)
        overtimeSessions = try Self.normalizedImportedOvertimeSessions(importedOvertimeSessions)
    }

    static func normalizedImportedClockOutSessions(_ imported: [ClockOutSession], calendar: Calendar = .current) throws -> [ClockOutSession] {
        var usedIDs = Set<UUID>()
        var normalized: [ClockOutSession] = []

        for session in imported {
            guard session.end > session.start else {
                throw SalaryDataTransferError.invalidWorkSessionData("存在结束时间不晚于开始时间的提前下班记录")
            }

            var uniqueSession = ClockOutSession(
                id: session.id,
                workday: calendar.startOfDay(for: session.workday),
                start: session.start,
                end: session.end
            )
            if usedIDs.contains(uniqueSession.id) {
                uniqueSession.id = UUID()
            }
            usedIDs.insert(uniqueSession.id)
            normalized.append(uniqueSession)
        }

        return normalized.sorted { $0.start < $1.start }
    }

    static func normalizedImportedOvertimeSessions(_ imported: [OvertimeSession], calendar: Calendar = .current) throws -> [OvertimeSession] {
        var usedIDs = Set<UUID>()
        var normalized: [OvertimeSession] = []

        for session in imported {
            guard session.end > session.start else {
                throw SalaryDataTransferError.invalidWorkSessionData("存在结束时间不晚于开始时间的晚下班记录")
            }

            var uniqueSession = OvertimeSession(
                id: session.id,
                workday: calendar.startOfDay(for: session.workday),
                start: session.start,
                end: session.end
            )
            if usedIDs.contains(uniqueSession.id) {
                uniqueSession.id = UUID()
            }
            usedIDs.insert(uniqueSession.id)
            normalized.append(uniqueSession)
        }

        return normalized.sorted { $0.start < $1.start }
    }

    private static var emptyAggregate: WorkSessionAggregateSummary {
        WorkSessionAggregateSummary(
            clockOutSeconds: 0,
            clockOutAmount: 0,
            clockOutCount: 0,
            clockOutDayCount: 0,
            overtimeSeconds: 0,
            overtimeAmount: 0,
            overtimeCount: 0,
            overtimeDayCount: 0
        )
    }

    private func currentRecordWorkday(now: Date, config: SalaryConfig, calendar: Calendar) -> Date {
        if let activeOvertime = activeOvertimeSession(now: now, config: config, calendar: calendar) {
            return calendar.startOfDay(for: activeOvertime.workday)
        }
        return SalaryWorkTimeline.relevantWorkday(for: now, config: config, calendar: calendar)
    }

    private func summaryMap(config: SalaryConfig, now: Date, calendar: Calendar) -> [Date: SummaryAccumulator] {
        var result: [Date: SummaryAccumulator] = [:]

        for session in clockOutSessions {
            let day = calendar.startOfDay(for: session.workday)
            let settlement = clockOutSettlement(for: session, config: config, calendar: calendar)
            var accumulator = result[day] ?? SummaryAccumulator()
            accumulator.clockOutSeconds += settlement.seconds
            accumulator.clockOutAmount += settlement.amount
            accumulator.clockOutCount += 1
            result[day] = accumulator
        }

        for session in overtimeSessions {
            let day = calendar.startOfDay(for: session.workday)
            let settlement = overtimeSettlement(for: session, now: now, config: config, calendar: calendar)
            var accumulator = result[day] ?? SummaryAccumulator()
            accumulator.overtimeSeconds += settlement.seconds
            accumulator.overtimeAmount += settlement.amount
            accumulator.overtimeCount += 1
            result[day] = accumulator
        }

        return result
    }

    private func clockOutSettlement(for session: ClockOutSession, config: SalaryConfig, calendar: Calendar) -> (seconds: TimeInterval, amount: Double) {
        guard session.end > session.start,
              let window = SalaryWorkTimeline.workWindow(startingOn: session.workday, config: config, calendar: calendar) else {
            return (0, 0)
        }

        let seconds = SalaryWorkTimeline.paidOverlapSeconds(
            from: session.start,
            to: min(session.end, window.end),
            in: window,
            config: config,
            calendar: calendar
        )
        return (seconds, seconds * window.salaryPerSecond)
    }

    private func overtimeSettlement(for session: OvertimeSession, now: Date, config: SalaryConfig, calendar: Calendar) -> (seconds: TimeInterval, amount: Double) {
        guard session.end > session.start,
              let window = SalaryWorkTimeline.workWindow(startingOn: session.workday, config: config, calendar: calendar) else {
            return (0, 0)
        }

        let settledEnd = min(session.end, max(now, session.start))
        let seconds = max(0, settledEnd.timeIntervalSince(session.start))
        return (seconds, seconds * window.salaryPerSecond)
    }

    private func dailySummary(for day: Date, accumulator: SummaryAccumulator, calendar: Calendar) -> WorkSessionDailySummary {
        WorkSessionDailySummary(
            workday: day,
            dayKey: Self.dayKey(for: day, calendar: calendar),
            clockOutSeconds: accumulator.clockOutSeconds,
            clockOutAmount: accumulator.clockOutAmount,
            clockOutCount: accumulator.clockOutCount,
            overtimeSeconds: accumulator.overtimeSeconds,
            overtimeAmount: accumulator.overtimeAmount,
            overtimeCount: accumulator.overtimeCount
        )
    }

    private func aggregate(_ values: [SummaryAccumulator]) -> WorkSessionAggregateSummary {
        WorkSessionAggregateSummary(
            clockOutSeconds: values.reduce(0) { $0 + $1.clockOutSeconds },
            clockOutAmount: values.reduce(0) { $0 + $1.clockOutAmount },
            clockOutCount: values.reduce(0) { $0 + $1.clockOutCount },
            clockOutDayCount: values.filter { $0.clockOutCount > 0 || $0.clockOutSeconds > 0 || $0.clockOutAmount > 0 }.count,
            overtimeSeconds: values.reduce(0) { $0 + $1.overtimeSeconds },
            overtimeAmount: values.reduce(0) { $0 + $1.overtimeAmount },
            overtimeCount: values.reduce(0) { $0 + $1.overtimeCount },
            overtimeDayCount: values.filter { $0.overtimeCount > 0 || $0.overtimeSeconds > 0 || $0.overtimeAmount > 0 }.count
        )
    }

    private func saveClockOutSessions() {
        if let data = try? JSONEncoder().encode(clockOutSessions) {
            defaults.set(data, forKey: clockOutStorageKey)
        }
    }

    private func saveOvertimeSessions() {
        if let data = try? JSONEncoder().encode(overtimeSessions) {
            defaults.set(data, forKey: overtimeStorageKey)
        }
    }

    private static func loadClockOutSessions(defaults: UserDefaults, key: String) -> [ClockOutSession] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ClockOutSession].self, from: data),
              let normalized = try? normalizedImportedClockOutSessions(decoded) else {
            return []
        }

        return normalized
    }

    private static func loadOvertimeSessions(defaults: UserDefaults, key: String) -> [OvertimeSession] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([OvertimeSession].self, from: data),
              let normalized = try? normalizedImportedOvertimeSessions(decoded) else {
            return []
        }

        return normalized
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
