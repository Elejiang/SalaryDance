import Foundation
import Combine

/// 今日工作状态，用于弹窗的图标、文案和颜色。
enum WorkStatus: Equatable {
    case notStarted
    case working
    case onBreak(breakName: String)
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

    private var timer: Timer?
    private var updateInterval: TimeInterval = 1
    private let configManager = SalaryConfigManager.shared

    var config: SalaryConfig {
        configManager.config
    }

    init() {
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    /// 按当前刷新间隔启动定时器。
    func startTimer() {
        startTimer(interval: updateInterval)
    }

    /// 状态栏或弹窗显示状态变化时调整刷新频率。
    func setUpdateInterval(_ interval: TimeInterval) {
        let normalizedInterval = min(
            SalaryConfig.refreshIntervalRange.upperBound,
            max(SalaryConfig.refreshIntervalRange.lowerBound, interval)
        )
        guard abs(updateInterval - normalizedInterval) > 0.01 else { return }
        updateInterval = normalizedInterval
        startTimer(interval: normalizedInterval)
    }

    /// 配置变化或弹窗打开前立即刷新一次，避免展示旧值。
    func refreshNow() {
        update(force: true)
    }

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.update(force: false)
        }
        newTimer.tolerance = min(5, max(0.2, interval * 0.25))
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        update(force: true)
    }

    private struct Snapshot {
        let todayEarnings: Double
        let status: WorkStatus
        let statusText: String
        let earningsPerSecond: Double
        let progress: Double
    }

    private struct WorkWindow {
        let start: Date
        let end: Date
    }

    /// 只在值实际变化时发布，降低 SwiftUI 重绘频率。
    private func update(force: Bool) {
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
    }

    /// 生成当前时刻的完整展示快照，是实时刷新链路的核心入口。
    private func makeSnapshot() -> Snapshot {
        let cfg = configManager.config
        let now = Date()
        let calendar = Calendar.current

        guard cfg.workDurationMinutes > 0 else {
            return Snapshot(
                todayEarnings: 0,
                status: .dayOff,
                statusText: "工作时间未设置",
                earningsPerSecond: cfg.salaryPerSecond,
                progress: 0
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

        guard let todayWindow = makeWorkWindow(startingOn: today, calendar: calendar, config: cfg) else {
            return Snapshot(
                todayEarnings: 0,
                status: .dayOff,
                statusText: "今日休息",
                earningsPerSecond: cfg.salaryPerSecond,
                progress: 0
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
                earningsPerSecond: cfg.salaryPerSecond,
                progress: 0
            )
        }

        if now >= todayWindow.end {
            return Snapshot(
                todayEarnings: cfg.dailySalary,
                status: .finished,
                statusText: "今日已收工",
                earningsPerSecond: cfg.salaryPerSecond,
                progress: 1.0
            )
        }

        return activeSnapshot(now: now, window: todayWindow, config: cfg)
    }

    private func activeSnapshot(now: Date, window: WorkWindow, config cfg: SalaryConfig) -> Snapshot {
        let earnings = calculateEarningsUpToNow(now: now, window: window, config: cfg)
        let progress = timeProgress(now: now, window: window)

        if let breakName = currentBreakName(now: now, window: window, config: cfg) {
            return Snapshot(
                todayEarnings: earnings,
                status: .onBreak(breakName: breakName),
                statusText: breakName + "中",
                earningsPerSecond: cfg.salaryPerSecond,
                progress: progress
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
            earningsPerSecond: cfg.salaryPerSecond,
            progress: progress
        )
    }

    /// 将某个自然日展开成真实工作窗口，跨夜时 end 会落到次日。
    private func makeWorkWindow(startingOn day: Date, calendar: Calendar, config: SalaryConfig) -> WorkWindow? {
        guard config.workDurationMinutes > 0, shouldCountToday(day, config: config) else { return nil }
        let dayStart = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .minute, value: config.workTime.startMinutes, to: dayStart),
              let end = calendar.date(byAdding: .minute, value: config.workTime.startMinutes + config.workDurationMinutes, to: dayStart) else {
            return nil
        }
        return WorkWindow(start: start, end: end)
    }

    private func shouldCountToday(_ date: Date, config: SalaryConfig) -> Bool {
        config.shouldCountSalary(on: date)
    }

    private func currentBreakName(now: Date, window: WorkWindow, config: SalaryConfig) -> String? {
        // 当前分钟使用展开后的工作时间轴，跨夜时可能大于 24:00。
        let currentMinute = config.workTimelineStartMinutes + Int(now.timeIntervalSince(window.start) / 60)
        if config.usesLunchBreak,
           config.clampedIntervalsInWorkTime(for: config.lunchBreak).contains(where: { currentMinute >= $0.startMinutes && currentMinute < $0.endMinutes }) {
            return "午休"
        }
        if config.dinnerBreakEnabled,
           config.clampedIntervalsInWorkTime(for: config.dinnerBreak).contains(where: { currentMinute >= $0.startMinutes && currentMinute < $0.endMinutes }) {
            return "晚饭"
        }
        return nil
    }

    private func calculateEarningsUpToNow(now: Date, window: WorkWindow, config: SalaryConfig) -> Double {
        let workDurationSeconds = Double(config.workDurationMinutes) * 60
        let elapsedWorkSeconds = min(max(0, now.timeIntervalSince(window.start)), workDurationSeconds)

        if config.countsBreakTimeAsPaidWork {
            return min(config.dailySalary, max(0, elapsedWorkSeconds * config.salaryPerSecond))
        }

        var elapsedBreakSeconds: Double = 0
        for interval in config.breakIntervalsWithinWorkTime {
            // 只扣除“已经发生”的休息时间，避免休息段之后的收入提前被扣完。
            let breakStart = Double(interval.startMinutes - config.workTimelineStartMinutes) * 60
            let breakEnd = Double(interval.endMinutes - config.workTimelineStartMinutes) * 60
            let overlapStart = max(0, breakStart)
            let overlapEnd = min(elapsedWorkSeconds, breakEnd)

            if overlapEnd > overlapStart {
                elapsedBreakSeconds += overlapEnd - overlapStart
            }
        }

        let paidElapsedSeconds = max(0, elapsedWorkSeconds - elapsedBreakSeconds)
        return min(config.dailySalary, paidElapsedSeconds * config.salaryPerSecond)
    }

    /// 时间进度按完整工作窗口计算，不受休息时间是否计薪影响。
    private func timeProgress(now: Date, window: WorkWindow) -> Double {
        let duration = window.end.timeIntervalSince(window.start)
        guard duration > 0 else { return 0 }
        return min(1.0, max(0, now.timeIntervalSince(window.start) / duration))
    }

    var formattedEarnings: String {
        formatMoney(todayEarnings)
    }

    func formattedEarnings(showCurrencySymbol: Bool) -> String {
        formatMoney(todayEarnings, showCurrencySymbol: showCurrencySymbol)
    }

    var formattedSecondSalary: String {
        formatMoney(config.salaryPerSecond)
    }

    var formattedMinuteSalary: String {
        formatMoney(config.salaryPerMinute)
    }

    var formattedHourlySalary: String {
        formatMoney(config.salaryPerHour)
    }

    var formattedDailySalary: String {
        formatMoney(config.dailySalary)
    }

    var formattedMonthlySalary: String {
        formatMoney(config.monthlySalary)
    }

    var formattedYearlySalary: String {
        formatMoney(config.yearlySalary)
    }

    private func formatMoney(_ value: Double, showCurrencySymbol: Bool = true) -> String {
        let amount = String(format: "%.\(config.displayDecimalPlaces)f", value)
        return showCurrencySymbol ? "¥\(amount)" : amount
    }
}
