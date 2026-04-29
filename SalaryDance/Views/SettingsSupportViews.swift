import SwiftUI
import AppKit

/// 设置页输入清洗工具，所有数字输入都先经过这里再写入配置。
enum InputValidation {
    /// 只保留一个小数点和指定长度的数字，用户输入超限时在提交阶段再做 clamp。
    static func decimalText(_ value: String, maxIntegerDigits: Int = 12, maxFractionDigits: Int = 2) -> String {
        var integerPart = ""
        var fractionPart = ""
        var hasSeparator = false

        for character in value {
            if character.isNumber {
                if hasSeparator {
                    guard fractionPart.count < maxFractionDigits else { continue }
                    fractionPart.append(character)
                } else {
                    guard integerPart.count < maxIntegerDigits else { continue }
                    integerPart.append(character)
                }
            } else if (character == "." || character == ",") && maxFractionDigits > 0 && !hasSeparator {
                hasSeparator = true
            }
        }

        if hasSeparator {
            return integerPart + "." + fractionPart
        }
        return integerPart
    }

    /// 只保留数字，适用于小时、分钟、周期起始日等整数输入。
    static func integerText(_ value: String, maxDigits: Int? = nil) -> String {
        let digits = value.filter(\.isNumber)
        guard let maxDigits else { return String(digits) }
        return String(digits.prefix(maxDigits))
    }

    static func decimalValue(from text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard normalized != ".", !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    static func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func rounded(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// 展示给用户的数字去掉无意义尾零，保持输入框紧凑。
    static func formattedDecimal(_ value: Double, maxFractionDigits: Int) -> String {
        if maxFractionDigits <= 0 {
            return String(format: "%.0f", value)
        }

        var text = String(format: "%.\(maxFractionDigits)f", value)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }
}

/// 设置窗口左侧栏的可拖拽分割线。
struct SettingsSplitDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    var onEditingEnded: ((Double) -> Void)?
    @State private var dragStartWidth: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(isActive ? 0.72 : 0.45))
                .frame(width: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(isActive ? 0.46 : 0))
                .frame(width: 3, height: 42)
        }
            .frame(width: 9)
            .contentShape(Rectangle())
            .background(Color.accentColor.opacity(isHovering ? 0.045 : 0))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? width
                        if dragStartWidth == nil {
                            dragStartWidth = start
                        }
                        setWidthWithoutAnimation(start + value.translation.width)
                    }
                    .onEnded { value in
                        let start = dragStartWidth ?? width
                        let finalWidth = clampedWidth(start + value.translation.width)
                        setWidthWithoutAnimation(finalWidth)
                        onEditingEnded?(finalWidth)
                        dragStartWidth = nil
                    }
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .animation(.easeInOut(duration: 0.14), value: isHovering)
            .help("拖动调整左侧栏目宽度")
    }

    private var isActive: Bool {
        isHovering || dragStartWidth != nil
    }

    private func setWidthWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            width = clampedWidth(value)
        }
    }

    private func clampedWidth(_ value: Double) -> Double {
        InputValidation.clamped(value, in: range)
    }
}

/// 设置页里的时间轴预览，和弹窗时间轴使用同一套配置语义。
struct TimelinePreviewBar: View {
    let config: SalaryConfig
    let progress: Double

    private struct Segment: Identifiable {
        let id: String
        let title: String
        let start: Double
        let end: Double
        let color: Color
    }

    var body: some View {
        let tint = Color(nsColor: config.workProgressNSColor)
        let labels = labelSegments

        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fillWidth = max(7, width * min(1, max(0, progress)))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .separatorColor).opacity(0.22),
                                    Color(nsColor: .windowBackgroundColor).opacity(0.46)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.52), tint.opacity(0.92), tint.opacity(0.60)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)

                    ForEach(breakSegments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .overlay(Color.white.opacity(0.08))
                            .frame(width: width * (segment.end - segment.start), height: 11)
                            .offset(x: width * segment.start)
                    }

                    if config.workProgressDisplaysGrid {
                        ForEach(gridTicks, id: \.self) { tick in
                            Rectangle()
                                .fill(Color(nsColor: .labelColor).opacity(0.28))
                                .frame(width: 1, height: 11)
                                .offset(x: max(0, width * tick - 0.5))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 11)

            if config.workProgressDisplaysSegmentLabels {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        ForEach(labels) { segment in
                            let startX = width * segment.start
                            let segmentWidth = width * (segment.end - segment.start)
                            Text(segment.title)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(segment.color.opacity(0.86))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(width: max(28, segmentWidth), alignment: .center)
                                .offset(x: startX)
                        }
                    }
                }
                .frame(height: 10)
            }
        }
    }

    /// 仅当用户开启休息时间颜色时，才在主时间轴上叠加休息段。
    private var breakSegments: [Segment] {
        var segments: [Segment] = []
        if config.usesLunchBreak,
           config.displaysLunchBreakColor {
            segments.append(contentsOf: makeSegments(id: "lunch", title: "午休", range: config.lunchBreak, color: Color(nsColor: config.lunchBreakNSColor)))
        }
        if config.dinnerBreakEnabled,
           config.displaysDinnerBreakColor {
            segments.append(contentsOf: makeSegments(id: "dinner", title: "晚饭", range: config.dinnerBreak, color: Color(nsColor: config.dinnerBreakNSColor)))
        }
        return segments
    }

    /// 生成“上午/午休/下午/晚饭/晚上”等时间段标签。
    private var labelSegments: [Segment] {
        let workStart = config.workTimelineStartMinutes
        let workEnd = config.workTimelineEndMinutes
        let duration = config.workDurationMinutes
        guard duration > 0 else { return [] }

        var breaks: [(id: String, title: String, start: Int, end: Int, color: Color)] = []
        if config.usesLunchBreak {
            breaks.append(contentsOf: config.clampedIntervalsInWorkTime(for: config.lunchBreak).enumerated().map { index, interval in
                ("lunch-\(index)", "午休", interval.startMinutes, interval.endMinutes, Color(nsColor: config.lunchBreakNSColor))
            })
        }
        if config.dinnerBreakEnabled {
            breaks.append(contentsOf: config.clampedIntervalsInWorkTime(for: config.dinnerBreak).enumerated().map { index, interval in
                ("dinner-\(index)", "晚饭", interval.startMinutes, interval.endMinutes, Color(nsColor: config.dinnerBreakNSColor))
            })
        }
        breaks = breaks.sorted { $0.start < $1.start }

        var segments: [Segment] = []
        var cursor = workStart

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
            segments.append(makeSegment(
                id: "work-\(start)-\(end)",
                title: title,
                start: start,
                end: end,
                color: Color(nsColor: config.workProgressNSColor),
                workStart: workStart,
                duration: duration
            ))
        }

        for item in breaks {
            appendWorkSegment(start: cursor, end: item.start)
            segments.append(makeSegment(
                id: item.id,
                title: item.title,
                start: item.start,
                end: item.end,
                color: item.color,
                workStart: workStart,
                duration: duration
            ))
            cursor = max(cursor, item.end)
        }

        appendWorkSegment(start: cursor, end: workEnd)
        return segments.filter { $0.end - $0.start > 0.055 }
    }

    /// 网格点使用展开后的工作时间轴，跨夜时仍按连续分钟计算。
    private var gridTicks: [Double] {
        let workStart = config.workTimelineStartMinutes
        let workEnd = config.workTimelineEndMinutes
        let duration = config.workDurationMinutes
        guard config.workProgressDisplaysGrid, duration > 0 else { return [] }

        var result: [Double] = []
        var minute = workStart + config.workProgressGridIntervalMinutes
        while minute < workEnd {
            result.append(Double(minute - workStart) / Double(duration))
            minute += config.workProgressGridIntervalMinutes
        }
        return result
    }

    private func makeSegments(id: String, title: String, range: TimeRange, color: Color) -> [Segment] {
        let workStart = config.workTimelineStartMinutes
        let duration = config.workDurationMinutes
        guard duration > 0 else { return [] }
        return config.clampedIntervalsInWorkTime(for: range).enumerated().map { index, interval in
            makeSegment(
                id: "\(id)-\(index)",
                title: title,
                start: interval.startMinutes,
                end: interval.endMinutes,
                color: color,
                workStart: workStart,
                duration: duration
            )
        }
    }

    private func makeSegment(id: String, title: String, start: Int, end: Int, color: Color, workStart: Int, duration: Int) -> Segment {
        Segment(
            id: id,
            title: title,
            start: Double(start - workStart) / Double(duration),
            end: Double(end - workStart) / Double(duration),
            color: color
        )
    }

    private func normalizedClockMinute(_ minute: Int) -> Int {
        let minutesPerDay = 24 * 60
        return ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

/// 小时/分钟输入组件，兼顾点击步进和直接输入。
struct TimeInputView: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @State private var hourText: String
    @State private var minuteText: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case hour
        case minute
    }

    init(hour: Binding<Int>, minute: Binding<Int>) {
        _hour = hour
        _minute = minute
        _hourText = State(initialValue: "\(Self.clamped(hour.wrappedValue, in: 0...23))")
        _minuteText = State(initialValue: Self.twoDigit(Self.clamped(minute.wrappedValue, in: 0...59)))
    }

    var body: some View {
        HStack(spacing: 10) {
            timeUnit(
                value: $hour,
                text: $hourText,
                range: 0...23,
                step: 1,
                field: .hour,
                unit: "时",
                formatter: { "\($0)" }
            )

            timeUnit(
                value: $minute,
                text: $minuteText,
                range: 0...59,
                step: 5,
                field: .minute,
                unit: "分",
                formatter: Self.twoDigit
            )
        }
    }

    private func timeUnit(
        value: Binding<Int>,
        text: Binding<String>,
        range: ClosedRange<Int>,
        step: Int,
        field: Field,
        unit: String,
        formatter: @escaping (Int) -> String
    ) -> some View {
        HStack(spacing: 4) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 38)
                .focused($focusedField, equals: field)
                .onSubmit {
                    commit(text: text, value: value, range: range, formatter: formatter)
                }
                .onChange(of: text.wrappedValue) { _, newValue in
                    guard focusedField == field else { return }
                    let sanitized = InputValidation.integerText(newValue, maxDigits: 2)
                    guard sanitized == newValue else {
                        text.wrappedValue = sanitized
                        return
                    }
                    guard let parsed = Int(sanitized), !range.contains(parsed) else { return }
                    let normalized = Self.clamped(parsed, in: range)
                    value.wrappedValue = normalized
                    text.wrappedValue = formatter(normalized)
                }
                .onChange(of: focusedField) { _, newValue in
                    guard newValue != field else { return }
                    commit(text: text, value: value, range: range, formatter: formatter)
                }
                .onChange(of: value.wrappedValue) { _, newValue in
                    guard focusedField != field else { return }
                    text.wrappedValue = formatter(Self.clamped(newValue, in: range))
                }

            Text(unit)
                .foregroundColor(.secondary)

            Stepper("", value: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    let normalized = Self.clamped(newValue, in: range)
                    value.wrappedValue = normalized
                    text.wrappedValue = formatter(normalized)
                }
            ), in: range, step: step)
            .labelsHidden()
            .frame(width: 44)
        }
    }

    /// 失焦或回车时统一提交，并把越界值修正回合法范围。
    private func commit(
        text: Binding<String>,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        formatter: (Int) -> String
    ) {
        let digits = text.wrappedValue.filter(\.isNumber)
        guard !digits.isEmpty, let parsed = Int(digits) else {
            text.wrappedValue = formatter(Self.clamped(value.wrappedValue, in: range))
            return
        }

        let normalized = Self.clamped(parsed, in: range)
        value.wrappedValue = normalized
        text.wrappedValue = formatter(normalized)
    }

    private static func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
