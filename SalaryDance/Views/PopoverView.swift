import SwiftUI

/// 状态栏点击或快捷键打开后的弹窗主视图，负责拼装薪资区、语录区和底部操作。
struct PopoverView: View {
    @ObservedObject var viewModel: SalaryViewModel
    @ObservedObject var statusBarController: StatusBarController
    @ObservedObject private var configManager = SalaryConfigManager.shared
    @ObservedObject private var offTaskTracker = OffTaskTracker.shared
    @ObservedObject private var workSessionTracker = WorkSessionTracker.shared
    @StateObject private var quoteState = WorkQuoteState()
    @State private var overtimeHours = 1
    @State private var overtimeMinutes = 0

    /// 弹窗内容全部受展示配置控制，用户关闭某类信息后不保留对应空位。
    var body: some View {
        let config = configManager.config
        // 薪资主块可以只显示状态、只显示进度、只显示金额或任意组合。
        let showsSalaryBlock = config.popoverDisplaysWorkStatus
            || config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate
            || config.popoverDisplaysWorkProgress
        let showsOffTaskPanel = config.popoverDisplaysAnyOffTaskInformation
        let showsWorkSessionPanel = config.popoverDisplaysAnyWorkSessionInformation
            && workSessionTracker.shouldShowPopoverPanel(config: config)
        // 只有存在敏感金额时才展示眼睛按钮，否则弹窗不出现无意义操作。
        let showsSalarySensitiveContent = config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate
        let showsWorkSessionSensitiveContent = showsWorkSessionPanel
        let showsOffTaskSensitiveContent = config.popoverDisplaysAnyOffTaskSalaryMetric
            || config.popoverDisplaysTodayOffTaskSummary

        VStack(spacing: 12) {
            if showsSalaryBlock {
                SalaryDisplayView(
                    viewModel: viewModel,
                    isPrivate: statusBarController.isContentMasked,
                    showsStatus: config.popoverDisplaysWorkStatus,
                    showsEarnings: config.popoverDisplaysCurrentEarnings,
                    showsRemainingEarnings: config.popoverDisplaysRemainingEarnings,
                    showsSecondSalary: config.popoverDisplaysSecondSalary,
                    showsMinuteSalary: config.popoverDisplaysMinuteSalary,
                    showsHourlySalary: config.popoverDisplaysHourlySalary,
                    showsDailySalary: config.popoverDisplaysDailySalary,
                    showsMonthlySalary: config.popoverDisplaysMonthlySalary,
                    showsYearlySalary: config.popoverDisplaysYearlySalary,
                    showsWorkProgress: config.popoverDisplaysWorkProgress,
                    earningsActionSystemImage: showsSalarySensitiveContent ? (statusBarController.isContentMasked ? "eye" : "eye.slash") : nil,
                    earningsAction: showsSalarySensitiveContent ? {
                        if statusBarController.isContentMasked {
                            statusBarController.revealContent()
                        } else {
                            statusBarController.hideContent()
                        }
                    } : nil
                )
            }

            if showsOffTaskPanel {
                offTaskPanel(
                    config: config,
                    showsPrivacyAction: showsOffTaskSensitiveContent && !showsSalarySensitiveContent
                )
            }

            if showsWorkSessionPanel {
                workSessionPanel(
                    config: config,
                    showsPrivacyAction: showsWorkSessionSensitiveContent && !showsSalarySensitiveContent && !showsOffTaskSensitiveContent
                )
            }

            if (showsSalaryBlock || showsWorkSessionPanel || showsOffTaskPanel) && config.popoverDisplaysQuote {
                Divider()
                    .padding(.horizontal, 16)
            }

            if config.popoverDisplaysQuote {
                VStack(spacing: 2) {
                    Text(quoteState.currentQuote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 32)
                        .fixedSize(horizontal: false, vertical: true)

                    footerButton("换一句", systemImage: "arrow.clockwise", compact: true) {
                        quoteState.refresh()
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                footerButton("设置", systemImage: "gearshape") {
                    statusBarController.showSettings()
                }

                Spacer(minLength: 12)

                footerButton("退出应用", systemImage: "power") {
                    statusBarController.quitApplication()
                }
            }
            .padding(.horizontal, 16)

        }
        .padding(.top, 15)
        .padding(.bottom, 12)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func workSessionPanel(config: SalaryConfig, showsPrivacyAction: Bool) -> some View {
        let summary = workSessionTracker.currentSummary(config: config)
        let clockOutAvailability = workSessionTracker.clockOutAvailability(config: config)
        let overtimeAvailability = workSessionTracker.overtimeAvailability(config: config)
        let clockOutSession = workSessionTracker.clockOutSession(for: summary.workday)
        let latestOvertime = workSessionTracker.latestOvertimeSession(for: summary.workday)
        let activeOvertime = workSessionTracker.activeOvertimeSession(config: config)
        let hasSelectedOvertimeDuration = selectedOvertimeMinutes > 0
        let canStartOvertime = overtimeAvailability.canStart && hasSelectedOvertimeDuration

        return WorkSessionPopoverPanelView(
            isPrivate: statusBarController.isContentMasked,
            title: workSessionTitle(clockOutSession: clockOutSession, activeOvertime: activeOvertime),
            subtitle: workSessionSubtitle(
                summary: summary,
                clockOutAvailability: clockOutAvailability,
                overtimeAvailability: overtimeAvailability,
                clockOutSession: clockOutSession,
                activeOvertime: activeOvertime
            ),
            activeOvertimeSummary: config.popoverDisplaysTodayWorkSessionSummary ? activeOvertimeSummary(activeOvertime) : nil,
            summaryText: config.popoverDisplaysTodayWorkSessionSummary && activeOvertime == nil ? workSessionSummaryText(summary) : nil,
            showsPrivacyAction: showsPrivacyAction,
            showsStatus: config.popoverDisplaysWorkSessionStatus,
            showsClockOutAction: config.popoverDisplaysClockOutAction,
            showsOvertimeAction: config.popoverDisplaysOvertimeAction,
            canClockOut: clockOutAvailability.canClockOut,
            hasClockOut: clockOutSession != nil,
            canEditOvertimeDuration: overtimeAvailability.canStart,
            canStartOvertime: canStartOvertime,
            canEndOvertime: activeOvertime != nil,
            canUndoOvertime: latestOvertime != nil,
            overtimeIsActive: activeOvertime != nil,
            overtimeHours: $overtimeHours,
            overtimeMinutes: $overtimeMinutes,
            clockOutHelp: clockOutSession == nil ? clockOutAvailability.helpMessage : "撤回今日提前下班记录。",
            overtimeHelp: latestOvertime == nil
                ? (hasSelectedOvertimeDuration ? overtimeAvailability.helpMessage : "请先选择加班时长。")
                : "撤回最近一条加班记录。",
            endOvertimeHelp: "按当前时间结束本次加班并进入结算。",
            privacyAction: {
                if statusBarController.isContentMasked {
                    statusBarController.revealContent()
                } else {
                    statusBarController.hideContent()
                }
            },
            clockOutAction: {
                if let clockOutSession {
                    workSessionTracker.undoClockOut(for: clockOutSession.workday)
                } else {
                    if offTaskTracker.isActive {
                        offTaskTracker.stop()
                    }
                    workSessionTracker.clockOut(config: config)
                }
                viewModel.refreshNow()
            },
            overtimeAction: {
                if latestOvertime != nil {
                    workSessionTracker.undoLatestOvertime(config: config)
                } else {
                    guard selectedOvertimeMinutes > 0 else {
                        return
                    }
                    workSessionTracker.startOvertime(minutes: selectedOvertimeMinutes, config: config)
                }
                viewModel.refreshNow()
            },
            endOvertimeAction: {
                workSessionTracker.endActiveOvertime(config: config)
                viewModel.refreshNow()
            }
        )
    }

    private func workSessionTitle(clockOutSession: ClockOutSession?, activeOvertime: OvertimeSession?) -> String {
        if activeOvertime != nil {
            return "加班中"
        }
        if clockOutSession != nil {
            return "已提前下班"
        }
        return "提前下班与加班"
    }

    private func workSessionSubtitle(
        summary: WorkSessionDailySummary,
        clockOutAvailability: ClockOutAvailability,
        overtimeAvailability: OvertimeAvailability,
        clockOutSession: ClockOutSession?,
        activeOvertime: OvertimeSession?
    ) -> String {
        if let activeOvertime {
            return "到 \(formatOffTaskTime(activeOvertime.end))，已亏 \(formatWorkSessionMoney(summary.overtimeAmount))"
        }
        if let clockOutSession {
            return "提前 \(formatOffTaskTime(clockOutSession.start)) 下班"
        }
        if clockOutAvailability.canClockOut {
            return clockOutAvailability.shortMessage
        }
        if overtimeAvailability.canStart {
            return overtimeAvailability.shortMessage
        }
        return summary.hasRecords ? "今日已记录" : clockOutAvailability.shortMessage
    }

    private var selectedOvertimeMinutes: Int {
        overtimeHours * 60 + overtimeMinutes
    }

    private func workSessionSummaryText(_ summary: WorkSessionDailySummary) -> String? {
        if summary.overtimeSeconds > 0 {
            return "今日已加班 \(formatOffTaskDuration(summary.overtimeSeconds))，按当前时薪折算多干 \(formatWorkSessionMoney(summary.overtimeAmount))。"
        }

        if summary.clockOutSeconds > 0 {
            return "今日提前下班 \(formatOffTaskDuration(summary.clockOutSeconds))，剩余 \(formatWorkSessionMoney(summary.clockOutAmount)) 直接进账。"
        }

        return nil
    }

    private func activeOvertimeSummary(_ activeOvertime: OvertimeSession?) -> WorkSessionActiveOvertimeSummary? {
        guard let activeOvertime else {
            return nil
        }

        let now = Date()
        let plannedSeconds = max(0, activeOvertime.end.timeIntervalSince(activeOvertime.start))
        let elapsedSeconds = max(0, min(now, activeOvertime.end).timeIntervalSince(activeOvertime.start))
        let plannedAmount = workSessionAmount(seconds: plannedSeconds, workday: activeOvertime.workday)
        let elapsedAmount = workSessionAmount(seconds: elapsedSeconds, workday: activeOvertime.workday)

        return WorkSessionActiveOvertimeSummary(
            plannedDuration: formatWorkSessionLiveDuration(plannedSeconds),
            plannedDurationValue: plannedSeconds,
            plannedAmount: formatWorkSessionMoney(plannedAmount),
            plannedAmountValue: plannedAmount,
            elapsedDuration: formatWorkSessionLiveDuration(elapsedSeconds),
            elapsedDurationValue: elapsedSeconds,
            elapsedAmount: formatWorkSessionMoney(elapsedAmount),
            elapsedAmountValue: elapsedAmount
        )
    }

    private func workSessionAmount(seconds: TimeInterval, workday: Date) -> Double {
        guard let window = SalaryWorkTimeline.workWindow(startingOn: workday, config: configManager.config) else {
            return 0
        }
        return max(0, seconds) * window.salaryPerSecond
    }

    /// 摸鱼状态面板承载开关和可选统计指标；指标默认关闭，避免弹窗初始信息过载。
    private func offTaskPanel(config: SalaryConfig, showsPrivacyAction: Bool) -> some View {
        let summary = offTaskTracker.currentSummary(config: config)
        let isActive = offTaskTracker.isActive
        let availability = offTaskTracker.startAvailability(config: config)
        let metrics = offTaskPanelMetrics(config: config, today: summary)

        return OffTaskPopoverPanelView(
            showsStatus: config.popoverDisplaysOffTaskStatus,
            isActive: isActive,
            canStart: availability.canStart,
            isPrivate: statusBarController.isContentMasked,
            subtitle: offTaskSubtitle(isActive: isActive, availability: availability, summary: summary),
            metrics: metrics,
            summaryText: config.popoverDisplaysTodayOffTaskSummary ? offTaskDailySummaryText(summary) : nil,
            showsPrivacyAction: showsPrivacyAction,
            toggleHelp: offTaskToggleHelp(isActive: isActive, availability: availability),
            privacyAction: {
                if statusBarController.isContentMasked {
                    statusBarController.revealContent()
                } else {
                    statusBarController.hideContent()
                }
            },
            toggleAction: {
                offTaskTracker.toggle(config: config)
                viewModel.refreshNow()
            }
        )
    }

    private func offTaskSubtitle(isActive: Bool, availability: OffTaskStartAvailability, summary: OffTaskDailySummary) -> String {
        if isActive, let start = offTaskTracker.activeSessionStart {
            return "从 \(formatOffTaskTime(start)) 开始"
        }
        if summary.isWorkFinished {
            return summary.hasRecords ? "今日已结算" : "今日无记录"
        }
        return availability.shortMessage
    }

    private func offTaskToggleHelp(isActive: Bool, availability: OffTaskStartAvailability) -> String {
        isActive ? "结束当前摸鱼记录" : availability.helpMessage
    }

    private func offTaskDailySummaryText(_ summary: OffTaskDailySummary) -> String {
        guard summary.hasRecords else {
            return "今日摸鱼：暂无摸鱼记录"
        }

        let dailySalary = configManager.config.effectiveDailySalary(on: summary.workday)
        let percent = dailySalary > 0
            ? summary.amount / dailySalary * 100
            : 0
        return "今日摸鱼：\(formatOffTaskDuration(summary.paidSeconds))，\(formatOffTaskMoney(summary.amount))，占今日收入 \(String(format: "%.1f%%", percent))"
    }

    private func offTaskPanelMetrics(config: SalaryConfig, today: OffTaskDailySummary) -> [SalaryMetricItem] {
        guard config.popoverDisplaysAnyOffTaskMetric else {
            return []
        }

        let now = Date()
        let cycleTitle = offTaskSettlementPeriodTitle(config)
        var cachedWeekSummary: OffTaskAggregateSummary?
        var cachedCycleSummary: OffTaskAggregateSummary?
        var cachedTotalSummary: OffTaskAggregateSummary?

        func weekSummary() -> OffTaskAggregateSummary {
            if let cachedWeekSummary { return cachedWeekSummary }
            let week = offTaskWeekPeriod(containing: now)
            let summary = offTaskTracker.summary(from: week.start, toExclusive: week.endExclusive, config: config, now: now)
            cachedWeekSummary = summary
            return summary
        }

        func cycleSummary() -> OffTaskAggregateSummary {
            if let cachedCycleSummary { return cachedCycleSummary }
            let salaryCycle = config.salaryCyclePeriod(containing: now)
            let summary = offTaskTracker.summary(from: salaryCycle.start, toExclusive: salaryCycle.endExclusive, config: config, now: now)
            cachedCycleSummary = summary
            return summary
        }

        func totalSummary() -> OffTaskAggregateSummary {
            if let cachedTotalSummary { return cachedTotalSummary }
            let summary = offTaskTracker.totalSummary(config: config, now: now)
            cachedTotalSummary = summary
            return summary
        }

        var metrics: [SalaryMetricItem] = []

        if config.popoverDisplaysTodayOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskTodaySalary", title: "本日摸鱼薪资", value: offTaskMoneyValue(today.amount)))
        }
        if config.popoverDisplaysWeekOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskWeekSalary", title: "本周摸鱼薪资", value: offTaskMoneyValue(weekSummary().amount)))
        }
        if config.popoverDisplaysSalaryCycleOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskCycleSalary", title: "\(cycleTitle)摸鱼薪资", value: offTaskMoneyValue(cycleSummary().amount)))
        }
        if config.popoverDisplaysHistoricalOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskTotalSalary", title: "历史摸鱼薪资", value: offTaskMoneyValue(totalSummary().amount)))
        }
        if config.popoverDisplaysTodayOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskTodayDuration", title: "本日摸鱼时长", value: formatOffTaskDuration(today.paidSeconds), isSensitive: false))
        }
        if config.popoverDisplaysWeekOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskWeekDuration", title: "本周摸鱼时长", value: formatOffTaskDuration(weekSummary().paidSeconds), isSensitive: false))
        }
        if config.popoverDisplaysSalaryCycleOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskCycleDuration", title: "\(cycleTitle)摸鱼时长", value: formatOffTaskDuration(cycleSummary().paidSeconds), isSensitive: false))
        }
        if config.popoverDisplaysHistoricalOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskTotalDuration", title: "历史摸鱼时长", value: formatOffTaskDuration(totalSummary().paidSeconds), isSensitive: false))
        }

        return metrics
    }

    /// 底部和“换一句”共用的按钮样式，contentShape 覆盖图标和文字之间的空白区域。
    private func footerButton(_ title: String, systemImage: String, compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(compact ? .caption2 : .caption)
                    .frame(width: compact ? 11 : 13, height: compact ? 11 : 13)

                Text(title)
                    .font(compact ? .caption2 : .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(minWidth: compact ? 56 : 72, minHeight: compact ? 20 : 28)
            .padding(.horizontal, compact ? 4 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .contentShape(Rectangle())
        .focusable(false)
    }

    private func formatOffTaskMoney(_ value: Double) -> String {
        guard !statusBarController.isContentMasked else { return "¥***" }
        return offTaskMoneyValue(value)
    }

    private func formatWorkSessionMoney(_ value: Double) -> String {
        guard !statusBarController.isContentMasked else { return "¥***" }
        return workSessionMoneyValue(value)
    }

    private func offTaskMoneyValue(_ value: Double) -> String {
        let amount = String(format: "%.\(configManager.config.displayDecimalPlaces)f", value)
        return "¥\(amount)"
    }

    private func workSessionMoneyValue(_ value: Double) -> String {
        offTaskMoneyValue(value)
    }

    private func formatOffTaskDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds.rounded(.down)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)时\(minutes)分"
        }
        return "\(minutes)分"
    }

    private func formatWorkSessionDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)时\(minutes)分"
        }
        if minutes > 0 {
            return "\(minutes)分"
        }
        return "\(seconds)秒"
    }

    private func formatWorkSessionLiveDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)时\(minutes)分\(seconds)秒"
        }
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        }
        return "\(seconds)秒"
    }

    private func formatOffTaskTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func offTaskWeekPeriod(containing date: Date, calendar: Calendar = .current) -> (start: Date, endExclusive: Date) {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let mappedWeekday = weekday == 1 ? 7 : weekday - 1
        let start = calendar.date(byAdding: .day, value: 1 - mappedWeekday, to: day) ?? day
        let endExclusive = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, endExclusive)
    }

    private func offTaskSettlementPeriodTitle(_ config: SalaryConfig) -> String {
        config.resolvedSalaryCycleMode == .naturalMonth ? "本月" : "本周期"
    }
}

/// 提前下班与加班弹窗面板只承载当下操作和一句反馈，完整数据放到设置页记录中。
struct WorkSessionActiveOvertimeSummary: Equatable {
    let plannedDuration: String
    let plannedDurationValue: Double
    let plannedAmount: String
    let plannedAmountValue: Double
    let elapsedDuration: String
    let elapsedDurationValue: Double
    let elapsedAmount: String
    let elapsedAmountValue: Double
}

struct WorkSessionPopoverPanelView: View {
    let isPrivate: Bool
    let title: String
    let subtitle: String
    let activeOvertimeSummary: WorkSessionActiveOvertimeSummary?
    let summaryText: String?
    let showsPrivacyAction: Bool
    let showsStatus: Bool
    let showsClockOutAction: Bool
    let showsOvertimeAction: Bool
    let canClockOut: Bool
    let hasClockOut: Bool
    let canEditOvertimeDuration: Bool
    let canStartOvertime: Bool
    let canEndOvertime: Bool
    let canUndoOvertime: Bool
    let overtimeIsActive: Bool
    @Binding var overtimeHours: Int
    @Binding var overtimeMinutes: Int
    let clockOutHelp: String
    let overtimeHelp: String
    let endOvertimeHelp: String
    let privacyAction: () -> Void
    let clockOutAction: () -> Void
    let overtimeAction: () -> Void
    let endOvertimeAction: () -> Void

    private var tint: Color {
        overtimeIsActive ? .indigo : (hasClockOut ? .green : .blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsStatus {
                statusRow
            }

            if showsClockOutAction || showsOvertimeAction || showsPrivacyAction {
                actionRow
            }

            if showsOvertimeAction && canEditOvertimeDuration && !canUndoOvertime {
                durationRow
            }

            if let activeOvertimeSummary {
                activeOvertimeSummaryView(activeOvertimeSummary)
            } else if let summaryText {
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: summaryText)
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func activeOvertimeSummaryView(_ summary: WorkSessionActiveOvertimeSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("预计加班 ")
                rollingSummaryText(summary.plannedDuration, value: summary.plannedDurationValue)
                Text("，按当前时薪折算多干 ")
                rollingSummaryText(summary.plannedAmount, value: summary.plannedAmountValue)
                Text("；")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            HStack(spacing: 0) {
                Text("目前已加班 ")
                rollingSummaryText(summary.elapsedDuration, value: summary.elapsedDurationValue)
                Text("，多干 ")
                rollingSummaryText(summary.elapsedAmount, value: summary.elapsedAmountValue)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(tint)
    }

    private func rollingSummaryText(_ text: String, value: Double) -> some View {
        Text(text)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.18), value: value)
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Image(systemName: overtimeIsActive ? "timer" : (hasClockOut ? "checkmark.circle.fill" : "clock"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if showsClockOutAction && !overtimeIsActive {
                Button(action: clockOutAction) {
                    Label(hasClockOut ? "撤回提前下班" : "提前下班", systemImage: hasClockOut ? "arrow.uturn.backward" : "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(hasClockOut ? .secondary : .white)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(
                    Capsule()
                        .fill(hasClockOut ? Color(nsColor: .controlBackgroundColor) : Color.green)
                )
                .overlay(
                    Capsule()
                        .stroke(hasClockOut ? Color(nsColor: .separatorColor).opacity(0.45) : Color.green.opacity(0.35), lineWidth: 1)
                )
                .disabled(!hasClockOut && !canClockOut)
                .opacity(!hasClockOut && !canClockOut ? 0.55 : 1)
                .help(clockOutHelp)
                .focusable(false)
            }

            Spacer(minLength: 0)

            if showsOvertimeAction {
                if overtimeIsActive {
                    Button(action: endOvertimeAction) {
                        Label("提前终止", systemImage: "stop.circle.fill")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(Color.indigo))
                    .overlay(Capsule().stroke(Color.indigo.opacity(0.35), lineWidth: 1))
                    .disabled(!canEndOvertime)
                    .help(endOvertimeHelp)
                    .focusable(false)

                    Button(action: overtimeAction) {
                        Label("撤回", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1))
                    .help(overtimeHelp)
                    .focusable(false)
                } else if canUndoOvertime {
                    Button(action: overtimeAction) {
                        Label("撤回加班", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1))
                    .help(overtimeHelp)
                    .focusable(false)
                } else {
                    Button(action: overtimeAction) {
                        Label("加班", systemImage: "plus.circle.fill")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(canStartOvertime ? .white : .secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(
                        Capsule()
                            .fill(canStartOvertime ? Color.indigo : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        Capsule()
                            .stroke(canStartOvertime ? Color.indigo.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                    )
                    .disabled(!canStartOvertime)
                    .help(overtimeHelp)
                    .focusable(false)
                }
            }

            if showsPrivacyAction {
                privacyButton
            }
        }
    }

    private var durationRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("加班时长")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                WorkSessionDurationInput(
                    title: "小时",
                    unit: "时",
                    value: $overtimeHours,
                    range: 0...12,
                    step: 1
                )

                WorkSessionDurationInput(
                    title: "分钟",
                    unit: "分",
                    value: $overtimeMinutes,
                    range: 0...59,
                    step: 5
                )
            }
        }
        .controlSize(.small)
        .disabled(!canEditOvertimeDuration)
        .opacity(canEditOvertimeDuration ? 1 : 0.55)
    }

    private var privacyButton: some View {
        Button(action: privacyAction) {
            Image(systemName: isPrivate ? "eye" : "eye.slash")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .focusable(false)
    }

}

private struct WorkSessionDurationInput: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                TextField("", value: clampedValue, format: .number)
                    .textFieldStyle(.plain)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 28)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                VStack(spacing: 0) {
                    durationAdjustButton(systemImage: "chevron.up") {
                        adjust(by: step)
                    }
                    durationAdjustButton(systemImage: "chevron.down") {
                        adjust(by: -step)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 7)
            .padding(.trailing, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 1)
            )
        }
        .frame(width: 76, alignment: .leading)
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { newValue in
                value = clamped(newValue)
            }
        )
    }

    private func durationAdjustButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .focusable(false)
    }

    private func adjust(by delta: Int) {
        value = clamped(value + delta)
    }

    private func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// 摸鱼状态弹窗面板由真实弹窗和设置预览共用，避免按钮、脱敏和指标布局出现两套实现。
struct OffTaskPopoverPanelView: View {
    let showsStatus: Bool
    let isActive: Bool
    let canStart: Bool
    let isPrivate: Bool
    let subtitle: String
    let metrics: [SalaryMetricItem]
    let summaryText: String?
    let showsPrivacyAction: Bool
    let toggleHelp: String
    let privacyAction: () -> Void
    let toggleAction: () -> Void

    private var isToggleDisabled: Bool {
        !isActive && !canStart
    }

    private var tint: Color {
        isActive ? .orange : Color(nsColor: .secondaryLabelColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsStatus {
                statusRow
            } else if showsPrivacyAction {
                HStack {
                    Spacer(minLength: 0)
                    privacyButton
                }
            }

            if !metrics.isEmpty {
                BalancedSalaryMetricGrid(
                    metrics: metrics,
                    isPrivate: isPrivate,
                    tint: .orange,
                    maxColumns: 2,
                    spacing: 7,
                    rowHeight: 42,
                    cornerRadius: 7,
                    valueFont: .caption.weight(.semibold),
                    valueMinimumScaleFactor: 0.66
                )
            }

            if let summaryText {
                Text(summaryText)
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: summaryText)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(tint.opacity(isActive ? 0.18 : 0.10))
                Image(systemName: isActive ? "fish.fill" : "fish")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(isActive ? "摸鱼中" : "摸鱼状态")
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsPrivacyAction {
                privacyButton
            }

            toggleButton
        }
        .help(toggleHelp)
    }

    private var privacyButton: some View {
        Button(action: privacyAction) {
            Image(systemName: isPrivate ? "eye" : "eye.slash")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .focusable(false)
    }

    private var toggleButton: some View {
        Button(action: toggleAction) {
            HStack(spacing: 4) {
                Image(systemName: isActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(isActive ? "结束" : "开启")
                    .font(.caption2.weight(.semibold))
            }
            .frame(minWidth: 48, minHeight: 24)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isActive ? .white : .primary)
        .background(
            Capsule()
                .fill(isActive ? Color.orange : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(isActive ? Color.orange.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .disabled(isToggleDisabled)
        .opacity(isToggleDisabled ? 0.55 : 1)
        .focusable(false)
        .help(toggleHelp)
    }
}
