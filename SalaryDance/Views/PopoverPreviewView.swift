import SwiftUI

/// 设置页右侧弹窗预览，尽量复用真实弹窗的布局组件和展示规则。
struct PopoverPreviewView: View {
    let config: SalaryConfig

    private let previewProgress = 0.42

    var body: some View {
        let salaryTint = Color(nsColor: config.popoverSalaryNSColor)
        let isPrivate = config.opensPrivatePopoverFromStatusItemClick
        let previewEarnings = config.hasCompensation ? config.dailySalary * previewProgress : 0

        VStack(alignment: .leading, spacing: 8) {
            Text("弹窗")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                if config.popoverDisplaysWorkStatus || config.popoverDisplaysWorkProgress {
                    previewStatusProgress
                }

                if config.popoverDisplaysCurrentEarnings || config.popoverDisplaysRemainingEarnings {
                    VStack(spacing: 1) {
                        if config.popoverDisplaysCurrentEarnings {
                            Text(isPrivate ? "¥***" : formatMoney(previewEarnings))
                                .font(.system(size: 30, weight: .bold, design: .monospaced))
                                .foregroundColor(salaryTint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.numericText())
                        }

                        if config.popoverDisplaysRemainingEarnings {
                            remainingEarningsPreview(
                                amount: max(0, config.dailySalary - previewEarnings),
                                isPrivate: isPrivate,
                                salaryTint: salaryTint
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if config.popoverDisplaysAnySalaryRate {
                    BalancedSalaryMetricGrid(
                        metrics: previewMetrics,
                        isPrivate: isPrivate,
                        tint: salaryTint,
                        spacing: 7,
                        rowHeight: 38,
                        cornerRadius: 6,
                        valueFont: .caption.weight(.semibold),
                        valueMinimumScaleFactor: 0.72
                    )
                }

                if config.popoverDisplaysQuote {
                    Text("今天的工资正在路上")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 260)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .frame(width: 280, alignment: .topLeading)
    }

    /// 用固定 42% 进度模拟一个工作中的场景，方便用户即时对比展示设置。
    private var previewStatusProgress: some View {
        let timelineTint = Color(nsColor: config.workProgressNSColor)
        let progressText = formatProgressPercent(previewProgress)

        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.orange.opacity(0.14)))

                if config.popoverDisplaysWorkStatus {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("工作中")
                            .font(.caption.weight(.semibold))
                        Text("距下班 4时12分")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if config.popoverDisplaysWorkProgress {
                    Text(progressText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(timelineTint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: progressText)
                }
            }

            if config.popoverDisplaysWorkProgress {
                TimelinePreviewBar(config: config, progress: previewProgress)
                    .frame(height: config.workProgressDisplaysSegmentLabels ? 32 : 14)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private func remainingEarningsPreview(amount: Double, isPrivate: Bool, salaryTint: Color) -> some View {
        HStack(spacing: 0) {
            Text("今天还剩 ")
                .foregroundColor(.secondary)
            Text(isPrivate ? "¥***" : formatMoney(amount))
                .foregroundColor(salaryTint)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(" 没赚")
                .foregroundColor(.secondary)
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    /// 根据弹窗展示开关生成预览指标，顺序必须和真实弹窗保持一致。
    private var previewMetrics: [SalaryMetricItem] {
        var metrics: [SalaryMetricItem] = []
        if config.popoverDisplaysSecondSalary {
            metrics.append(SalaryMetricItem(id: "second", title: "秒薪", value: formatMoney(config.salaryPerSecond)))
        }
        if config.popoverDisplaysMinuteSalary {
            metrics.append(SalaryMetricItem(id: "minute", title: "分薪", value: formatMoney(config.salaryPerMinute)))
        }
        if config.popoverDisplaysHourlySalary {
            metrics.append(SalaryMetricItem(id: "hour", title: "时薪", value: formatMoney(config.salaryPerHour)))
        }
        if config.popoverDisplaysDailySalary {
            metrics.append(SalaryMetricItem(id: "day", title: "日薪", value: formatMoney(config.dailySalary)))
        }
        if config.popoverDisplaysMonthlySalary {
            metrics.append(SalaryMetricItem(id: "month", title: "月薪", value: formatMoney(config.monthlySalary)))
        }
        if config.popoverDisplaysYearlySalary {
            metrics.append(SalaryMetricItem(id: "year", title: "年薪", value: formatMoney(config.yearlySalary)))
        }
        return metrics
    }

    private func formatMoney(_ value: Double, showCurrencySymbol: Bool = true) -> String {
        let amount = String(format: "%.\(config.displayDecimalPlaces)f", value)
        return showCurrencySymbol ? "¥\(amount)" : amount
    }

    private func formatProgressPercent(_ progress: Double) -> String {
        String(format: "%.\(config.workProgressDisplayDecimalPlaces)f%%", progress * 100)
    }
}
