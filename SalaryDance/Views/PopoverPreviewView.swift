import SwiftUI

/// 设置页右侧弹窗预览，尽量复用真实弹窗的布局组件和展示规则。
struct PopoverPreviewView: View {
    let config: SalaryConfig
    @StateObject private var previewViewModel: SalaryViewModel
    @State private var isPrivate: Bool

    private static let previewProgress = 0.42

    init(config: SalaryConfig) {
        self.config = config
        let viewModel = SalaryViewModel(startsTimer: false)
        Self.applyPreviewSnapshot(to: viewModel, config: config)
        _previewViewModel = StateObject(wrappedValue: viewModel)
        _isPrivate = State(initialValue: config.opensPrivatePopoverFromStatusItemClick)
    }

    var body: some View {
        let showsSalaryBlock = config.popoverDisplaysWorkStatus
            || config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate
            || config.popoverDisplaysWorkProgress
        let showsSalarySensitiveContent = config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate
        let showsOffTaskSensitiveContent = config.popoverDisplaysAnyOffTaskSalaryMetric

        VStack(alignment: .leading, spacing: 8) {
            Text("弹窗")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                if showsSalaryBlock {
                    SalaryDisplayView(
                        viewModel: previewViewModel,
                        isPrivate: isPrivate,
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
                        earningsActionSystemImage: showsSalarySensitiveContent ? (isPrivate ? "eye" : "eye.slash") : nil,
                        earningsAction: showsSalarySensitiveContent ? {
                            isPrivate.toggle()
                        } : nil
                    )
                }

                if config.popoverDisplaysAnyOffTaskInformation {
                    offTaskPreviewPanel(
                        showsPrivacyAction: showsOffTaskSensitiveContent && !showsSalarySensitiveContent
                    )
                }

                if config.popoverDisplaysQuote {
                    Text("今天的工资正在路上")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(width: 260)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .frame(width: 280, alignment: .topLeading)
        .onAppear {
            Self.applyPreviewSnapshot(to: previewViewModel, config: config)
            isPrivate = config.opensPrivatePopoverFromStatusItemClick
        }
        .onChange(of: config) { _, newValue in
            Self.applyPreviewSnapshot(to: previewViewModel, config: newValue)
            isPrivate = newValue.opensPrivatePopoverFromStatusItemClick
        }
    }

    private static func applyPreviewSnapshot(to viewModel: SalaryViewModel, config: SalaryConfig) {
        let now = Date()
        let dailySalary = config.effectiveDailySalary(on: now)
        let workTime = config.effectiveWorkTime(on: now)
        viewModel.status = .working
        viewModel.statusText = "距下班 4时12分"
        viewModel.progress = Self.previewProgress
        viewModel.effectiveDailySalary = dailySalary
        viewModel.effectiveWorkTime = workTime
        viewModel.effectivePaidWorkMinutes = config.paidWorkMinutes(workTime: workTime)
        viewModel.earningsPerSecond = config.salaryPerSecond(on: now)
        viewModel.todayEarnings = config.hasCompensation ? dailySalary * Self.previewProgress : 0
    }

    private func offTaskPreviewPanel(showsPrivacyAction: Bool) -> some View {
        OffTaskPopoverPanelView(
            showsStatus: config.popoverDisplaysOffTaskStatus,
            isActive: false,
            canStart: true,
            isPrivate: isPrivate,
            subtitle: "未开启",
            metrics: previewOffTaskMetrics(dailySalary: previewViewModel.effectiveDailySalary),
            finishedSummary: nil,
            showsPrivacyAction: showsPrivacyAction,
            toggleHelp: "预览中不会改写真实摸鱼记录。",
            privacyAction: {
                isPrivate.toggle()
            },
            toggleAction: {}
        )
    }

    private func previewOffTaskMetrics(dailySalary: Double) -> [SalaryMetricItem] {
        let baseAmount = config.hasCompensation ? dailySalary * 0.06 : 0
        let cycleTitle = config.resolvedSalaryCycleMode == .naturalMonth ? "本月" : "本周期"
        var metrics: [SalaryMetricItem] = []

        if config.popoverDisplaysTodayOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "previewOffTaskTodaySalary", title: "本日摸鱼薪资", value: formatMoney(baseAmount)))
        }
        if config.popoverDisplaysWeekOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "previewOffTaskWeekSalary", title: "本周摸鱼薪资", value: formatMoney(baseAmount * 3.2)))
        }
        if config.popoverDisplaysSalaryCycleOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "previewOffTaskCycleSalary", title: "\(cycleTitle)摸鱼薪资", value: formatMoney(baseAmount * 11.4)))
        }
        if config.popoverDisplaysHistoricalOffTaskSalary {
            metrics.append(SalaryMetricItem(id: "previewOffTaskTotalSalary", title: "历史摸鱼薪资", value: formatMoney(baseAmount * 28.6)))
        }
        if config.popoverDisplaysTodayOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "previewOffTaskTodayDuration", title: "本日摸鱼时长", value: "18分", isSensitive: false))
        }
        if config.popoverDisplaysWeekOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "previewOffTaskWeekDuration", title: "本周摸鱼时长", value: "1时42分", isSensitive: false))
        }
        if config.popoverDisplaysSalaryCycleOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "previewOffTaskCycleDuration", title: "\(cycleTitle)摸鱼时长", value: "6时18分", isSensitive: false))
        }
        if config.popoverDisplaysHistoricalOffTaskDuration {
            metrics.append(SalaryMetricItem(id: "previewOffTaskTotalDuration", title: "历史摸鱼时长", value: "15时40分", isSensitive: false))
        }

        return metrics
    }

    private func formatMoney(_ value: Double, showCurrencySymbol: Bool = true) -> String {
        let amount = String(format: "%.\(config.displayDecimalPlaces)f", value)
        return showCurrencySymbol ? "¥\(amount)" : amount
    }

}
