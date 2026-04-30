import SwiftUI

/// 弹窗里的核心展示组件，负责把工作状态、进度条、当前收入、剩余收入和薪资指标组合到一个稳定宽度内。
struct SalaryDisplayView: View {
    @ObservedObject var viewModel: SalaryViewModel
    var isPrivate: Bool = false
    var showsStatus: Bool = true
    var showsEarnings: Bool = true
    var showsRemainingEarnings: Bool = true
    var showsSecondSalary: Bool = true
    var showsMinuteSalary: Bool = true
    var showsHourlySalary: Bool = true
    var showsDailySalary: Bool = true
    var showsMonthlySalary: Bool = false
    var showsYearlySalary: Bool = false
    var showsWorkProgress: Bool = true
    var earningsActionSystemImage: String?
    var earningsAction: (() -> Void)?
    @State private var displayEarnings: Double = 0
    @State private var animateChange = false

    /// 时间轴上被休息时间覆盖的片段，使用 0...1 的相对位置避免不同工作时长下重复计算 UI 坐标。
    private struct BreakSegment: Identifiable {
        let id: String
        let name: String
        let start: Double
        let end: Double
        let tint: Color
        let isActive: Bool
    }

    /// 时间轴网格刻度，同样使用相对位置，让跨夜班次也能连续绘制。
    private struct GridTick: Identifiable {
        let id: Int
        let position: Double
    }

    /// 时间轴标签片段，既包含“上午/下午/晚上”，也包含午休、晚饭等休息段。
    private struct TimelineLabelSegment: Identifiable {
        let id: String
        let title: String
        let start: Double
        let end: Double
        let tint: Color
    }

    /// 按用户配置决定各模块是否渲染，避免隐藏内容仍然占用弹窗高度。
    var body: some View {
        let salaryTint = Color(nsColor: viewModel.config.popoverSalaryNSColor)

        VStack(spacing: 10) {
            if showsStatus || showsWorkProgress {
                statusProgressPanel
            }

            if showsEarnings || showsRemainingEarnings {
                earningsBlock(salaryTint: salaryTint)
            }

            if showsSalaryRates {
                salaryInfoRow
            }
        }
        .onAppear {
            displayEarnings = viewModel.todayEarnings
        }
        .onChange(of: viewModel.todayEarnings) { _, newValue in
            displayEarnings = newValue
            animateChange = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                animateChange = false
            }
        }
    }

    /// 当前收入和“今日剩余”同属金额主展示区，组合在一起能减少显隐切换时的跳动。
    private func earningsBlock(salaryTint: Color) -> some View {
        VStack(spacing: 0) {
            if showsEarnings {
                earningsRow(salaryTint: salaryTint)
            }

            if showsRemainingEarnings {
                remainingEarningsRow(salaryTint: salaryTint)
            }
        }
    }

    /// “还剩多少钱没赚”的金额跟随薪资色，并使用数字滚动保持和主金额一致的反馈。
    private func remainingEarningsRow(salaryTint: Color) -> some View {
        Group {
            if viewModel.status == .dayOff {
                Text("今天不计薪")
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 0) {
                    Text("今天还剩 ")
                        .foregroundColor(.secondary)

                    Text(remainingEarningsAmountText)
                        .foregroundColor(salaryTint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: displayEarnings)

                    Text(" 没赚")
                        .foregroundColor(.secondary)
                }
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.top, showsEarnings ? 0 : 4)
    }

    /// 主金额保持居中，右侧显隐按钮独立贴边，避免明文和脱敏宽度不同导致整体位移。
    private func earningsRow(salaryTint: Color) -> some View {
        ZStack(alignment: .trailing) {
            Text(isPrivate ? "¥***" : formatMoney(displayEarnings))
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(salaryTint)
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 56)
                .padding(.horizontal, earningsAction == nil ? 0 : 34)
                .padding(.vertical, 2)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: displayEarnings)
                .scaleEffect(animateChange ? 1.02 : 1.0)
                .animation(.spring(response: 0.3), value: animateChange)

            if let earningsActionSystemImage,
               let earningsAction {
                Button(action: earningsAction) {
                    Image(systemName: earningsActionSystemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                )
                .focusable(false)
            }
        }
        .padding(.horizontal, 16)
    }

    /// 剩余收入按日薪扣减当前已赚金额，非计薪日由上层直接展示“不计薪”。
    private var remainingEarningsAmountText: String {
        let remaining = max(0, viewModel.config.dailySalary - displayEarnings)
        return isPrivate ? "¥***" : formatMoney(remaining)
    }

    /// 工作状态和时间轴的组合面板；百分比表达的是时间进度，不受休息是否计薪影响。
    private var statusProgressPanel: some View {
        let presentation = statusPresentation
        let progress = min(1, max(0, viewModel.progress))
        let progressText = formatProgressPercent(progress)
        let timelineTint = Color(nsColor: viewModel.config.workProgressNSColor)
        let breakSegments = progressBreakSegments
        let showsBreakMarkers = !breakSegments.isEmpty
        let gridTicks = progressGridTicks
        let showsGrid = viewModel.config.workProgressDisplaysGrid && !gridTicks.isEmpty
        let labelSegments = progressLabelSegments
        let showsLabels = viewModel.config.workProgressDisplaysSegmentLabels && !labelSegments.isEmpty

        return VStack(spacing: 8) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(presentation.tint.opacity(0.16))
                    Image(systemName: presentation.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(presentation.tint)
                }
                .frame(width: 28, height: 28)

                if showsStatus {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(presentation.subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if showsWorkProgress {
                    Text(progressText)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(timelineTint)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: progressText)
                }
            }

            if showsWorkProgress {
                VStack(spacing: 6) {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let fillWidth = progress > 0 ? max(7, width * progress) : 0
                        let dotX = min(max(6, width * progress), width - 6)

                        ZStack(alignment: .leading) {
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(nsColor: .separatorColor).opacity(0.22),
                                                Color(nsColor: .windowBackgroundColor).opacity(0.42)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                timelineTint.opacity(0.52),
                                                timelineTint.opacity(0.92),
                                                timelineTint.opacity(0.64)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: fillWidth)

                                if showsBreakMarkers {
                                    ForEach(breakSegments) { segment in
                                        let segmentX = width * segment.start
                                        let segmentWidth = width * (segment.end - segment.start)

                                        breakSegmentOverlay(segment)
                                            .frame(width: segmentWidth, height: 12)
                                            .offset(x: segmentX)
                                    }
                                }

                                if showsGrid {
                                    ForEach(gridTicks) { tick in
                                        Rectangle()
                                            .fill(Color(nsColor: .labelColor).opacity(0.30))
                                            .frame(width: 1.2, height: 12)
                                            .overlay(
                                                Rectangle()
                                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.42))
                                                    .frame(width: 0.5)
                                            )
                                            .offset(x: max(0, width * tick.position - 0.6))
                                    }
                                }
                            }
                            .frame(height: 12)
                            .clipShape(Capsule())
                            .shadow(color: timelineTint.opacity(0.12), radius: 3, x: 0, y: 1)

                            Circle()
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(timelineTint, lineWidth: 2))
                                .shadow(color: timelineTint.opacity(0.24), radius: 4, x: 0, y: 1)
                                .offset(x: dotX - 6)
                        }
                    }
                    .frame(height: 12)

                    if showsLabels {
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            ZStack(alignment: .leading) {
                                ForEach(labelSegments) { segment in
                                    let startX = width * segment.start
                                    let segmentWidth = width * (segment.end - segment.start)

                                    Text(segment.title)
                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                        .foregroundColor(segment.tint.opacity(0.88))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                        .frame(width: max(28, segmentWidth), alignment: .center)
                                        .offset(x: startX)
                                }
                            }
                        }
                        .frame(height: 11)
                    }

                    HStack {
                        Text(viewModel.effectiveWorkTime.startString)
                        Spacer()
                        Text(viewModel.effectiveWorkTime.endString)
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.75))
                    .monospacedDigit()
                }
            }
        }
        .padding(.top, 7)
        .padding(.bottom, 8)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            presentation.tint.opacity(0.10),
                            Color.white.opacity(0.025),
                            timelineTint.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    /// 将计算状态转成 UI 文案、图标和色彩，集中处理可以避免多个视图出现状态描述不一致。
    private var statusPresentation: (title: String, subtitle: String, icon: String, tint: Color) {
        switch viewModel.status {
        case .notStarted:
            return ("未上班", viewModel.statusText.isEmpty ? "等待开工" : viewModel.statusText, "moon.zzz.fill", .blue)
        case .working:
            return ("工作中", viewModel.statusText, "flame.fill", .orange)
        case .onBreak(let name):
            let subtitle = viewModel.config.countsBreakTimeAsPaidWork ? "休息时间计薪" : "休息时间不计薪"
            return ("\(name)中", subtitle, "cup.and.saucer.fill", .teal)
        case .finished:
            return ("今日已收工", "已完成今日工作", "checkmark.circle.fill", .green)
        case .dayOff:
            return ("今日休息", "不计入工作进度", "sun.max.fill", .purple)
        }
    }

    /// 休息色块只在对应开关开启时绘制，避免和主时间轴颜色混合出不可控效果。
    private var progressBreakSegments: [BreakSegment] {
        let config = viewModel.config
        var segments: [BreakSegment] = []

        if config.usesLunchBreak,
           config.displaysLunchBreakColor {
            segments.append(contentsOf: makeBreakSegments(
                id: "lunch",
                name: "午休",
                range: config.lunchBreak,
                tint: Color(nsColor: config.lunchBreakNSColor)
            ))
        }

        if config.dinnerBreakEnabled,
           config.displaysDinnerBreakColor {
            segments.append(contentsOf: makeBreakSegments(
                id: "dinner",
                name: "晚饭",
                range: config.dinnerBreak,
                tint: Color(nsColor: config.dinnerBreakNSColor)
            ))
        }

        return segments
    }

    /// 网格刻度基于展开后的工作时间轴计算，因此晚班和跨夜班不会在 0 点处断裂。
    private var progressGridTicks: [GridTick] {
        let config = viewModel.config
        guard config.workProgressDisplaysGrid else { return [] }

        let workStart = viewModel.effectiveWorkTimelineStartMinutes
        let workEnd = viewModel.effectiveWorkTimelineEndMinutes
        let workDuration = viewModel.effectiveWorkDurationMinutes
        let interval = config.workProgressGridIntervalMinutes
        guard workDuration > 0, interval > 0 else { return [] }

        var ticks: [GridTick] = []
        var minute = workStart + interval
        while minute < workEnd {
            ticks.append(
                GridTick(
                    id: minute,
                    position: Double(minute - workStart) / Double(workDuration)
                )
            )
            minute += interval
        }
        return ticks
    }

    /// 标签开关由面板统一控制，这里只负责提供可绘制片段。
    private var progressLabelSegments: [TimelineLabelSegment] {
        timelineLabelSegments()
    }

    /// 把一个休息时间段裁剪到工作窗口内，返回可直接映射到时间轴宽度的片段。
    private func makeBreakSegments(id: String, name: String, range: TimeRange, tint: Color) -> [BreakSegment] {
        let workStart = viewModel.effectiveWorkTimelineStartMinutes
        let workDuration = viewModel.effectiveWorkDurationMinutes
        guard workDuration > 0 else { return [] }

        let isActive: Bool
        if case .onBreak(let activeName) = viewModel.status {
            isActive = activeName == name
        } else {
            isActive = false
        }

        return viewModel.clampedIntervalsInEffectiveWorkTime(for: range).enumerated().map { index, interval in
            BreakSegment(
                id: "\(id)-\(index)",
                name: name,
                start: Double(interval.startMinutes - workStart) / Double(workDuration),
                end: Double(interval.endMinutes - workStart) / Double(workDuration),
                tint: tint,
                isActive: isActive
            )
        }
    }

    /// 生成时间轴标签：休息段插入工作段中，过短片段会被过滤，避免小弹窗里文字重叠。
    private func timelineLabelSegments() -> [TimelineLabelSegment] {
        let config = viewModel.config
        let workStart = viewModel.effectiveWorkTimelineStartMinutes
        let workEnd = viewModel.effectiveWorkTimelineEndMinutes
        let workDuration = viewModel.effectiveWorkDurationMinutes
        guard workDuration > 0 else { return [] }

        var breaks: [(id: String, title: String, start: Int, end: Int, tint: Color)] = []

        // 休息时间可能跨夜或被工作时间裁掉，先统一转成工作窗口内的片段。
        func appendBreak(id: String, title: String, range: TimeRange, tint: Color) {
            for (index, interval) in viewModel.clampedIntervalsInEffectiveWorkTime(for: range).enumerated() {
                breaks.append(("\(id)-\(index)", title, interval.startMinutes, interval.endMinutes, tint))
            }
        }

        if config.usesLunchBreak {
            appendBreak(
                id: "lunch",
                title: "午休",
                range: config.lunchBreak,
                tint: Color(nsColor: config.lunchBreakNSColor)
            )
        }
        if config.dinnerBreakEnabled {
            appendBreak(
                id: "dinner",
                title: "晚饭",
                range: config.dinnerBreak,
                tint: Color(nsColor: config.dinnerBreakNSColor)
            )
        }

        breaks.sort { $0.start < $1.start }

        var segments: [TimelineLabelSegment] = []
        var cursor = workStart

        // 工作片段根据中点所属自然时段命名，跨夜时先归一化到 0...24 小时。
        func appendWorkSegment(start: Int, end: Int) {
            guard end - start >= 20 else { return }
            let midpoint = (start + end) / 2
            let clockMinute = normalizedClockMinute(midpoint)
            let title: String
            if clockMinute < 6 * 60 {
                title = "凌晨"
            } else if clockMinute < 12 * 60 {
                title = "上午"
            } else if clockMinute < 18 * 60 {
                title = "下午"
            } else {
                title = "晚上"
            }
            segments.append(makeLabelSegment(
                id: "work-\(start)-\(end)",
                title: title,
                start: start,
                end: end,
                tint: Color(nsColor: config.workProgressNSColor),
                workStart: workStart,
                workDuration: workDuration
            ))
        }

        for item in breaks {
            appendWorkSegment(start: cursor, end: item.start)
            segments.append(makeLabelSegment(
                id: item.id,
                title: item.title,
                start: item.start,
                end: item.end,
                tint: item.tint,
                workStart: workStart,
                workDuration: workDuration
            ))
            cursor = max(cursor, item.end)
        }

        appendWorkSegment(start: cursor, end: workEnd)
        return segments.filter { $0.end - $0.start > 0.055 }
    }

    /// 将展开时间轴上的分钟数归一回一天内的分钟数，用于判断“上午/下午/晚上”。
    private func normalizedClockMinute(_ minute: Int) -> Int {
        let minutesPerDay = 24 * 60
        return ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// 构造 0...1 相对位置的标签片段，视图层只需按父容器宽度换算像素。
    private func makeLabelSegment(
        id: String,
        title: String,
        start: Int,
        end: Int,
        tint: Color,
        workStart: Int,
        workDuration: Int
    ) -> TimelineLabelSegment {
        TimelineLabelSegment(
            id: id,
            title: title,
            start: Double(start - workStart) / Double(workDuration),
            end: Double(end - workStart) / Double(workDuration),
            tint: tint
        )
    }

    /// 休息段使用实色覆盖主时间轴，当前休息段额外提亮但不改变整体高度。
    private func breakSegmentOverlay(_ segment: BreakSegment) -> some View {
        Rectangle()
            .fill(segment.tint)
            .overlay(Color.white.opacity(segment.isActive ? 0.16 : 0.06))
            .shadow(color: segment.tint.opacity(segment.isActive ? 0.24 : 0.10), radius: 2, x: 0, y: 1)
            .accessibilityLabel("\(segment.name)时间段")
    }

    /// 任意薪资指标开启时才渲染指标网格，减少无内容时的空白。
    private var showsSalaryRates: Bool {
        showsSecondSalary
            || showsMinuteSalary
            || showsHourlySalary
            || showsDailySalary
            || showsMonthlySalary
            || showsYearlySalary
    }

    /// 按固定顺序收集薪资指标，真实弹窗和设置预览保持同一展示顺序。
    private var salaryMetrics: [SalaryMetricItem] {
        var metrics: [SalaryMetricItem] = []
        if showsSecondSalary {
            metrics.append(SalaryMetricItem(id: "second", title: "秒薪", value: viewModel.formattedSecondSalary))
        }
        if showsMinuteSalary {
            metrics.append(SalaryMetricItem(id: "minute", title: "分薪", value: viewModel.formattedMinuteSalary))
        }
        if showsHourlySalary {
            metrics.append(SalaryMetricItem(id: "hour", title: "时薪", value: viewModel.formattedHourlySalary))
        }
        if showsDailySalary {
            metrics.append(SalaryMetricItem(id: "day", title: "日薪", value: viewModel.formattedDailySalary))
        }
        if showsMonthlySalary {
            metrics.append(SalaryMetricItem(id: "month", title: "月薪", value: viewModel.formattedMonthlySalary))
        }
        if showsYearlySalary {
            metrics.append(SalaryMetricItem(id: "year", title: "年薪", value: viewModel.formattedYearlySalary))
        }
        return metrics
    }

    /// 使用均衡网格处理 1/2/3 个指标的最后一行排布。
    private var salaryInfoRow: some View {
        let salaryTint = Color(nsColor: viewModel.config.popoverSalaryNSColor)

        return BalancedSalaryMetricGrid(
            metrics: salaryMetrics,
            isPrivate: isPrivate,
            tint: salaryTint
        )
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    /// 所有弹窗金额共享同一小数位配置，保证主金额、剩余金额和指标格式一致。
    private func formatMoney(_ value: Double) -> String {
        let digits = SalaryConfigManager.shared.config.displayDecimalPlaces
        return String(format: "¥%.\(digits)f", value)
    }

    /// 工作进度百分比使用独立精度配置，数值变化时配合 numericText 做滚动。
    private func formatProgressPercent(_ progress: Double) -> String {
        let digits = viewModel.config.workProgressDisplayDecimalPlaces
        return String(format: "%.\(digits)f%%", progress * 100)
    }
}
