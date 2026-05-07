import Foundation
import Combine

/// 今日工作状态，用于弹窗的图标、文案和颜色。
enum WorkStatus: Equatable {
    case notStarted
    case working
    case onBreak(breakName: String)
    case clockedOutEarly
    case overtime
    case finished
    case dayOff
}

/// 按当前配置和系统时间计算实时收入、进度和工作状态。
final class SalaryViewModel: ObservableObject {
    @Published var todayEarnings: Double = 0
    @Published var status: WorkStatus = .notStarted
    @Published var statusText: String = ""
    @Published var earningsPerSecond: Double = 0
    @Published var progress: Double = 0
    @Published var effectiveDailySalary: Double = 0
    @Published var effectiveWorkTime: TimeRange = .defaultWorkTime
    @Published var effectivePaidWorkMinutes: Int = 0

    private var timer: Timer?
    private var updateInterval: TimeInterval = 1
    private let configManager = SalaryConfigManager.shared
    private let offTaskTracker = OffTaskTracker.shared
    private let workSessionTracker = WorkSessionTracker.shared

    var config: SalaryConfig {
        configManager.config
    }

    init(startsTimer: Bool = true) {
        if startsTimer {
            startTimer()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// 按当前刷新间隔启动定时器。
    func startTimer() {
        startTimer(interval: updateInterval, refreshImmediately: true)
    }

    /// 状态栏或弹窗显示状态变化时调整刷新频率。
    func setUpdateInterval(_ interval: TimeInterval) {
        let normalizedInterval = min(
            SalaryConfig.refreshIntervalRange.upperBound,
            max(SalaryConfig.refreshIntervalRange.lowerBound, interval)
        )
        guard abs(updateInterval - normalizedInterval) > 0.01 else { return }
        updateInterval = normalizedInterval
        startTimer(interval: normalizedInterval, refreshImmediately: false)
    }

    /// 配置变化或弹窗打开后刷新一次；只发布实际变化，避免强制重绘整棵弹窗视图。
    func refreshNow() {
        update(force: false)
    }

    private func startTimer(interval: TimeInterval, refreshImmediately: Bool) {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.update(force: false)
        }
        newTimer.tolerance = Self.timerTolerance(for: interval)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        if refreshImmediately {
            update(force: true)
        }
    }

    private static func timerTolerance(for interval: TimeInterval) -> TimeInterval {
        // 状态栏实时金额依赖稳定节拍触发数字过渡；短间隔不参与大幅 coalescing，避免滚动节奏忽快忽慢。
        if interval <= 1 {
            return 0.02
        }
        if interval <= 2 {
            return 0.05
        }
        return min(5, max(0.2, interval * 0.25))
    }

    private struct Snapshot {
        let todayEarnings: Double
        let status: WorkStatus
        let statusText: String
        let earningsPerSecond: Double
        let progress: Double
        let effectiveDailySalary: Double
        let effectiveWorkTime: TimeRange
        let effectivePaidWorkMinutes: Int
    }

    private struct WorkWindow {
        let start: Date
        let end: Date
        let workTime: TimeRange
        let dailySalary: Double
        let salaryPerSecond: Double
        let paidWorkMinutes: Int
    }

    /// 只在值实际变化时发布，降低 SwiftUI 重绘频率。
    private func update(force: Bool) {
        offTaskTracker.syncWithWorkState(config: configManager.config)
        let snapshot = makeSnapshot()

        if force || abs(todayEarnings - snapshot.todayEarnings) > 0.0001 {
            todayEarnings = snapshot.todayEarnings
        }
        if force || status != snapshot.status {
            status = snapshot.status
        }
        if force || statusText != snapshot.statusText {
            statusText = snapshot.statusText
        }
        if force || abs(earningsPerSecond - snapshot.earningsPerSecond) > 0.0001 {
            earningsPerSecond = snapshot.earningsPerSecond
        }
        if force || abs(progress - snapshot.progress) > 0.0001 {
            progress = snapshot.progress
        }
        if force || abs(effectiveDailySalary - snapshot.effectiveDailySalary) > 0.0001 {
            effectiveDailySalary = snapshot.effectiveDailySalary
        }
        if force || effectiveWorkTime != snapshot.effectiveWorkTime {
            effectiveWorkTime = snapshot.effectiveWorkTime
        }
        if force || effectivePaidWorkMinutes != snapshot.effectivePaidWorkMinutes {
            effectivePaidWorkMinutes = snapshot.effectivePaidWorkMinutes
        }
    }

    /// 生成当前时刻的完整展示快照，是实时刷新链路的核心入口。
    private func makeSnapshot() -> Snapshot {
        let cfg = configManager.config
        let now = Date()
        let calendar = Calendar.current

        let fallbackWorkTime = cfg.effectiveWorkTime(on: now, calendar: calendar)
        let fallbackDailySalary = cfg.effectiveDailySalary(on: now, calendar: calendar)
        let fallbackPaidWorkMinutes = cfg.paidWorkMinutes(workTime: fallbackWorkTime)
        let fallbackSalaryPerSecond = cfg.salaryPerSecond(on: now, calendar: calendar)

        guard cfg.workDurationMinutes > 0 || cfg.workDurationMinutes(for: fallbackWorkTime) > 0 else {
            return Snapshot(
                todayEarnings: 0,
                status: .dayOff,
                statusText: "工作时间未设置",
                earningsPerSecond: fallbackSalaryPerSecond,
                progress: 0,
                effectiveDailySalary: fallbackDailySalary,
                effectiveWorkTime: fallbackWorkTime,
                effectivePaidWorkMinutes: fallbackPaidWorkMinutes
            )
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // 支持跨夜班次：凌晨时可能仍处在昨天开始的工作窗口里。
        if let yesterdayWindow = makeWorkWindow(startingOn: yesterday, calendar: calendar, config: cfg) {
            if now >= yesterdayWindow.start, now < yesterdayWindow.end {
                return activeSnapshot(now: now, window: yesterdayWindow, config: cfg)
            }
        }

        if let overtimeSnapshot = activeOvertimeSnapshot(now: now, config: cfg, calendar: calendar) {
            return overtimeSnapshot
        }

        guard let todayWindow = makeWorkWindow(startingOn: today, calendar: calendar, config: cfg) else {
            return Snapshot(
                todayEarnings: 0,
                status: .dayOff,
                statusText: "今日休息",
                earningsPerSecond: fallbackSalaryPerSecond,
                progress: 0,
                effectiveDailySalary: fallbackDailySalary,
                effectiveWorkTime: fallbackWorkTime,
                effectivePaidWorkMinutes: fallbackPaidWorkMinutes
            )
        }

        if now < todayWindow.start {
            let waitMinutes = Int(todayWindow.start.timeIntervalSince(now) / 60)
            let h = waitMinutes / 60
            let m = waitMinutes % 60
            return Snapshot(
                todayEarnings: 0,
                status: .notStarted,
                statusText: h > 0 ? "距上班 \(h)时\(m)分" : "距上班 \(m)分钟",
                earningsPerSecond: todayWindow.salaryPerSecond,
                progress: 0,
                effectiveDailySalary: todayWindow.dailySalary,
                effectiveWorkTime: todayWindow.workTime,
                effectivePaidWorkMinutes: todayWindow.paidWorkMinutes
            )
        }

        if now >= todayWindow.end {
            return finishedSnapshot(now: now, window: todayWindow, config: cfg)
        }

        return activeSnapshot(now: now, window: todayWindow, config: cfg)
    }

    private func activeSnapshot(now: Date, window: WorkWindow, config cfg: SalaryConfig) -> Snapshot {
        if let clockOut = workSessionTracker.clockOutSession(for: window.start, calendar: .current),
           now >= clockOut.start {
            return Snapshot(
                todayEarnings: window.dailySalary,
                status: .clockedOutEarly,
                statusText: "提前 \(formatClock(clockOut.start)) 下班",
                earningsPerSecond: window.salaryPerSecond,
                progress: 1.0,
                effectiveDailySalary: window.dailySalary,
                effectiveWorkTime: window.workTime,
                effectivePaidWorkMinutes: window.paidWorkMinutes
            )
        }

        let earnings = calculateEarningsUpToNow(now: now, window: window, config: cfg)
        let progress = timeProgress(now: now, window: window)

        if let breakName = currentBreakName(now: now, window: window, config: cfg) {
            return Snapshot(
                todayEarnings: earnings,
                status: .onBreak(breakName: breakName),
                statusText: breakName + "中",
                earningsPerSecond: window.salaryPerSecond,
                progress: progress,
                effectiveDailySalary: window.dailySalary,
                effectiveWorkTime: window.workTime,
                effectivePaidWorkMinutes: window.paidWorkMinutes
            )
        }

        let remainingSeconds = window.end.timeIntervalSince(now)
        let remainingMinutes = Int(remainingSeconds / 60)
        let h = remainingMinutes / 60
        let m = remainingMinutes % 60
        return Snapshot(
            todayEarnings: earnings,
            status: .working,
            statusText: h > 0 ? "距下班 \(h)时\(m)分" : "距下班 \(m)分钟",
            earningsPerSecond: window.salaryPerSecond,
            progress: progress,
            effectiveDailySalary: window.dailySalary,
            effectiveWorkTime: window.workTime,
            effectivePaidWorkMinutes: window.paidWorkMinutes
        )
    }

    private func activeOvertimeSnapshot(now: Date, config cfg: SalaryConfig, calendar: Calendar) -> Snapshot? {
        guard SalaryWorkTimeline.activeWindow(containing: now, config: cfg, calendar: calendar) == nil,
              let activeOvertime = workSessionTracker.activeOvertimeSession(now: now, config: cfg, calendar: calendar),
              let window = makeWorkWindow(startingOn: activeOvertime.workday, calendar: calendar, config: cfg),
              now >= window.end else {
            return nil
        }

        return finishedSnapshot(now: now, window: window, config: cfg)
    }

    private func finishedSnapshot(now: Date, window: WorkWindow, config cfg: SalaryConfig) -> Snapshot {
        let activeOvertime = workSessionTracker.activeOvertimeSession(now: now, config: cfg)
        let status: WorkStatus
        let statusText: String

        if let overtime = activeOvertime,
           Calendar.current.isDate(overtime.workday, inSameDayAs: window.start) {
            status = .overtime
            statusText = overtimeStatusText(now: now, overtime: overtime)
        } else if workSessionTracker.clockOutSession(for: window.start) != nil {
            status = .clockedOutEarly
            statusText = "已提前下班"
        } else {
            status = .finished
            statusText = "今日已收工"
        }

        return Snapshot(
            todayEarnings: window.dailySalary,
            status: status,
            statusText: statusText,
            earningsPerSecond: window.salaryPerSecond,
            progress: 1.0,
            effectiveDailySalary: window.dailySalary,
            effectiveWorkTime: window.workTime,
            effectivePaidWorkMinutes: window.paidWorkMinutes
        )
    }

    /// 将某个自然日展开成真实工作窗口，跨夜时 end 会落到次日。
    private func makeWorkWindow(startingOn day: Date, calendar: Calendar, config: SalaryConfig) -> WorkWindow? {
        guard shouldCountToday(day, config: config) else { return nil }
        let workTime = config.effectiveWorkTime(on: day, calendar: calendar)
        let workDurationMinutes = config.workDurationMinutes(for: workTime)
        guard workDurationMinutes > 0 else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .minute, value: workTime.startMinutes, to: dayStart),
              let end = calendar.date(byAdding: .minute, value: workTime.startMinutes + workDurationMinutes, to: dayStart) else {
            return nil
        }
        return WorkWindow(
            start: start,
            end: end,
            workTime: workTime,
            dailySalary: config.effectiveDailySalary(on: day, calendar: calendar),
            salaryPerSecond: config.salaryPerSecond(on: day, calendar: calendar),
            paidWorkMinutes: config.paidWorkMinutes(workTime: workTime)
        )
    }

    private func shouldCountToday(_ date: Date, config: SalaryConfig) -> Bool {
        config.shouldCountSalary(on: date)
    }

    private func currentBreakName(now: Date, window: WorkWindow, config: SalaryConfig) -> String? {
        // 当前分钟使用展开后的工作时间轴，跨夜时可能大于 24:00。
        let currentMinute = config.workTimelineStartMinutes(for: window.workTime) + Int(now.timeIntervalSince(window.start) / 60)
        if config.usesLunchBreak,
           config.clampedIntervalsInWorkTime(for: config.lunchBreak, workTime: window.workTime).contains(where: { currentMinute >= $0.startMinutes && currentMinute < $0.endMinutes }) {
            return "午休"
        }
        if config.dinnerBreakEnabled,
           config.clampedIntervalsInWorkTime(for: config.dinnerBreak, workTime: window.workTime).contains(where: { currentMinute >= $0.startMinutes && currentMinute < $0.endMinutes }) {
            return "晚饭"
        }
        return nil
    }

    private func calculateEarningsUpToNow(now: Date, window: WorkWindow, config: SalaryConfig) -> Double {
        let workDurationSeconds = Double(config.workDurationMinutes(for: window.workTime)) * 60
        let elapsedWorkSeconds = min(max(0, now.timeIntervalSince(window.start)), workDurationSeconds)

        if config.countsBreakTimeAsPaidWork {
            return min(window.dailySalary, max(0, elapsedWorkSeconds * window.salaryPerSecond))
        }

        var elapsedBreakSeconds: Double = 0
        for interval in config.breakIntervalsWithinWorkTime(workTime: window.workTime) {
            // 只扣除“已经发生”的休息时间，避免休息段之后的收入提前被扣完。
            let breakStart = Double(interval.startMinutes - config.workTimelineStartMinutes(for: window.workTime)) * 60
            let breakEnd = Double(interval.endMinutes - config.workTimelineStartMinutes(for: window.workTime)) * 60
            let overlapStart = max(0, breakStart)
            let overlapEnd = min(elapsedWorkSeconds, breakEnd)

            if overlapEnd > overlapStart {
                elapsedBreakSeconds += overlapEnd - overlapStart
            }
        }

        let paidElapsedSeconds = max(0, elapsedWorkSeconds - elapsedBreakSeconds)
        return min(window.dailySalary, paidElapsedSeconds * window.salaryPerSecond)
    }

    /// 时间进度按完整工作窗口计算，不受休息时间是否计薪影响。
    private func timeProgress(now: Date, window: WorkWindow) -> Double {
        let duration = window.end.timeIntervalSince(window.start)
        guard duration > 0 else { return 0 }
        return min(1.0, max(0, now.timeIntervalSince(window.start) / duration))
    }

    private func overtimeStatusText(now: Date, overtime: OvertimeSession) -> String {
        let remainingMinutes = max(0, Int(overtime.end.timeIntervalSince(now) / 60))
        let h = remainingMinutes / 60
        let m = remainingMinutes % 60
        if h > 0 {
            return "加班至 \(formatClock(overtime.end))，剩 \(h)时\(m)分"
        }
        return "加班至 \(formatClock(overtime.end))，剩 \(m)分钟"
    }

    private func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var formattedEarnings: String {
        formatMoney(todayEarnings)
    }

    func formattedEarnings(showCurrencySymbol: Bool) -> String {
        formatMoney(todayEarnings, showCurrencySymbol: showCurrencySymbol)
    }

    var formattedSecondSalary: String {
        formatMoney(earningsPerSecond)
    }

    var formattedMinuteSalary: String {
        formatMoney(earningsPerSecond * 60)
    }

    var formattedHourlySalary: String {
        formatMoney(earningsPerSecond * 3600)
    }

    var formattedDailySalary: String {
        formatMoney(effectiveDailySalary)
    }

    var formattedMonthlySalary: String {
        formatMoney(config.monthlySalary)
    }

    var formattedYearlySalary: String {
        formatMoney(config.yearlySalary)
    }

    var effectiveWorkTimelineStartMinutes: Int {
        config.workTimelineStartMinutes(for: effectiveWorkTime)
    }

    var effectiveWorkTimelineEndMinutes: Int {
        config.workTimelineEndMinutes(for: effectiveWorkTime)
    }

    var effectiveWorkDurationMinutes: Int {
        config.workDurationMinutes(for: effectiveWorkTime)
    }

    func clampedIntervalsInEffectiveWorkTime(for range: TimeRange) -> [(startMinutes: Int, endMinutes: Int)] {
        config.clampedIntervalsInWorkTime(for: range, workTime: effectiveWorkTime)
    }

    private func formatMoney(_ value: Double, showCurrencySymbol: Bool = true) -> String {
        let amount = String(format: "%.\(config.displayDecimalPlaces)f", value)
        return showCurrencySymbol ? "¥\(amount)" : amount
    }
}
