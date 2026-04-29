import SwiftUI

/// 状态栏点击或快捷键打开后的弹窗主视图，负责拼装薪资区、语录区和底部操作。
struct PopoverView: View {
    @ObservedObject var viewModel: SalaryViewModel
    @ObservedObject var statusBarController: StatusBarController
    @ObservedObject private var configManager = SalaryConfigManager.shared
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
        // 只有存在敏感金额时才展示眼睛按钮，否则弹窗不出现无意义操作。
        let showsSensitiveContent = config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate

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
                    earningsActionSystemImage: showsSensitiveContent ? (statusBarController.isContentMasked ? "eye" : "eye.slash") : nil,
                    earningsAction: showsSensitiveContent ? {
                        if statusBarController.isContentMasked {
                            statusBarController.revealContent()
                        } else {
                            statusBarController.hideContent()
                        }
                    } : nil
                )
            }

            if showsSalaryBlock && config.popoverDisplaysQuote {
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
        .padding(.vertical, 12)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
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
}
