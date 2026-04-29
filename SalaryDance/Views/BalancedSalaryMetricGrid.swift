import SwiftUI

/// 薪资指标的数据载体，供真实弹窗和设置预览复用。
struct SalaryMetricItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

/// 平衡薪资指标布局：每行最多 3 个，最后一行 1 个居中、2 个均匀铺开。
struct BalancedSalaryMetricGrid: View {
    let metrics: [SalaryMetricItem]
    let isPrivate: Bool
    let tint: Color
    var spacing: CGFloat = 8
    var rowHeight: CGFloat = 50
    var cornerRadius: CGFloat = 7
    var valueFont: Font = .system(size: 11, weight: .semibold, design: .rounded)
    var valueMinimumScaleFactor: CGFloat = 0.55

    private struct MetricRow: Identifiable {
        let items: [SalaryMetricItem]

        var id: String {
            items.map(\.id).joined(separator: "-")
        }
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows) { row in
                GeometryReader { proxy in
                    let width = cardWidth(itemCount: row.items.count, availableWidth: proxy.size.width)

                    HStack(spacing: spacing) {
                        if row.items.count == 1 {
                            Spacer(minLength: 0)
                        }

                        ForEach(row.items) { metric in
                            metricCard(metric)
                                .frame(width: width)
                        }

                        if row.items.count == 1 {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: rowHeight)
            }
        }
    }

    private var rows: [MetricRow] {
        stride(from: 0, to: metrics.count, by: 3).map { start in
            MetricRow(items: Array(metrics[start..<min(start + 3, metrics.count)]))
        }
    }

    private func cardWidth(itemCount: Int, availableWidth: CGFloat) -> CGFloat {
        // 单个指标按三列宽度计算再居中，避免最后一行只有一个时被拉满。
        let columns = itemCount == 1 ? 3 : max(1, min(3, itemCount))
        let totalSpacing = spacing * CGFloat(columns - 1)
        return max(0, (availableWidth - totalSpacing) / CGFloat(columns))
    }

    private func metricCard(_ metric: SalaryMetricItem) -> some View {
        VStack(spacing: 4) {
            Text(metric.title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(isPrivate ? "***" : metric.value)
                .font(valueFont)
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(valueMinimumScaleFactor)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: rowHeight)
        .background(RoundedRectangle(cornerRadius: cornerRadius).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(tint.opacity(0.16), lineWidth: 1))
    }
}
