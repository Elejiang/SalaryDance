import SwiftUI

/// 状态栏点击或快捷键打开后的弹窗主视图，负责拼装薪资区、语录区和底部操作。
struct PopoverView: View {
    @ObservedObject var viewModel: SalaryViewModel
    @ObservedObject var statusBarController: StatusBarController
    @ObservedObject private var configManager = SalaryConfigManager.shared
    @ObservedObject private var offTaskTracker = OffTaskTracker.shared
    @StateObject private var quoteState = WorkQuoteState()

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
        // 只有存在敏感金额时才展示眼睛按钮，否则弹窗不出现无意义操作。
        let showsSalarySensitiveContent = config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate
        let showsOffTaskSensitiveContent = config.popoverDisplaysAnyOffTaskSalaryMetric

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

            if (showsSalaryBlock || showsOffTaskPanel) && config.popoverDisplaysQuote {
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
            finishedSummary: config.popoverDisplaysOffTaskStatus && summary.isWorkFinished ? offTaskFinishedSummaryText(summary) : nil,
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

    private func offTaskFinishedSummaryText(_ summary: OffTaskDailySummary) -> String {
        guard summary.hasRecords else {
            return "下班总结：今天没有摸鱼记录"
        }

        let percent = viewModel.effectiveDailySalary > 0
            ? summary.amount / viewModel.effectiveDailySalary * 100
            : 0
        return "下班总结：\(formatOffTaskDuration(summary.paidSeconds))，\(formatOffTaskMoney(summary.amount))，占今日收入 \(String(format: "%.1f%%", percent))"
    }

    private func offTaskPanelMetrics(config: SalaryConfig, today: OffTaskDailySummary) -> [SalaryMetricItem] {
        guard config.popoverDisplaysAnyOffTaskMetric else {
            return []
        }

        let now = Date()
        let week = offTaskWeekPeriod(containing: now)
        let salaryCycle = config.salaryCyclePeriod(containing: now)
        let weekSummary = offTaskTracker.summary(from: week.start, toExclusive: week.endExclusive, config: config, now: now)
        let cycleSummary = offTaskTracker.summary(from: salaryCycle.start, toExclusive: salaryCycle.endExclusive, config: config, now: now)
        let totalSummary = offTaskTracker.totalSummary(config: config, now: now)
        let cycleTitle = offTaskSettlementPeriodTitle(config)

        var metrics: [SalaryMetricItem] = []

        if config.popoverDisplaysTodayOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskTodaySalary", title: "本日摸鱼薪资", value: offTaskMoneyValue(today.amount)))
        }
        if config.popoverDisplaysWeekOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskWeekSalary", title: "本周摸鱼薪资", value: offTaskMoneyValue(weekSummary.amount)))
        }
        if config.popoverDisplaysSalaryCycleOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskCycleSalary", title: "\(cycleTitle)摸鱼薪资", value: offTaskMoneyValue(cycleSummary.amount)))
        }
        if config.popoverDisplaysHistoricalOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "offTaskTotalSalary", title: "历史摸鱼薪资", value: offTaskMoneyValue(totalSummary.amount)))
        }
        if config.popoverDisplaysTodayOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskTodayDuration", title: "本日摸鱼时长", value: formatOffTaskDuration(today.paidSeconds), isSensitive: false))
        }
        if config.popoverDisplaysWeekOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskWeekDuration", title: "本周摸鱼时长", value: formatOffTaskDuration(weekSummary.paidSeconds), isSensitive: false))
        }
        if config.popoverDisplaysSalaryCycleOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskCycleDuration", title: "\(cycleTitle)摸鱼时长", value: formatOffTaskDuration(cycleSummary.paidSeconds), isSensitive: false))
        }
        if config.popoverDisplaysHistoricalOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "offTaskTotalDuration", title: "历史摸鱼时长", value: formatOffTaskDuration(totalSummary.paidSeconds), isSensitive: false))
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

    private func offTaskMoneyValue(_ value: Double) -> String {
        let amount = String(format: "%.\(configManager.config.displayDecimalPlaces)f", value)
        return "¥\(amount)"
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

/// 摸鱼状态弹窗面板由真实弹窗和设置预览共用，避免按钮、脱敏和指标布局出现两套实现。
struct OffTaskPopoverPanelView: View {
    let showsStatus: Bool
    let isActive: Bool
    let canStart: Bool
    let isPrivate: Bool
    let subtitle: String
    let metrics: [SalaryMetricItem]
    let finishedSummary: String?
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

            if let finishedSummary {
                Text(finishedSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
