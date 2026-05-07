import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置页左侧导航分类。分类数量较多时保持这里的 title/subtitle/icon 同步，避免侧边栏和内容区语义漂移。
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case salary
    case time
    case display
    case offTask
    case shortcut
    case calendar
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salary: return "薪资"
        case .time: return "时间"
        case .display: return "展示"
        case .offTask: return "记录"
        case .shortcut: return "快捷键"
        case .calendar: return "日历"
        case .app: return "应用"
        }
    }

    var subtitle: String {
        switch self {
        case .salary: return "输入薪资、补贴和金额精度"
        case .time: return "工作时段、休息和计薪时长"
        case .display: return "状态栏、弹窗和时间轴"
        case .offTask: return "摸鱼、提前下班和加班统计"
        case .shortcut: return "快捷键录制和动作顺序"
        case .calendar: return "计薪规则、节假日和调休日"
        case .app: return "启动、刷新和备份迁移"
        }
    }

    var iconName: String {
        switch self {
        case .salary: return "yensign.circle"
        case .time: return "clock"
        case .display: return "menubar.rectangle"
        case .offTask: return "chart.bar"
        case .shortcut: return "keyboard"
        case .calendar: return "calendar"
        case .app: return "gearshape"
        }
    }
}

private struct DataTransferStatus: Equatable {
    let message: String
    let isError: Bool

    static func success(_ message: String) -> DataTransferStatus {
        DataTransferStatus(message: message, isError: false)
    }

    static func failure(_ message: String) -> DataTransferStatus {
        DataTransferStatus(message: message, isError: true)
    }
}

/// 补贴启停使用滑动开关表达“参与/不参与计算”，绿色开启、红色关闭，便于做金额对比。
private struct SubsidyStatusToggleStyle: ToggleStyle {
    var enabledAccessibilityLabel = "补贴已开启"
    var disabledAccessibilityLabel = "补贴已关闭"
    var enabledHelp = "关闭补贴"
    var disabledHelp = "开启补贴"

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .padding(3)
            }
            .frame(width: 42, height: 22)
            .overlay {
                Image(systemName: configuration.isOn ? "checkmark" : "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: configuration.isOn ? .leading : .trailing)
                    .padding(.horizontal, 7)
            }
            .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(configuration.isOn ? enabledAccessibilityLabel : disabledAccessibilityLabel))
        .help(configuration.isOn ? enabledHelp : disabledHelp)
    }
}

private struct OffTaskHistoryYear: Identifiable {
    let id: String
    let title: String
    let monthCount: Int
    let paidSeconds: TimeInterval
    let amount: Double
    let recordCount: Int
    let dayCount: Int
}

private struct OffTaskHistoryMonth: Identifiable {
    let id: String
    let title: String
    let dayCount: Int
    let paidSeconds: TimeInterval
    let amount: Double
    let recordCount: Int
}

private struct OffTaskHistoryDay: Identifiable {
    let id: String
    let title: String
    let summaries: [OffTaskSessionSummary]
    let paidSeconds: TimeInterval
    let amount: Double
}

private struct OffTaskDisplayPeriod: Identifiable {
    let id: String
    let title: String
    let rangeText: String
    let summary: OffTaskAggregateSummary
}

private struct WorkSessionDisplayPeriod: Identifiable {
    let id: String
    let title: String
    let rangeText: String
    let summary: WorkSessionAggregateSummary
}

private struct WorkSessionHistoryYear: Identifiable {
    let id: String
    let title: String
    let monthCount: Int
    let seconds: TimeInterval
    let clockOutAmount: Double
    let overtimeAmount: Double
    let recordCount: Int
    let dayCount: Int
}

private struct WorkSessionHistoryMonth: Identifiable {
    let id: String
    let title: String
    let dayCount: Int
    let seconds: TimeInterval
    let clockOutAmount: Double
    let overtimeAmount: Double
    let recordCount: Int
}

private struct WorkSessionHistoryDay: Identifiable {
    let id: String
    let title: String
    let summaries: [WorkSessionRecordSummary]
    let seconds: TimeInterval
    let clockOutAmount: Double
    let overtimeAmount: Double
}

/// 展示页一次性创建的开关较多，使用 SwiftUI 轻量样式替代原生 Toggle 初始化。
private struct SettingsSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                configuration.label
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.accentColor.opacity(0.88) : Color(nsColor: .separatorColor).opacity(0.42))

                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
                        .padding(2)
                }
                .frame(width: 32, height: 18)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityValue(configuration.isOn ? "开启" : "关闭")
    }
}

/// 展示页共用一个系统色板，避免多个 ColorPicker 在切页时批量初始化。
private final class SettingsColorPanelCoordinator: NSObject {
    static let shared = SettingsColorPanelCoordinator()

    private var onChange: ((String) -> Void)?
    private var lastHex: String?

    private override init() {
        super.init()
    }

    func show(color: NSColor, onChange: @escaping (String) -> Void) {
        lastHex = SalaryColor.hex(from: color)
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        let hex = SalaryColor.hex(from: sender.color)
        guard hex != lastHex else { return }
        lastHex = hex
        onChange?(hex)
    }
}

private struct SettingsColorSwatchButton: View {
    let title: String
    let color: NSColor
    let hex: String
    let onChange: (String) -> Void

    var body: some View {
        Button {
            SettingsColorPanelCoordinator.shared.show(color: color, onChange: onChange)
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: color))
                .frame(width: 34, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text("\(title)：\(hex)"))
        .help("选择\(title)")
    }
}

private struct SecondPrecisionDateTimePicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 42, alignment: .leading)

            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 130)

            timeStepper(component: .hour, range: 0...23, suffix: "时")
            timeStepper(component: .minute, range: 0...59, suffix: "分")
            timeStepper(component: .second, range: 0...59, suffix: "秒")
        }
        .controlSize(.small)
    }

    private func timeStepper(component: Calendar.Component, range: ClosedRange<Int>, suffix: String) -> some View {
        Stepper(value: componentBinding(component), in: range) {
            Text("\(componentValue(component))\(suffix)")
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .leading)
        }
        .frame(width: 82)
    }

    private func componentBinding(_ component: Calendar.Component) -> Binding<Int> {
        Binding(
            get: { componentValue(component) },
            set: { newValue in
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                switch component {
                case .hour:
                    components.hour = newValue
                case .minute:
                    components.minute = newValue
                case .second:
                    components.second = newValue
                default:
                    break
                }
                date = Calendar.current.date(from: components) ?? date
            }
        )
    }

    private func componentValue(_ component: Calendar.Component) -> Int {
        Calendar.current.component(component, from: date)
    }
}

private struct OffTaskSessionRowView: View {
    let summary: OffTaskSessionSummary
    let config: SalaryConfig
    @ObservedObject private var tracker = OffTaskTracker.shared
    @State private var isEditing = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var validationMessage: String?
    @State private var showsDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                editContent
            } else {
                readOnlyContent
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 1)
        )
        .onAppear(perform: resetEditingDates)
        .onChange(of: summary.session) { _, _ in
            if !isEditing {
                resetEditingDates()
            }
        }
        .alert("删除这条记录？", isPresented: $showsDeleteAlert) {
            Button("删除", role: .destructive) {
                tracker.deleteSession(id: summary.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，本条记录对应的摸鱼薪资和时长会立即从统计中移除。")
        }
    }

    private var readOnlyContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatRange(summary.session))
                    .font(.caption.monospacedDigit().weight(.semibold))
                if !Calendar.current.isDate(summary.session.start, inSameDayAs: summary.workday) {
                    Text(formatDate(summary.session.start))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
            .frame(width: 132, alignment: .leading)

            Text(formatDuration(summary.paidSeconds))
                .font(.caption.monospacedDigit())
                .foregroundColor(.primary)
                .frame(width: 76, alignment: .leading)

            Text(formatMoney(summary.amount))
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 86, alignment: .leading)

            Group {
                if summary.isActive {
                    Label("进行中", systemImage: "record.circle")
                        .foregroundColor(.orange)
                } else {
                    Text("已结束")
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
            .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)

            Button("编辑") {
                resetEditingDates()
                isEditing = true
            }
            .controlSize(.small)
            .help(summary.isActive ? "编辑进行中记录的开始时间" : "编辑开始和结束时间")

            Button(role: .destructive) {
                showsDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("删除记录")
        }
    }

    private var editContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecondPrecisionDateTimePicker(title: "开始", date: $startDate)

            if summary.isActive {
                Label("进行中的记录会保持开启，只调整开始时间。", systemImage: "record.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                SecondPrecisionDateTimePicker(title: "结束", date: $endDate)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Text(summary.isActive ? "今日金额和计薪时长会按新的开始时间实时重算。" : "金额和计薪时长会按修改后的时间范围实时重算。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("取消") {
                    validationMessage = nil
                    isEditing = false
                    resetEditingDates()
                }
                .controlSize(.small)

                Button("保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
            }
        }
    }

    private func save() {
        let updatedEnd = summary.isActive ? nil : endDate
        if summary.isActive {
            guard startDate < Date() else {
                validationMessage = "开始时间必须早于当前时间"
                return
            }
            guard let activeWindow = SalaryWorkTimeline.activeWindow(containing: Date(), config: config),
                  startDate >= activeWindow.start,
                  startDate < activeWindow.end else {
                validationMessage = "开始时间必须在当前工作窗口内"
                return
            }
            guard SalaryWorkTimeline.paidInterval(containing: startDate, in: activeWindow, config: config) != nil else {
                validationMessage = "开始时间必须在计薪区间内"
                return
            }
        } else {
            guard endDate > startDate else {
                validationMessage = "结束时间必须晚于开始时间"
                return
            }
        }

        guard tracker.updateSessionTimeRange(id: summary.id, start: startDate, end: updatedEnd) else {
            validationMessage = "保存失败，请检查时间范围"
            return
        }

        validationMessage = nil
        isEditing = false
    }

    private func resetEditingDates() {
        startDate = summary.session.start
        endDate = summary.session.end ?? Date()
    }

    private func formatRange(_ session: OffTaskSession) -> String {
        let endText = session.end.map(formatTime) ?? "进行中"
        return "\(formatTime(session.start)) - \(endText)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日 E"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
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

    private func formatMoney(_ value: Double) -> String {
        let amount = String(format: "%.\(config.displayDecimalPlaces)f", value)
        return "¥\(amount)"
    }
}

/// 设置窗口主体。当前采用“左侧分类 + 右侧预加载页面”的结构，减少栏目切换时的重新创建成本。
struct SettingsView: View {
    @ObservedObject var configManager = SalaryConfigManager.shared
    @ObservedObject var holidayManager = ChineseHolidays.shared
    @ObservedObject var shortcutMonitor = GlobalShortcutMonitor.shared
    @ObservedObject var offTaskTracker = OffTaskTracker.shared
    @ObservedObject var workSessionTracker = WorkSessionTracker.shared
    @State private var tempSalaryAmount: String = ""
    @State private var refreshIntervalText: String = ""
    @State private var fixedMonthlyWorkdaysText: String = ""
    @State private var salaryCycleStartDayText: String = ""
    @State private var selectedCategory: SettingsCategory = .salary
    @FocusState private var isSalaryAmountFocused: Bool
    @FocusState private var isRefreshIntervalFocused: Bool
    @FocusState private var isFixedMonthlyWorkdaysFocused: Bool
    @FocusState private var isSalaryCycleStartDayFocused: Bool
    /// 设置窗口左侧分类栏宽度，独立于薪资配置持久化。
    @AppStorage("settings_sidebar_width") private var storedSidebarWidth: Double = 168
    /// 拖动过程中的侧边栏宽度，拖动结束后再写入 `storedSidebarWidth`。
    @State private var sidebarWidth: Double = 168
    @State private var expandedOffTaskHistoryYears: Set<String> = []
    @State private var expandedOffTaskHistoryMonths: Set<String> = []
    @State private var expandedOffTaskHistoryDays: Set<String> = []
    @State private var expandedWorkSessionHistoryYears: Set<String> = []
    @State private var expandedWorkSessionHistoryMonths: Set<String> = []
    @State private var expandedWorkSessionHistoryDays: Set<String> = []
    @State private var dataTransferStatus: DataTransferStatus?
    private let sidebarWidthRange: ClosedRange<Double> = 168...310
    private static let settingsPageContentPadding: CGFloat = 24

    /// 侧边栏宽度拖动时只更新内存状态，拖动结束后再持久化，避免 UserDefaults 连续写入导致抖动。
    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: sidebarWidth)

            SettingsSplitDivider(width: $sidebarWidth, range: sidebarWidthRange) { finalWidth in
                storedSidebarWidth = clampedSidebarWidth(finalWidth)
            }

            settingsMainContent
        }
        .frame(minWidth: 920, idealWidth: 980, minHeight: 600, idealHeight: 680)
        .onAppear {
            sidebarWidth = clampedSidebarWidth(storedSidebarWidth)
            refreshInputTextsFromConfig()
        }
        .onChange(of: configManager.config.resolvedRefreshIntervalSeconds) { _, newValue in
            if !isRefreshIntervalFocused {
                refreshIntervalText = formatRefreshInterval(newValue)
            }
        }
        .onChange(of: configManager.config.resolvedMonthlySalaryCycleStartDay) { _, newValue in
            if !isSalaryCycleStartDayFocused {
                salaryCycleStartDayText = "\(newValue)"
            }
        }
        .onChange(of: configManager.config.resolvedFixedMonthlyWorkdays) { _, newValue in
            if !isFixedMonthlyWorkdaysFocused {
                fixedMonthlyWorkdaysText = formatWorkdayCount(newValue)
            }
        }
        .onChange(of: isRefreshIntervalFocused) { _, isFocused in
            if !isFocused {
                commitRefreshIntervalText()
            }
        }
        .onChange(of: isSalaryAmountFocused) { _, isFocused in
            if !isFocused {
                commitSalaryAmountText()
            }
        }
        .onChange(of: isFixedMonthlyWorkdaysFocused) { _, isFocused in
            if !isFocused {
                commitFixedMonthlyWorkdaysText()
            }
        }
        .onChange(of: isSalaryCycleStartDayFocused) { _, isFocused in
            if !isFocused {
                commitSalaryCycleStartDayText()
            }
        }
    }

    private func clampedSidebarWidth(_ value: Double) -> Double {
        InputValidation.clamped(value, in: sidebarWidthRange)
    }

    private func refreshInputTextsFromConfig() {
        tempSalaryAmount = configManager.config.salaryAmount > 0
            ? InputValidation.formattedDecimal(configManager.config.salaryAmount, maxFractionDigits: 2)
            : ""
        refreshIntervalText = formatRefreshInterval(configManager.config.resolvedRefreshIntervalSeconds)
        fixedMonthlyWorkdaysText = formatWorkdayCount(configManager.config.resolvedFixedMonthlyWorkdays)
        salaryCycleStartDayText = "\(configManager.config.resolvedMonthlySalaryCycleStartDay)"
    }

    /// 左侧分类列表，整块按钮都可点击，避免只能点中文字的问题。
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 6)

            ForEach(SettingsCategory.allCases) { category in
                settingsSidebarButton(category)
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    /// 分类切换禁用动画，避免 SwiftUI 默认转场带来的 100ms 级视觉延迟。
    private func settingsSidebarButton(_ category: SettingsCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: category.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                    Text(category.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, 8)
    }

    /// 每个设置页顶部使用一致的标题结构，降低多栏目维护成本。
    private func settingsHeader(for category: SettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(category.title, systemImage: category.iconName)
                .font(.title3.weight(.semibold))
            Text(category.subtitle)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 只构建当前栏目，避免切页时同时刷新弹窗预览和历史记录等重内容。
    @ViewBuilder
    private var settingsMainContent: some View {
        settingsPage(selectedCategory)
    }

    /// 单个设置页统一放进 ScrollView，右侧预览和设置项可以一起滚动对照。
    @ViewBuilder
    private func settingsPage(_ category: SettingsCategory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsHeader(for: category)
                settingsContent(for: category)
            }
            .padding(Self.settingsPageContentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: Self.settingsPageScrollCoordinateSpace(for: category))
    }

    private static func settingsPageScrollCoordinateSpace(for category: SettingsCategory) -> String {
        "settings-page-scroll-\(category.id)"
    }

    /// 分类到内容区的唯一入口，新增栏目时优先在这里挂载，避免散落在 body 中。
    @ViewBuilder
    private func settingsContent(for category: SettingsCategory) -> some View {
        switch category {
        case .salary:
            salarySection
        case .time:
            workTimeSection
            breakSection
        case .display:
            displaySettingsContent
        case .offTask:
            recordsSettingsContent
        case .shortcut:
            shortcutSettingsSection
        case .calendar:
            workDaySection
            specialWorkdaySection
        case .app:
            dataPortabilitySection
            appBehaviorSection
        }
    }

    /// 记录页包含两组历史统计，使用惰性布局避免切入页面时一次性构建全部折叠明细。
    private var recordsSettingsContent: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            offTaskStatsSection
            workSessionStatsSection
        }
    }

    /// 薪资设置包含基础薪资、补贴、月薪折算方式和六个薪资换算结果。
    private var salarySection: some View {
        GroupBox {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("薪资类型")
                        .frame(width: 80, alignment: .leading)
                    settingsSegmentedControl(
                        options: Array(SalaryType.allCases),
                        selection: $configManager.config.salaryType,
                        title: { $0.title }
                    )
                    .frame(width: 220)
                    Spacer()
                }

                HStack {
                    Text(configManager.config.salaryType.title)
                        .frame(width: 80, alignment: .leading)
                    TextField("0", text: $tempSalaryAmount)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSalaryAmountFocused)
                        .frame(width: 140)
                        .onSubmit {
                            commitSalaryAmountText()
                        }
                        .onChange(of: tempSalaryAmount) { _, newValue in
                            sanitizeAndSaveSalaryAmount(newValue)
                        }
                    Text("元")
                        .foregroundColor(.secondary)
                    Spacer()
                }

                monthlySalaryCalculationSection
                subsidyListSection

                if configManager.config.hasCompensation {
                    Divider()

                    let today = Date()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                        salaryMetricCard(title: "秒薪", value: formatMoney(configManager.config.salaryPerSecond(on: today)))
                        salaryMetricCard(title: "分薪", value: formatMoney(configManager.config.salaryPerMinute(on: today)))
                        salaryMetricCard(title: "时薪", value: formatMoney(configManager.config.salaryPerHour(on: today)))
                        salaryMetricCard(title: "日薪", value: formatMoney(configManager.config.effectiveDailySalary(on: today)))
                        salaryMetricCard(title: "月薪", value: formatMoney(configManager.config.monthlySalary))
                        salaryMetricCard(title: "年薪", value: formatMoney(configManager.config.yearlySalary))
                    }

                    Text(salaryConversionDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        } label: {
            Label("薪资设置", systemImage: "yensign.circle")
                .font(.headline)
        }
    }

    /// 月薪配置拆成“周期范围”和“计薪方式”两步；周期影响归属范围，计薪方式影响折算分母。
    private var monthlySalaryCalculationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("计薪周期")
                    .frame(width: 80, alignment: .leading)
                settingsSegmentedControl(
                    options: Array(SalaryCycleMode.allCases),
                    selection: Binding(
                        get: { configManager.config.resolvedSalaryCycleMode },
                        set: { newValue in
                            configManager.config.salaryCycleMode = newValue
                            ensureSalaryCycleHolidayData()
                        }
                    ),
                    title: { $0.title }
                )
                .frame(width: 180)
                Spacer()
            }

            if configManager.config.resolvedSalaryCycleMode == .fixedMonthlyCycle {
                HStack {
                    Text("周期起始")
                        .frame(width: 80, alignment: .leading)
                    TextField("", text: $salaryCycleStartDayText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .focused($isSalaryCycleStartDayFocused)
                        .frame(width: 46)
                        .onSubmit {
                            commitSalaryCycleStartDayText()
                        }
                        .onChange(of: salaryCycleStartDayText) { _, newValue in
                            sanitizeSalaryCycleStartDayText(newValue)
                        }
                    Text("日")
                        .foregroundColor(.secondary)

                    Stepper("", value: Binding(
                        get: { configManager.config.resolvedMonthlySalaryCycleStartDay },
                        set: { newValue in
                            setSalaryCycleStartDay(newValue)
                        }
                    ), in: 1...31)
                    .labelsHidden()
                    .frame(width: 44)

                    Text("每月 \(configManager.config.resolvedMonthlySalaryCycleStartDay) 日到次月前一日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                }
            }

            let period = configManager.config.currentSalaryCyclePeriod
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.secondary)
                Text("当前周期 \(formatSalaryCyclePeriod(period))，共 \(period.totalDays) 天，计薪 \(period.paidWorkdays) 天")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Text(configManager.config.resolvedSalaryCycleMode == .naturalMonth ? "自然月周期按每月 1 日到当月最后一天归属。" : "固定周期按指定日期起算；当月没有对应日期时，按当月最后一天作为周期起点。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("日薪与月薪折算方式")
                    .frame(width: 140, alignment: .leading)
                Picker("", selection: Binding(
                    get: { configManager.config.resolvedMonthlySalaryCalculationMode },
                    set: { newValue in
                        configManager.config.monthlySalaryCalculationMode = newValue
                        ensureSalaryCycleHolidayData()
                    }
                )) {
                    ForEach(MonthlySalaryCalculationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                Spacer()
            }

            if configManager.config.resolvedMonthlySalaryCalculationMode == .salaryCycleWorkdays,
               configManager.config.salaryType != .daily {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("该计算方式下每周期的工作日数量不同，建议薪资类型为日薪使用该方式更为准确")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if configManager.config.resolvedMonthlySalaryCalculationMode == .fixedAverage {
                HStack {
                    Text("固定天数")
                        .frame(width: 80, alignment: .leading)
                    TextField("", text: $fixedMonthlyWorkdaysText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .focused($isFixedMonthlyWorkdaysFocused)
                        .frame(width: 60)
                        .onSubmit {
                            commitFixedMonthlyWorkdaysText()
                        }
                        .onChange(of: fixedMonthlyWorkdaysText) { _, newValue in
                            sanitizeFixedMonthlyWorkdaysText(newValue)
                        }
                    Text("天")
                        .foregroundColor(.secondary)

                    Stepper("", value: Binding(
                        get: { configManager.config.resolvedFixedMonthlyWorkdays },
                        set: { newValue in
                            setFixedMonthlyWorkdays(newValue)
                        }
                    ), in: SalaryConfig.monthlyWorkdaysRange, step: 0.25)
                    .labelsHidden()
                    .frame(width: 44)

                    Button("默认") {
                        setFixedMonthlyWorkdays(SalaryConfig.averageMonthlyWorkDays)
                    }
                    .controlSize(.small)

                    Text("范围 1-31 天")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Text("固定天数只决定月薪和日薪折算，不改变上面的计薪周期范围。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if configManager.config.resolvedMonthlySalaryCalculationMode == .salaryCycleWorkdays {
                Text("周期内工作天数会随自然月、固定周期、节假日和调休日变化。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            ensureSalaryCycleHolidayData()
        }
    }

    /// 补贴列表和薪资输入放在同一页，避免用户在日薪、月薪和实时收入之间来回推导。
    private var subsidyListSection: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(alignment: .center, spacing: 8) {
                Label("补贴", systemImage: "plus.circle")
                    .font(.callout.weight(.semibold))

                Spacer()

                Button {
                    addSubsidy(type: .daily)
                } label: {
                    Label("按日", systemImage: "calendar")
                }
                .controlSize(.small)

                Button {
                    addSubsidy(type: .monthly)
                } label: {
                    Label("按月", systemImage: "calendar.badge.clock")
                }
                .controlSize(.small)
            }

            Text(subsidyExplanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if configManager.config.subsidies.isEmpty {
                Text("暂无补贴。按日补贴会进入今日收入；按月补贴可只汇入月薪，或按规则平摊到每天。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(configManager.config.subsidies) { subsidy in
                        subsidyRow(subsidy)
                    }
                }
            }
        }
    }

    /// 单条补贴把名称、金额和按月规则集中展示，减少复杂规则散落在多行输入里造成的误解。
    private func subsidyRow(_ subsidy: SalarySubsidy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("", isOn: subsidyEnabledBinding(for: subsidy.id))
                    .labelsHidden()
                    .toggleStyle(SubsidyStatusToggleStyle())

                TextField("补贴名", text: subsidyNameBinding(for: subsidy.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Picker("", selection: subsidyTypeBinding(for: subsidy.id)) {
                    ForEach(SalarySubsidyType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 110)

                TextField("0", value: subsidyAmountBinding(for: subsidy.id), format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)

                Text("元")
                    .foregroundColor(.secondary)

                Spacer(minLength: 0)

                Text(subsidyImpactSummary(for: subsidy))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Button(role: .destructive) {
                    removeSubsidy(subsidy.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除补贴")
            }

            if subsidy.type == .monthly {
                monthlySubsidyRuleRow(subsidy)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 1)
        )
        .opacity(subsidy.enabled ? 1 : 0.62)
    }

    @ViewBuilder
    private func monthlySubsidyRuleRow(_ subsidy: SalarySubsidy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("计入方式")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)

                settingsSegmentedControl(
                    options: Array(MonthlySubsidyApplicationMode.allCases),
                    selection: monthlySubsidyApplicationBinding(for: subsidy.id),
                    title: { $0.title }
                )
                .frame(width: 220)

                Spacer(minLength: 0)
            }

            if subsidy.monthlyApplicationMode == .spreadToDailySalary {
                HStack(spacing: 8) {
                    Text("平摊方式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)

                    Picker("", selection: monthlySubsidyProrationBinding(for: subsidy.id)) {
                        ForEach(MonthlySubsidyProrationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 156)

                    if subsidy.monthlyProrationMode == .fixedDays {
                        TextField(
                            "21.75",
                            value: subsidyFixedDaysBinding(for: subsidy.id),
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)

                        Text("天")
                            .foregroundColor(.secondary)

                        Stepper("", value: subsidyFixedDaysBinding(for: subsidy.id), in: SalaryConfig.monthlyWorkdaysRange, step: 0.25)
                            .labelsHidden()
                            .frame(width: 44)
                    }

                    Spacer(minLength: 0)
                }

                Text(monthlySubsidyProrationDescription(for: subsidy))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(subsidy.enabled ? "只增加月薪和年薪，不进入今日收入、秒薪、分薪和时薪。" : "已关闭，不参与任何薪资计算。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// 只负责工作起止时间和最终计薪时长摘要；时间轴视觉配置放在“展示”栏目。
    private var workTimeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("上班时间")
                        .frame(width: 80, alignment: .leading)
                    timePicker(hour: $configManager.config.workTime.startHour,
                               minute: $configManager.config.workTime.startMinute)
                    Spacer()
                }

                HStack {
                    Text("下班时间")
                        .frame(width: 80, alignment: .leading)
                    timePicker(hour: $configManager.config.workTime.endHour,
                               minute: $configManager.config.workTime.endMinute)
                    Spacer()
                }

                Divider()

                HStack {
                    Text("计薪时长")
                        .frame(width: 80, alignment: .leading)
                    Text(formatDuration(configManager.config.paidWorkMinutes))
                        .fontWeight(.medium)
                    Text(configManager.config.countsBreakTimeAsPaidWork ? "含休息" : "不含休息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(12)
        } label: {
            Label("工作时间", systemImage: "clock")
                .font(.headline)
        }
    }

    /// 午休、晚饭和“休息是否计薪”都属于时间语义，展示颜色不在这里配置。
    private var breakSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用午休", isOn: Binding(
                    get: { configManager.config.usesLunchBreak },
                    set: { configManager.config.lunchBreakEnabled = $0 }
                ))

                if configManager.config.usesLunchBreak {
                    HStack {
                        Text("午休开始")
                            .frame(width: 80, alignment: .leading)
                        timePicker(hour: $configManager.config.lunchBreak.startHour,
                                   minute: $configManager.config.lunchBreak.startMinute)
                        Spacer()
                    }

                    HStack {
                        Text("午休结束")
                            .frame(width: 80, alignment: .leading)
                        timePicker(hour: $configManager.config.lunchBreak.endHour,
                                   minute: $configManager.config.lunchBreak.endMinute)
                        Spacer()
                    }
                }

                Toggle("启用晚饭休息", isOn: $configManager.config.dinnerBreakEnabled)
                    .padding(.top, 4)

                if configManager.config.dinnerBreakEnabled {
                    HStack {
                        Text("晚饭开始")
                            .frame(width: 80, alignment: .leading)
                        timePicker(hour: $configManager.config.dinnerBreak.startHour,
                                   minute: $configManager.config.dinnerBreak.startMinute)
                        Spacer()
                    }

                    HStack {
                        Text("晚饭结束")
                            .frame(width: 80, alignment: .leading)
                        timePicker(hour: $configManager.config.dinnerBreak.endHour,
                                   minute: $configManager.config.dinnerBreak.endMinute)
                        Spacer()
                    }
                }

                Divider()

                Toggle("休息时间计入计薪时长", isOn: Binding(
                    get: { configManager.config.countsBreakTimeAsPaidWork },
                    set: { configManager.config.breakTimeCountsAsPaidWork = $0 }
                ))

                Text(configManager.config.countsBreakTimeAsPaidWork ? "开启后，午休和晚饭休息期间收入仍会累计。" : "关闭时，午休和晚饭休息期间收入暂停累计。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        } label: {
            Label("休息时间", systemImage: "cup.and.saucer")
                .font(.headline)
        }
    }

    /// 计薪日规则和节假日数据状态，节假日失败时允许用户手动重试。
    private var workDaySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("计薪规则", selection: $configManager.config.workDayRule) {
                    ForEach(WorkDayRule.allCases, id: \.self) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.radioGroup)

                if configManager.config.workDayRule == .custom {
                    Divider()
                    Text("选择工作日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        ForEach(1...7, id: \.self) { day in
                            let dayName = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1]
                            Toggle(dayName, isOn: Binding(
                                get: { configManager.config.customWorkDays.contains(day) },
                                set: { isOn in
                                    if isOn {
                                        configManager.config.customWorkDays.insert(day)
                                    } else {
                                        configManager.config.customWorkDays.remove(day)
                                    }
                                }
                            ))
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if configManager.config.workDayRule == .weekdaysOnly {
                    Divider()
                    HStack {
                        if holidayManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在自动获取节假日数据...")
                                .foregroundColor(.secondary)
                        } else if let error = holidayManager.lastError {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("节假日获取失败：\(error)")
                                .foregroundColor(.secondary)
                            Button("重试") {
                                holidayManager.retryFetch()
                            }
                            .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已加载 \(holidayManager.holidays.count) 天节假日 + \(holidayManager.extraWorkdays.count) 天调休日")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.callout)

                    holidayCalendarDisclosure
                }
            }
            .padding(12)
        } label: {
            Label("计薪规则", systemImage: "calendar")
                .font(.headline)
        }
    }

    /// 特殊工作日规则按列表顺序匹配，第一条启用且命中的规则覆盖当天上下班时间。
    private var specialWorkdaySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("用于设置节假日/周末前一天、固定星期或隔周固定日等特殊工作安排；命中后只改当天上下班时间，从而影响当天实时收入和秒/分/时薪。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("规则优先级")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("从上到下匹配，命中后只覆盖当天上下班时间。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        addSpecialWorkdayRule()
                    } label: {
                        Label("新增规则", systemImage: "plus")
                    }
                    .controlSize(.small)
                }

                specialWorkdayTodayStatus

                if configManager.config.specialWorkdayRules.isEmpty {
                    Text("暂无特殊工作日规则。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(configManager.config.specialWorkdayRules.enumerated()), id: \.element.id) { index, rule in
                            specialWorkdayRuleRow(rule, priority: index)
                        }
                    }
                }
            }
            .padding(12)
        } label: {
            Label("特殊工作日", systemImage: "calendar.badge.clock")
                .font(.headline)
        }
    }

    private var specialWorkdayTodayStatus: some View {
        let today = Date()
        let matchedRule = configManager.config.matchingSpecialWorkdayRule(on: today)

        return HStack(spacing: 6) {
            Image(systemName: matchedRule == nil ? "minus.circle" : "checkmark.circle.fill")
                .foregroundColor(matchedRule == nil ? .secondary : .green)

            if let matchedRule {
                Text("今日命中：\(matchedRule.displayName)，\(matchedRule.workTime.startString)-\(matchedRule.workTime.endString)")
            } else {
                Text("今日未命中特殊工作时间")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func specialWorkdayRuleRow(_ rule: SpecialWorkdayRule, priority: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Toggle("", isOn: specialRuleEnabledBinding(for: rule.id))
                    .labelsHidden()
                    .toggleStyle(SubsidyStatusToggleStyle(
                        enabledAccessibilityLabel: "规则已开启",
                        disabledAccessibilityLabel: "规则已关闭",
                        enabledHelp: "关闭规则",
                        disabledHelp: "开启规则"
                    ))

                TextField("规则名", text: specialRuleNameBinding(for: rule.id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 128)

                Picker("", selection: specialRuleKindBinding(for: rule.id)) {
                    ForEach(SpecialWorkdayRuleKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 132)

                Spacer(minLength: 0)

                Text("#\(priority + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 28)

                HStack(spacing: 2) {
                    Button {
                        moveSpecialWorkdayRule(rule.id, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(priority == 0)
                    .help("上移")

                    Button {
                        moveSpecialWorkdayRule(rule.id, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(priority == configManager.config.specialWorkdayRules.count - 1)
                    .help("下移")
                }

                Button(role: .destructive) {
                    removeSpecialWorkdayRule(rule.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除规则")
            }

            specialWorkdayConditionControls(rule)

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text("上班")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    timePicker(
                        hour: specialRuleWorkTimeBinding(for: rule.id, \.startHour),
                        minute: specialRuleWorkTimeBinding(for: rule.id, \.startMinute)
                    )
                }

                HStack(spacing: 8) {
                    Text("下班")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    timePicker(
                        hour: specialRuleWorkTimeBinding(for: rule.id, \.endHour),
                        minute: specialRuleWorkTimeBinding(for: rule.id, \.endMinute)
                    )
                }

                Spacer(minLength: 0)
            }

            Text(specialWorkdayRuleSummary(rule))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 1)
        )
        .opacity(rule.enabled ? 1 : 0.62)
    }

    @ViewBuilder
    private func specialWorkdayConditionControls(_ rule: SpecialWorkdayRule) -> some View {
        switch rule.kind {
        case .dayBeforeRestDay:
            EmptyView()
        case .weekly:
            specialWeekdayToggleRow(for: rule.id)
        case .intervalWeeks:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("每")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper(value: specialRuleIntervalWeeksBinding(for: rule.id), in: SpecialWorkdayRule.intervalWeeksRange) {
                        Text("\(rule.intervalWeeks) 周")
                            .font(.caption.monospacedDigit())
                    }
                    .frame(width: 92)

                    specialWeekdayToggleRow(for: rule.id)
                }

                HStack(spacing: 8) {
                    Text("起始周")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("", selection: specialRuleAnchorDateBinding(for: rule.id), displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 128)
                    Text("以这个日期所在的周一到周日作为第 1 个循环周；之后每隔设定周数，在上面勾选的星期生效。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .exactDate:
            HStack(spacing: 8) {
                Text("日期")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: specialRuleExactDateBinding(for: rule.id), displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 128)
            }
        }
    }

    private func specialWeekdayToggleRow(for id: UUID) -> some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                Toggle(weekdayTitle(day), isOn: specialRuleWeekdayBinding(for: id, day: day))
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// 节假日和调休日展开查看区，使用已过/未过颜色帮助用户快速判断时效。
    private var holidayCalendarDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                holidayDateLegend
                holidayDateColorControls

                Divider()

                holidayDateGrid(
                    title: "节假日",
                    dates: holidayManager.holidays.sorted(),
                    names: holidayManager.holidayNames,
                    emptyText: "暂无节假日数据"
                )

                holidayDateGrid(
                    title: "调休日",
                    dates: holidayManager.extraWorkdays.sorted(),
                    names: holidayManager.extraWorkdayNames,
                    emptyText: "暂无调休日数据"
                )
            }
            .padding(.top, 8)
        } label: {
            Text("查看节假日和调休日")
                .font(.callout)
        }
    }

    /// 颜色图例和说明与用户配置绑定，默认已过红色、未过绿色。
    private var holidayDateLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                holidayLegendItem(
                    title: "已过",
                    color: Color(nsColor: configManager.config.holidayPastNSColor)
                )
                holidayLegendItem(
                    title: "未过",
                    color: Color(nsColor: configManager.config.holidayFutureNSColor)
                )
            }
            Text("早于今天的日期标为已过；今天及之后的日期标为未过。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func holidayLegendItem(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var holidayDateColorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已过颜色")
                    .frame(width: 80, alignment: .leading)
                ColorPicker("", selection: holidayPastColorBinding, supportsOpacity: false)
                    .labelsHidden()
                Text(configManager.config.resolvedHolidayPastColorHex)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Text("未过颜色")
                    .frame(width: 80, alignment: .leading)
                ColorPicker("", selection: holidayFutureColorBinding, supportsOpacity: false)
                    .labelsHidden()
                Text(configManager.config.resolvedHolidayFutureColorHex)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    /// 节假日和调休日共用网格，避免两块列表样式不一致。
    private func holidayDateGrid(
        title: String,
        dates: [String],
        names: [String: String],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text("\(dates.count)天")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if dates.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(dates, id: \.self) { date in
                        holidayDateChip(date: date, name: names[date])
                    }
                }
            }
        }
    }

    /// 单个日期标签展示日期、名称和已过/未过状态。
    private func holidayDateChip(date: String, name: String?) -> some View {
        let state = holidayDateState(for: date)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(formatHolidayDate(date))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(state.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(state.color)
                    .lineLimit(1)
            }

            if let name, !name.isEmpty {
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(state.color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(state.color.opacity(0.28), lineWidth: 1)
        )
    }

    /// 状态栏和金额格式设置放在展示页顶部，因为它们会影响弹窗预览中的金额格式。
    private var statusBarDisplaySection: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("状态栏")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Toggle("显示实时薪资", isOn: Binding(
                        get: { configManager.config.displaysEarningsInStatusBar },
                        set: { configManager.config.statusBarShowsEarnings = $0 }
                    ))

                    Toggle("显示 App 图标", isOn: Binding(
                        get: { configManager.config.statusBarDisplaysAppIcon },
                        set: { configManager.config.statusBarShowsAppIcon = $0 }
                    ))

                    Toggle("显示摸鱼状态图标", isOn: Binding(
                        get: { configManager.config.statusBarDisplaysOffTaskStatusIcon },
                        set: { configManager.config.statusBarShowsOffTaskStatusIcon = $0 }
                    ))

                    Toggle("仅摸鱼中显示", isOn: Binding(
                        get: { configManager.config.statusBarDisplaysOffTaskStatusIconOnlyWhenActive },
                        set: { configManager.config.statusBarShowsOffTaskStatusIconOnlyWhenActive = $0 }
                    ))
                    .padding(.leading, 18)
                    .disabled(!configManager.config.statusBarDisplaysOffTaskStatusIcon)
                    .help("关闭后，未摸鱼时也会在状态栏显示灰色鱼图标。")

                    Toggle("显示 ¥ 符号", isOn: Binding(
                        get: { configManager.config.statusBarDisplaysCurrencySymbol },
                        set: { configManager.config.statusBarShowsCurrencySymbol = $0 }
                    ))
                    .disabled(!configManager.config.displaysEarningsInStatusBar)

                    HStack {
                        Text("数字动画")
                            .frame(width: 70, alignment: .leading)
                        settingsSegmentedControl(
                            options: Array(StatusBarSalaryAnimationStyle.allCases),
                            selection: Binding(
                                get: { configManager.config.resolvedStatusBarSalaryAnimationStyle },
                                set: { configManager.config.statusBarSalaryAnimationStyle = $0 }
                            ),
                            title: { $0.title }
                        )
                        .frame(maxWidth: 220)
                    }
                    .disabled(!configManager.config.displaysEarningsInStatusBar)

                    HStack {
                        Text("金额颜色")
                            .frame(width: 70, alignment: .leading)
                        settingsColorControl(
                            title: "金额颜色",
                            color: configManager.config.statusBarSalaryNSColor,
                            hex: configManager.config.resolvedStatusBarSalaryColorHex
                        ) { hex in
                            configManager.config.statusBarSalaryColorHex = hex
                        }
                        Button("默认") {
                            configManager.config.statusBarSalaryColorHex = nil
                        }
                        .controlSize(.small)
                    }
                    .disabled(!configManager.config.displaysEarningsInStatusBar)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("金额")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("小数位")
                            .frame(width: 70, alignment: .leading)
                        settingsSegmentedControl(
                            options: Array(0...3),
                            selection: Binding(
                                get: { configManager.config.displayDecimalPlaces },
                                set: { configManager.config.moneyDecimalPlaces = $0 }
                            ),
                            title: { "\($0)" }
                        )
                        .frame(width: 140)
                        Spacer(minLength: 0)
                    }

                    Text("影响状态栏、弹窗和薪资换算展示。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(12)
        } label: {
            Label("状态栏与金额", systemImage: "menubar.rectangle")
                .font(.headline)
        }
    }

    /// 展示页采用左侧设置、右侧预览的同屏排布，便于边调边看。
    private var displaySettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusBarDisplaySection

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    popoverDisplaySection
                    workProgressDisplaySection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                displayPreviewStickyColumn
            }
        }
        .toggleStyle(SettingsSwitchToggleStyle())
    }

    /// 右侧预览直接复用真实弹窗组件，避免设置页和实际弹窗出现两套展示逻辑。
    private var displayPreviewPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                PopoverPreviewView(config: configManager.config)
            }
            .padding(12)
        } label: {
            Label("弹窗预览", systemImage: "eye")
                .font(.headline)
        }
    }

    /// 预览和左侧配置仍在同一个滚动页内；用无状态几何计算固定位置，避免滚动时刷新整个设置页。
    private var displayPreviewStickyColumn: some View {
        GeometryReader { proxy in
            let anchorMinY = proxy.frame(in: .named(Self.settingsPageScrollCoordinateSpace(for: .display))).minY
            let stickyOffset = max(0, Self.settingsPageContentPadding - anchorMinY)
            displayPreviewPanel
                .offset(y: stickyOffset)
                .zIndex(1)
        }
        .frame(width: 300, height: 0, alignment: .topLeading)
    }

    /// 弹窗内容开关逐项独立控制，避免“全部展示/全部隐藏”的粗粒度体验。
    private var popoverDisplaySection: some View {
        let settlementTitle = offTaskSettlementPeriodTitle(configManager.config)

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("打开弹窗默认隐藏金额", isOn: Binding(
                    get: { configManager.config.opensPrivatePopoverFromStatusItemClick },
                    set: { configManager.config.statusItemClickShowsPrivatePopover = $0 }
                ))

                Divider()

                Text("弹窗内容")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    popoverContentGroup("基础信息") {
                        HStack(spacing: 10) {
                            popoverContentToggle("当前收入", isOn: Binding(
                                get: { configManager.config.popoverDisplaysCurrentEarnings },
                                set: { configManager.config.popoverShowsCurrentEarnings = $0 }
                            ))

                            popoverContentToggle("今日剩余", isOn: Binding(
                                get: { configManager.config.popoverDisplaysRemainingEarnings },
                                set: { configManager.config.popoverShowsRemainingEarnings = $0 }
                            ))
                        }

                        HStack(spacing: 10) {
                            popoverContentToggle("工作状态", isOn: Binding(
                                get: { configManager.config.popoverDisplaysWorkStatus },
                                set: { configManager.config.popoverShowsWorkStatus = $0 }
                            ))

                            popoverContentToggle("工作进度条", isOn: Binding(
                                get: { configManager.config.popoverDisplaysWorkProgress },
                                set: { configManager.config.popoverShowsWorkProgress = $0 }
                            ))
                        }
                    }

                    popoverContentGroup("薪资指标") {
                        HStack(spacing: 10) {
                            popoverContentToggle("秒薪", isOn: Binding(
                                get: { configManager.config.popoverDisplaysSecondSalary },
                                set: { configManager.config.popoverShowsSecondSalary = $0 }
                            ))

                            popoverContentToggle("分薪", isOn: Binding(
                                get: { configManager.config.popoverDisplaysMinuteSalary },
                                set: { configManager.config.popoverShowsMinuteSalary = $0 }
                            ))
                        }

                        HStack(spacing: 10) {
                            popoverContentToggle("时薪", isOn: Binding(
                                get: { configManager.config.popoverDisplaysHourlySalary },
                                set: { configManager.config.popoverShowsHourlySalary = $0 }
                            ))

                            popoverContentToggle("日薪", isOn: Binding(
                                get: { configManager.config.popoverDisplaysDailySalary },
                                set: { configManager.config.popoverShowsDailySalary = $0 }
                            ))
                        }

                        HStack(spacing: 10) {
                            popoverContentToggle("月薪", isOn: Binding(
                                get: { configManager.config.popoverDisplaysMonthlySalary },
                                set: { configManager.config.popoverShowsMonthlySalary = $0 }
                            ))

                            popoverContentToggle("年薪", isOn: Binding(
                                get: { configManager.config.popoverDisplaysYearlySalary },
                                set: { configManager.config.popoverShowsYearlySalary = $0 }
                            ))
                        }
                    }

                    popoverContentGroup("摸鱼状态") {
                        HStack(spacing: 10) {
                            popoverContentToggle("状态入口", isOn: Binding(
                                get: { configManager.config.popoverDisplaysOffTaskStatus },
                                set: { configManager.config.popoverShowsOffTaskStatus = $0 }
                            ))

                            popoverContentToggle("今日摸鱼", isOn: Binding(
                                get: { configManager.config.popoverDisplaysTodayOffTaskSummary },
                                set: { configManager.config.popoverShowsTodayOffTaskSummary = $0 }
                            ))
                        }

                        Text("摸鱼薪资")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            popoverContentToggle("本日摸鱼薪资", isOn: Binding(
                                get: { configManager.config.popoverDisplaysTodayOffTaskSalary },
                                set: { configManager.config.popoverShowsTodayOffTaskSalary = $0 }
                            ))

                            popoverContentToggle("本周摸鱼薪资", isOn: Binding(
                                get: { configManager.config.popoverDisplaysWeekOffTaskSalary },
                                set: { configManager.config.popoverShowsWeekOffTaskSalary = $0 }
                            ))
                        }

                        HStack(spacing: 10) {
                            popoverContentToggle("\(settlementTitle)摸鱼薪资", isOn: Binding(
                                get: { configManager.config.popoverDisplaysSalaryCycleOffTaskSalary },
                                set: { configManager.config.popoverShowsSalaryCycleOffTaskSalary = $0 }
                            ))

                            popoverContentToggle("历史摸鱼薪资", isOn: Binding(
                                get: { configManager.config.popoverDisplaysHistoricalOffTaskSalary },
                                set: { configManager.config.popoverShowsHistoricalOffTaskSalary = $0 }
                            ))
                        }

                        Text("摸鱼时长")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            popoverContentToggle("本日摸鱼时长", isOn: Binding(
                                get: { configManager.config.popoverDisplaysTodayOffTaskDuration },
                                set: { configManager.config.popoverShowsTodayOffTaskDuration = $0 }
                            ))

                            popoverContentToggle("本周摸鱼时长", isOn: Binding(
                                get: { configManager.config.popoverDisplaysWeekOffTaskDuration },
                                set: { configManager.config.popoverShowsWeekOffTaskDuration = $0 }
                            ))
                        }

                        HStack(spacing: 10) {
                            popoverContentToggle("\(settlementTitle)摸鱼时长", isOn: Binding(
                                get: { configManager.config.popoverDisplaysSalaryCycleOffTaskDuration },
                                set: { configManager.config.popoverShowsSalaryCycleOffTaskDuration = $0 }
                            ))

                            popoverContentToggle("历史摸鱼时长", isOn: Binding(
                                get: { configManager.config.popoverDisplaysHistoricalOffTaskDuration },
                                set: { configManager.config.popoverShowsHistoricalOffTaskDuration = $0 }
                            ))
                        }
                    }

                    popoverContentGroup("提前下班与加班") {
                        HStack(spacing: 10) {
                            popoverContentToggle("状态入口", isOn: Binding(
                                get: { configManager.config.popoverDisplaysWorkSessionStatus },
                                set: { configManager.config.popoverShowsWorkSessionStatus = $0 }
                            ))

                            popoverContentToggle("今日提示", isOn: Binding(
                                get: { configManager.config.popoverDisplaysTodayWorkSessionSummary },
                                set: { configManager.config.popoverShowsTodayWorkSessionSummary = $0 }
                            ))
                        }

                        HStack(spacing: 10) {
                            popoverContentToggle("提前下班入口", isOn: Binding(
                                get: { configManager.config.popoverDisplaysClockOutAction },
                                set: { configManager.config.popoverShowsClockOutAction = $0 }
                            ))

                            popoverContentToggle("加班入口", isOn: Binding(
                                get: { configManager.config.popoverDisplaysOvertimeAction },
                                set: { configManager.config.popoverShowsOvertimeAction = $0 }
                            ))
                        }
                    }

                    popoverContentGroup("其他") {
                        HStack(spacing: 10) {
                            popoverContentToggle("打工语录", isOn: Binding(
                                get: { configManager.config.popoverDisplaysQuote },
                                set: { configManager.config.popoverShowsQuote = $0 }
                            ))

                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack {
                    Text("薪资颜色")
                        .frame(width: 80, alignment: .leading)
                    settingsColorControl(
                        title: "薪资颜色",
                        color: configManager.config.popoverSalaryNSColor,
                        hex: configManager.config.resolvedPopoverSalaryColorHex
                    ) { hex in
                        configManager.config.popoverSalaryColorHex = hex
                    }
                    Spacer()
                }
            }
            .padding(12)
        } label: {
            Label("弹窗展示", systemImage: "rectangle.on.rectangle")
                .font(.headline)
        }
    }

    /// 时间轴颜色、网格和标签都属于展示层配置，和真实工作时间解耦。
    private var workProgressDisplaySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("时间轴颜色")
                        .frame(width: 80, alignment: .leading)
                    settingsColorControl(
                        title: "时间轴颜色",
                        color: configManager.config.workProgressNSColor,
                        hex: configManager.config.resolvedWorkProgressColorHex
                    ) { hex in
                        configManager.config.workProgressColorHex = hex
                    }
                    Spacer()
                }

                Toggle("显示时间网格", isOn: Binding(
                    get: { configManager.config.workProgressDisplaysGrid },
                    set: { configManager.config.workProgressShowsGrid = $0 }
                ))

                if configManager.config.workProgressDisplaysGrid {
                    HStack {
                        Text("网格精度")
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { configManager.config.workProgressGridIntervalMinutes },
                            set: { configManager.config.workProgressGridMinutes = $0 }
                        )) {
                            ForEach(SalaryConfig.workProgressGridIntervalOptions, id: \.self) { minutes in
                                Text(formatGridInterval(minutes)).tag(minutes)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 96)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Toggle("显示时间段标签", isOn: Binding(
                    get: { configManager.config.workProgressDisplaysSegmentLabels },
                    set: { configManager.config.workProgressShowsSegmentLabels = $0 }
                ))

                HStack {
                    Text("进度小数位")
                        .frame(width: 80, alignment: .leading)
                    settingsSegmentedControl(
                        options: Array(SalaryConfig.workProgressDecimalPlacesRange),
                        selection: Binding(
                            get: { configManager.config.workProgressDisplayDecimalPlaces },
                            set: { configManager.config.workProgressDecimalPlaces = $0 }
                        ),
                        title: { "\($0)" }
                    )
                    .frame(width: 140)
                    Spacer()
                }

                Divider()

                Toggle("显示午休颜色", isOn: Binding(
                    get: { configManager.config.displaysLunchBreakColor },
                    set: { configManager.config.lunchBreakShowsColor = $0 }
                ))

                HStack {
                    Text("午休颜色")
                        .frame(width: 80, alignment: .leading)
                    settingsColorControl(
                        title: "午休颜色",
                        color: configManager.config.lunchBreakNSColor,
                        hex: configManager.config.resolvedLunchBreakColorHex
                    ) { hex in
                        configManager.config.lunchBreakColorHex = hex
                    }
                        .disabled(!configManager.config.displaysLunchBreakColor)
                    Spacer()
                }

                Toggle("显示晚饭颜色", isOn: Binding(
                    get: { configManager.config.displaysDinnerBreakColor },
                    set: { configManager.config.dinnerBreakShowsColor = $0 }
                ))

                HStack {
                    Text("晚饭颜色")
                        .frame(width: 80, alignment: .leading)
                    settingsColorControl(
                        title: "晚饭颜色",
                        color: configManager.config.dinnerBreakNSColor,
                        hex: configManager.config.resolvedDinnerBreakColorHex
                    ) { hex in
                        configManager.config.dinnerBreakColorHex = hex
                    }
                        .disabled(!configManager.config.displaysDinnerBreakColor)
                    Spacer()
                }

                Text("这里只控制时间轴视觉；工作、午休和晚饭的具体时间仍在“时间”里设置。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        } label: {
            Label("时间轴展示", systemImage: "paintpalette")
                .font(.headline)
        }
    }

    /// 提前下班和加班统计按原始记录实时换算；提前下班算赚到的钱，加班默认无收入因此算亏损。
    private var workSessionStatsSection: some View {
        let config = configManager.config
        let today = workSessionTracker.currentSummary(config: config)
        let displayPeriods = workSessionDisplayPeriods(config: config, today: today)
        let clockOutAvailability = workSessionTracker.clockOutAvailability(config: config)
        let overtimeAvailability = workSessionTracker.overtimeAvailability(config: config)
        let hasClockOut = workSessionTracker.clockOutSession(for: today.workday) != nil
        let hasOvertime = workSessionTracker.latestOvertimeSession(for: today.workday) != nil

        return LazyVStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workSessionStatusText(today))
                                .font(.callout.weight(.semibold))
                            Text(workSessionStatusDetail(today, clockOutAvailability: clockOutAvailability, overtimeAvailability: overtimeAvailability))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                if hasClockOut {
                                    workSessionTracker.undoClockOut(for: today.workday)
                                } else {
                                    if offTaskTracker.isActive {
                                        offTaskTracker.stop()
                                    }
                                    workSessionTracker.clockOut(config: config)
                                }
                            } label: {
                                Label(hasClockOut ? "撤回提前下班" : "提前下班", systemImage: hasClockOut ? "arrow.uturn.backward" : "checkmark.circle.fill")
                            }
                            .disabled(!hasClockOut && !clockOutAvailability.canClockOut)
                            .help(hasClockOut ? "撤回今日提前下班记录。" : clockOutAvailability.helpMessage)
                            .controlSize(.small)

                            Button {
                                workSessionTracker.undoLatestOvertime(config: config)
                            } label: {
                                Label("撤回加班", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(!hasOvertime)
                            .help("撤回最近一条今日加班记录。")
                            .controlSize(.small)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                        workSessionStatCard(title: "提前下班进账", value: formatMoney(today.clockOutAmount), tint: .green)
                        workSessionStatCard(title: "提前下班时长", value: formatOffTaskDuration(today.clockOutSeconds), tint: .green)
                        workSessionStatCard(title: "加班亏损", value: formatMoney(today.overtimeAmount), tint: .indigo)
                        workSessionStatCard(title: "加班时长", value: formatOffTaskDuration(today.overtimeSeconds), tint: .indigo)
                    }
                }
                .padding(12)
            } label: {
                Label("提前下班与加班", systemImage: "timer")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(displayPeriods) { period in
                            workSessionPeriodCard(period)
                        }
                    }
                }
                .padding(12)
            } label: {
                Label("提前下班 / 加班概览", systemImage: "chart.bar.xaxis")
                    .font(.headline)
            }

            workSessionHistorySummarySection(config: config)
        }
    }

    private func workSessionHistorySummarySection(config: SalaryConfig) -> some View {
        let total = workSessionTracker.totalSummary(config: config)
        let summaries = workSessionTracker.recordSummaries(config: config)
        let historyYears = workSessionHistoryYears(from: summaries)

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                    workSessionStatCard(title: "历史提前下班进账", value: formatMoney(total.clockOutAmount), tint: .green)
                    workSessionStatCard(title: "历史提前下班时长", value: formatOffTaskDuration(total.clockOutSeconds), tint: .green)
                    workSessionStatCard(title: "历史加班亏损", value: formatMoney(total.overtimeAmount), tint: .indigo)
                    workSessionStatCard(title: "历史加班时长", value: formatOffTaskDuration(total.overtimeSeconds), tint: .indigo)
                }

                Divider()

                HStack(spacing: 8) {
                    Label("年 / 月 / 日", systemImage: "square.stack.3d.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    offTaskHistoryPill("提前下班 \(total.clockOutCount)次")
                    offTaskHistoryPill("加班 \(total.overtimeCount)次")
                    offTaskHistoryPill("\(historyYears.reduce(0) { $0 + $1.dayCount })天")
                }

                if historyYears.isEmpty {
                    Text("暂无提前下班或加班记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(historyYears) { year in
                            workSessionHistoryYearDisclosure(year, summaries: summaries)
                        }
                    }
                }
            }
            .padding(12)
        } label: {
            Label("提前下班 / 加班历史记录", systemImage: "tray.full")
                .font(.headline)
        }
    }

    private func workSessionDisplayPeriods(config: SalaryConfig, today: WorkSessionDailySummary) -> [WorkSessionDisplayPeriod] {
        let now = Date()
        let todayAggregate = WorkSessionAggregateSummary(
            clockOutSeconds: today.clockOutSeconds,
            clockOutAmount: today.clockOutAmount,
            clockOutCount: today.clockOutCount,
            clockOutDayCount: today.hasClockOutRecords ? 1 : 0,
            overtimeSeconds: today.overtimeSeconds,
            overtimeAmount: today.overtimeAmount,
            overtimeCount: today.overtimeCount,
            overtimeDayCount: today.hasOvertimeRecords ? 1 : 0
        )
        let week = offTaskWeekPeriod(containing: now)
        let settlement = config.salaryCyclePeriod(containing: now)
        let weekSummary = workSessionTracker.summary(from: week.start, toExclusive: week.endExclusive, config: config, now: now)
        let settlementSummary = workSessionTracker.summary(from: settlement.start, toExclusive: settlement.endExclusive, config: config, now: now)

        return [
            WorkSessionDisplayPeriod(
                id: "today",
                title: "本日",
                rangeText: formatOffTaskDateRange(start: today.workday, endExclusive: Calendar.current.date(byAdding: .day, value: 1, to: today.workday) ?? today.workday),
                summary: todayAggregate
            ),
            WorkSessionDisplayPeriod(
                id: "week",
                title: "本周",
                rangeText: formatOffTaskDateRange(start: week.start, endExclusive: week.endExclusive),
                summary: weekSummary
            ),
            WorkSessionDisplayPeriod(
                id: "settlement",
                title: offTaskSettlementPeriodTitle(config),
                rangeText: formatOffTaskDateRange(start: settlement.start, endExclusive: settlement.endExclusive),
                summary: settlementSummary
            )
        ]
    }

    private func workSessionPeriodCard(_ period: WorkSessionDisplayPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(period.title)
                    .font(.callout.weight(.semibold))
                Text(period.rangeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                workSessionPeriodMetric(title: "提前下班进账", value: formatMoney(period.summary.clockOutAmount))
                workSessionPeriodMetric(title: "提前下班时长", value: formatOffTaskDuration(period.summary.clockOutSeconds))
                workSessionPeriodMetric(title: "加班亏损", value: formatMoney(period.summary.overtimeAmount))
                workSessionPeriodMetric(title: "加班时长", value: formatOffTaskDuration(period.summary.overtimeSeconds))

                HStack(spacing: 8) {
                    offTaskHistoryPill("提前下班\(period.summary.clockOutCount)次")
                    offTaskHistoryPill("加班\(period.summary.overtimeCount)次")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.blue.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        )
    }

    private func workSessionPeriodMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    /// 提前下班与加班历史同样按年、月、日折叠，避免累计数据和明细割裂。
    private func workSessionHistoryYears(from summaries: [WorkSessionRecordSummary]) -> [WorkSessionHistoryYear] {
        let grouped = Dictionary(grouping: summaries) { summary in
            offTaskYearKey(summary.workday)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let records = grouped[key] else {
                return nil
            }

            return WorkSessionHistoryYear(
                id: key,
                title: formatOffTaskYear(records.first?.workday ?? Date()),
                monthCount: Set(records.map { offTaskMonthKey($0.workday) }).count,
                seconds: records.reduce(0) { $0 + $1.seconds },
                clockOutAmount: records.filter { $0.kind == .clockOut }.reduce(0) { $0 + $1.amount },
                overtimeAmount: records.filter { $0.kind == .overtime }.reduce(0) { $0 + $1.amount },
                recordCount: records.count,
                dayCount: Set(records.map { offTaskDayKey($0.workday) }).count
            )
        }
    }

    private func workSessionHistoryMonths(from summaries: [WorkSessionRecordSummary]) -> [WorkSessionHistoryMonth] {
        let grouped = Dictionary(grouping: summaries) { summary in
            offTaskMonthKey(summary.workday)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let records = grouped[key] else {
                return nil
            }

            return WorkSessionHistoryMonth(
                id: key,
                title: formatOffTaskMonth(records.first?.workday ?? Date()),
                dayCount: Set(records.map { offTaskDayKey($0.workday) }).count,
                seconds: records.reduce(0) { $0 + $1.seconds },
                clockOutAmount: records.filter { $0.kind == .clockOut }.reduce(0) { $0 + $1.amount },
                overtimeAmount: records.filter { $0.kind == .overtime }.reduce(0) { $0 + $1.amount },
                recordCount: records.count
            )
        }
    }

    private func workSessionHistoryDays(from summaries: [WorkSessionRecordSummary]) -> [WorkSessionHistoryDay] {
        let grouped = Dictionary(grouping: summaries) { summary in
            offTaskDayKey(summary.workday)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let records = grouped[key]?.sorted(by: { lhs, rhs in
                lhs.end > rhs.end
            }) else {
                return nil
            }

            return WorkSessionHistoryDay(
                id: key,
                title: formatOffTaskDay(records.first?.workday ?? Date()),
                summaries: records,
                seconds: records.reduce(0) { $0 + $1.seconds },
                clockOutAmount: records.filter { $0.kind == .clockOut }.reduce(0) { $0 + $1.amount },
                overtimeAmount: records.filter { $0.kind == .overtime }.reduce(0) { $0 + $1.amount }
            )
        }
    }

    private func workSessionHistoryYearDisclosure(_ year: WorkSessionHistoryYear, summaries: [WorkSessionRecordSummary]) -> some View {
        let isExpanded = expandedWorkSessionHistoryYears.contains(year.id)

        return VStack(alignment: .leading, spacing: 0) {
            workSessionHistoryDisclosureButton(isExpanded: isExpanded) {
                toggleOffTaskHistoryExpansion(year.id, in: &expandedWorkSessionHistoryYears)
            } label: {
                workSessionHistoryGroupLabel(
                    icon: "calendar",
                    title: year.title,
                    detail: "共计\(year.monthCount)月 | \(year.dayCount)天",
                    recordCount: year.recordCount,
                    seconds: year.seconds,
                    clockOutAmount: year.clockOutAmount,
                    overtimeAmount: year.overtimeAmount
                )
            }

            if isExpanded {
                let yearSummaries = summaries.filter { summary in
                    offTaskYearKey(summary.workday) == year.id
                }
                let months = workSessionHistoryMonths(from: yearSummaries)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(months) { month in
                        workSessionHistoryMonthDisclosure(month, summaries: yearSummaries)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.38), lineWidth: 1)
        )
    }

    private func workSessionHistoryMonthDisclosure(_ month: WorkSessionHistoryMonth, summaries: [WorkSessionRecordSummary]) -> some View {
        let isExpanded = expandedWorkSessionHistoryMonths.contains(month.id)

        return VStack(alignment: .leading, spacing: 0) {
            workSessionHistoryDisclosureButton(isExpanded: isExpanded) {
                toggleOffTaskHistoryExpansion(month.id, in: &expandedWorkSessionHistoryMonths)
            } label: {
                workSessionHistoryGroupLabel(
                    icon: "calendar.circle",
                    title: month.title,
                    detail: "共计\(month.dayCount)天",
                    recordCount: month.recordCount,
                    seconds: month.seconds,
                    clockOutAmount: month.clockOutAmount,
                    overtimeAmount: month.overtimeAmount
                )
            }

            if isExpanded {
                let monthSummaries = summaries.filter { summary in
                    offTaskMonthKey(summary.workday) == month.id
                }
                let days = workSessionHistoryDays(from: monthSummaries)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(days) { day in
                        workSessionHistoryDayDisclosure(day)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
        )
    }

    private func workSessionHistoryDayDisclosure(_ day: WorkSessionHistoryDay) -> some View {
        let isExpanded = expandedWorkSessionHistoryDays.contains(day.id)

        return VStack(alignment: .leading, spacing: 0) {
            workSessionHistoryDisclosureButton(isExpanded: isExpanded) {
                toggleOffTaskHistoryExpansion(day.id, in: &expandedWorkSessionHistoryDays)
            } label: {
                workSessionHistoryGroupLabel(
                    icon: "calendar.day.timeline.left",
                    title: day.title,
                    detail: nil,
                    recordCount: day.summaries.count,
                    seconds: day.seconds,
                    clockOutAmount: day.clockOutAmount,
                    overtimeAmount: day.overtimeAmount
                )
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("类型")
                            .frame(width: 72, alignment: .leading)
                        Text("起止时间")
                            .frame(width: 132, alignment: .leading)
                        Text("时长")
                            .frame(width: 86, alignment: .leading)
                        Text("金额")
                            .frame(width: 96, alignment: .leading)
                        Text("状态")
                            .frame(width: 64, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                    ForEach(day.summaries) { summary in
                        workSessionRecordRow(summary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
        )
    }

    private func workSessionHistoryDisclosureButton<Label: View>(
        isExpanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue)
                }
                .frame(width: 28, height: 28)

                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isExpanded ? "收起记录" : "展开记录")
    }

    private func workSessionHistoryGroupLabel(
        icon: String,
        title: String,
        detail: String?,
        recordCount: Int,
        seconds: TimeInterval,
        clockOutAmount: Double,
        overtimeAmount: Double
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 16)

            Text(title)
                .font(.callout.weight(.semibold))

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 10)

            offTaskHistoryPill("\(recordCount)次")
            offTaskHistoryPill(formatOffTaskDuration(seconds))
            Text("进账 \(formatMoney(clockOutAmount)) / 亏损 \(formatMoney(overtimeAmount))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(.primary)
    }

    private func workSessionRecordRow(_ summary: WorkSessionRecordSummary) -> some View {
        let tint: Color = summary.kind == .clockOut ? .green : .indigo

        return HStack(spacing: 10) {
            Label(summary.kind.title, systemImage: summary.kind == .clockOut ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 72, alignment: .leading)

            Text("\(formatWorkSessionClock(summary.start)) - \(formatWorkSessionClock(summary.end))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 132, alignment: .leading)

            Text(formatOffTaskDuration(summary.seconds))
                .font(.caption.monospacedDigit())
                .frame(width: 86, alignment: .leading)

            Text(formatMoney(summary.amount))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 96, alignment: .leading)

            Text(summary.isActive ? "进行中" : "已完成")
                .font(.caption2)
                .foregroundColor(summary.isActive ? tint : .secondary)
                .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 1)
        )
    }

    /// 摸鱼统计直接按已记录区间和当前薪资规则实时汇总，便于对照当日、周期和长期数据。
    private var offTaskStatsSection: some View {
        let config = configManager.config
        let today = offTaskTracker.currentSummary(config: config)
        let displayPeriods = offTaskDisplayPeriods(config: config, today: today)
        let startAvailability = offTaskTracker.startAvailability(config: config)
        let statusDetail = offTaskStatusDetail(today)

        return LazyVStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(offTaskStatusText(today))
                                .font(.callout.weight(.semibold))
                            Text(statusDetail)
                                .font(.caption)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.15), value: statusDetail)
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }

                        Spacer()

                        Button {
                            offTaskTracker.toggle(config: config)
                        } label: {
                            Label(offTaskTracker.isActive ? "结束摸鱼" : "开启摸鱼", systemImage: offTaskTracker.isActive ? "stop.fill" : "play.fill")
                        }
                        .disabled(!offTaskTracker.isActive && !startAvailability.canStart)
                        .help(offTaskToggleHelp(isActive: offTaskTracker.isActive, availability: startAvailability))
                        .controlSize(.small)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                        offTaskStatCard(title: "摸鱼薪资", value: formatMoney(today.amount))
                        offTaskStatCard(title: "计薪时长", value: formatOffTaskDuration(today.paidSeconds))
                        offTaskStatCard(title: "摸鱼次数", value: "\(today.sessionCount)")
                        offTaskStatCard(title: "今日占比", value: formatOffTaskPercent(today))
                    }
                }
                .padding(12)
            } label: {
                Label("当前状态", systemImage: "fish")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(displayPeriods) { period in
                            offTaskPeriodCard(period)
                        }
                    }
                }
                .padding(12)
            } label: {
                Label("数据概览", systemImage: "chart.bar.xaxis")
                    .font(.headline)
            }

            offTaskHistorySummarySection(config: config)
        }
    }

    private func offTaskHistorySummarySection(config: SalaryConfig) -> some View {
        let total = offTaskTracker.totalSummary(config: config)
        let summaries = offTaskTracker.sessionSummaries(config: config)
        let historyYears = offTaskHistoryYears(from: summaries)

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                    offTaskStatCard(title: "历史摸鱼薪资", value: formatMoney(total.amount))
                    offTaskStatCard(title: "历史摸鱼时长", value: formatOffTaskDuration(total.paidSeconds))
                    offTaskStatCard(title: "历史摸鱼次数", value: "\(total.sessionCount)")
                    offTaskStatCard(title: "历史摸鱼天数", value: "\(total.dayCount)")
                }

                Divider()

                HStack(spacing: 8) {
                    Label("年 / 月 / 日", systemImage: "square.stack.3d.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    offTaskHistoryPill("\(total.sessionCount)次")
                    offTaskHistoryPill("\(total.dayCount)天")
                }

                if historyYears.isEmpty {
                    Text("暂无摸鱼记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(historyYears) { year in
                            offTaskHistoryYearDisclosure(year, summaries: summaries, config: config)
                        }
                    }
                }
            }
            .padding(12)
        } label: {
            Label("历史记录", systemImage: "tray.full")
                .font(.headline)
        }
    }

    private func offTaskDisplayPeriods(config: SalaryConfig, today: OffTaskDailySummary) -> [OffTaskDisplayPeriod] {
        let now = Date()
        let todayAggregate = OffTaskAggregateSummary(
            paidSeconds: today.paidSeconds,
            amount: today.amount,
            sessionCount: today.sessionCount,
            dayCount: today.hasRecords ? 1 : 0
        )
        let week = offTaskWeekPeriod(containing: now)
        let settlement = config.salaryCyclePeriod(containing: now)
        let weekSummary = offTaskTracker.summary(from: week.start, toExclusive: week.endExclusive, config: config, now: now)
        let settlementSummary = offTaskTracker.summary(from: settlement.start, toExclusive: settlement.endExclusive, config: config, now: now)

        return [
            OffTaskDisplayPeriod(
                id: "today",
                title: "本日",
                rangeText: formatOffTaskDateRange(start: today.workday, endExclusive: Calendar.current.date(byAdding: .day, value: 1, to: today.workday) ?? today.workday),
                summary: todayAggregate
            ),
            OffTaskDisplayPeriod(
                id: "week",
                title: "本周",
                rangeText: formatOffTaskDateRange(start: week.start, endExclusive: week.endExclusive),
                summary: weekSummary
            ),
            OffTaskDisplayPeriod(
                id: "settlement",
                title: offTaskSettlementPeriodTitle(config),
                rangeText: formatOffTaskDateRange(start: settlement.start, endExclusive: settlement.endExclusive),
                summary: settlementSummary
            )
        ]
    }

    private func offTaskPeriodCard(_ period: OffTaskDisplayPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(period.title)
                    .font(.callout.weight(.semibold))
                Text(period.rangeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                offTaskPeriodMetric(title: "摸鱼薪资", value: formatMoney(period.summary.amount))
                offTaskPeriodMetric(title: "计薪时长", value: formatOffTaskDuration(period.summary.paidSeconds))

                HStack(spacing: 8) {
                    offTaskHistoryPill("\(period.summary.sessionCount)次")
                    offTaskHistoryPill("\(period.summary.dayCount)天")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private func offTaskPeriodMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    /// 历史记录按年、月、日逐级折叠，避免记录增多后单层列表过长。
    private func offTaskHistoryYears(from summaries: [OffTaskSessionSummary]) -> [OffTaskHistoryYear] {
        let grouped = Dictionary(grouping: summaries) { summary in
            offTaskYearKey(summary.workday)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let records = grouped[key] else {
                return nil
            }

            return OffTaskHistoryYear(
                id: key,
                title: formatOffTaskYear(records.first?.workday ?? Date()),
                monthCount: Set(records.map { offTaskMonthKey($0.workday) }).count,
                paidSeconds: records.reduce(0) { $0 + $1.paidSeconds },
                amount: records.reduce(0) { $0 + $1.amount },
                recordCount: records.count,
                dayCount: Set(records.map { offTaskDayKey($0.workday) }).count
            )
        }
    }

    private func offTaskHistoryMonths(from summaries: [OffTaskSessionSummary]) -> [OffTaskHistoryMonth] {
        let grouped = Dictionary(grouping: summaries) { summary in
            offTaskMonthKey(summary.workday)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let records = grouped[key] else {
                return nil
            }

            return OffTaskHistoryMonth(
                id: key,
                title: formatOffTaskMonth(records.first?.workday ?? Date()),
                dayCount: Set(records.map { offTaskDayKey($0.workday) }).count,
                paidSeconds: records.reduce(0) { $0 + $1.paidSeconds },
                amount: records.reduce(0) { $0 + $1.amount },
                recordCount: records.count
            )
        }
    }

    private func offTaskHistoryDays(from summaries: [OffTaskSessionSummary]) -> [OffTaskHistoryDay] {
        let grouped = Dictionary(grouping: summaries) { summary in
            offTaskDayKey(summary.workday)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let records = grouped[key]?.sorted(by: { lhs, rhs in
                (lhs.session.end ?? lhs.session.start) > (rhs.session.end ?? rhs.session.start)
            }) else {
                return nil
            }

            return OffTaskHistoryDay(
                id: key,
                title: formatOffTaskDay(records.first?.workday ?? Date()),
                summaries: records,
                paidSeconds: records.reduce(0) { $0 + $1.paidSeconds },
                amount: records.reduce(0) { $0 + $1.amount }
            )
        }
    }

    private func offTaskHistoryYearDisclosure(_ year: OffTaskHistoryYear, summaries: [OffTaskSessionSummary], config: SalaryConfig) -> some View {
        let isExpanded = expandedOffTaskHistoryYears.contains(year.id)

        return VStack(alignment: .leading, spacing: 0) {
            offTaskHistoryDisclosureButton(isExpanded: isExpanded) {
                toggleOffTaskHistoryExpansion(year.id, in: &expandedOffTaskHistoryYears)
            } label: {
                offTaskHistoryGroupLabel(
                    icon: "calendar",
                    title: year.title,
                    detail: "共计摸鱼\(year.monthCount)月 | \(year.dayCount)天",
                    recordCount: year.recordCount,
                    paidSeconds: year.paidSeconds,
                    amount: year.amount
                )
            }

            if isExpanded {
                let yearSummaries = summaries.filter { summary in
                    offTaskYearKey(summary.workday) == year.id
                }
                let months = offTaskHistoryMonths(from: yearSummaries)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(months) { month in
                        offTaskHistoryMonthDisclosure(month, summaries: yearSummaries, config: config)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.38), lineWidth: 1)
        )
    }

    private func offTaskHistoryMonthDisclosure(_ month: OffTaskHistoryMonth, summaries: [OffTaskSessionSummary], config: SalaryConfig) -> some View {
        let isExpanded = expandedOffTaskHistoryMonths.contains(month.id)

        return VStack(alignment: .leading, spacing: 0) {
            offTaskHistoryDisclosureButton(isExpanded: isExpanded) {
                toggleOffTaskHistoryExpansion(month.id, in: &expandedOffTaskHistoryMonths)
            } label: {
                offTaskHistoryGroupLabel(
                    icon: "calendar.circle",
                    title: month.title,
                    detail: "共计摸鱼\(month.dayCount)天",
                    recordCount: month.recordCount,
                    paidSeconds: month.paidSeconds,
                    amount: month.amount
                )
            }

            if isExpanded {
                let monthSummaries = summaries.filter { summary in
                    offTaskMonthKey(summary.workday) == month.id
                }
                let days = offTaskHistoryDays(from: monthSummaries)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(days) { day in
                        offTaskHistoryDayDisclosure(day, config: config)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
        )
    }

    private func offTaskHistoryDayDisclosure(_ day: OffTaskHistoryDay, config: SalaryConfig) -> some View {
        let isExpanded = expandedOffTaskHistoryDays.contains(day.id)

        return VStack(alignment: .leading, spacing: 0) {
            offTaskHistoryDisclosureButton(isExpanded: isExpanded) {
                toggleOffTaskHistoryExpansion(day.id, in: &expandedOffTaskHistoryDays)
            } label: {
                offTaskHistoryGroupLabel(
                    icon: "calendar.day.timeline.left",
                    title: day.title,
                    detail: nil,
                    recordCount: day.summaries.count,
                    paidSeconds: day.paidSeconds,
                    amount: day.amount
                )
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("起止时间")
                            .frame(width: 132, alignment: .leading)
                        Text("计薪时长")
                            .frame(width: 76, alignment: .leading)
                        Text("摸鱼薪资")
                            .frame(width: 86, alignment: .leading)
                        Text("状态")
                            .frame(width: 64, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                    ForEach(day.summaries) { summary in
                        OffTaskSessionRowView(summary: summary, config: config)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
        )
    }

    private func offTaskHistoryDisclosureButton<Label: View>(
        isExpanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                }
                .frame(width: 28, height: 28)

                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isExpanded ? "收起记录" : "展开记录")
    }

    private func toggleOffTaskHistoryExpansion(_ id: String, in expandedIDs: inout Set<String>) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    private func offTaskHistoryGroupLabel(
        icon: String,
        title: String,
        detail: String?,
        recordCount: Int,
        paidSeconds: TimeInterval,
        amount: Double
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 16)

            Text(title)
                .font(.callout.weight(.semibold))

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 10)

            offTaskHistoryPill("\(recordCount)次")
            offTaskHistoryPill(formatOffTaskDuration(paidSeconds))
            Text(formatMoney(amount))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundColor(.primary)
    }

    private func offTaskHistoryPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
    }

    /// 弹窗内容开关使用统一宽度，保证两列排列时不会因为文字长短错位。
    private func popoverContentToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func popoverContentGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            content()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
        )
    }

    /// 快捷键设置包含录制、启停、动作排序和注册错误提示。
    private var shortcutSettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用快捷键动作", isOn: $configManager.config.shortcutEnabled)
                    .onChange(of: configManager.config.shortcutEnabled) { _, _ in
                        GlobalShortcutMonitor.shared.restart()
                    }

                if configManager.config.shortcutEnabled {
                    HStack {
                        Text("快捷键")
                            .frame(width: 80, alignment: .leading)
                        ShortcutRecorderView(config: configManager.config)
                        Button("重置") {
                            configManager.config.shortcutModifiers = SalaryConfig.defaultShortcutModifiers
                            configManager.config.shortcutKeyCode = ShortcutKey.defaultKeyCode
                            GlobalShortcutMonitor.shared.restart()
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                    Text("点击右侧箭头调整动作顺序；每次触发快捷键会按顺序执行下一项。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    shortcutActionSection
                }

                Divider()

                offTaskShortcutSection

                if let registrationError = shortcutMonitor.registrationError {
                    Label(registrationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(12)
        } label: {
            Label("快捷键", systemImage: "keyboard")
                .font(.headline)
        }
    }

    private var offTaskShortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("启用摸鱼切换快捷键", isOn: Binding(
                get: { configManager.config.offTaskShortcutEnabled },
                set: { newValue in
                    configManager.config.offTaskShortcutEnabled = newValue
                    GlobalShortcutMonitor.shared.restart()
                }
            ))

            if configManager.config.offTaskShortcutEnabled {
                HStack {
                    Text("摸鱼切换")
                        .frame(width: 80, alignment: .leading)
                    ShortcutRecorderView(config: configManager.config, target: .offTaskToggle)
                    Button("重置") {
                        configManager.config.offTaskShortcutModifiers = SalaryConfig.defaultShortcutModifiers
                        configManager.config.offTaskShortcutKeyCode = SalaryConfig.defaultOffTaskShortcutKeyCode
                        GlobalShortcutMonitor.shared.restart()
                    }
                    .controlSize(.small)
                    Spacer()
                }

                Text("触发后会在当前工作窗口内开启摸鱼；已开启时触发会结束本次记录。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// 导入导出分成数据和配置两类；两者字段零交集，合并后覆盖除节假日缓存以外的可迁移内容。
    private var dataPortabilitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                dataTransferRow(
                    title: "数据",
                    detail: "包含薪资数据、补贴、计薪规则、工作时间和所有摸鱼、提前下班、加班记录；",
                    exportTitle: "导出数据",
                    importTitle: "导入数据",
                    exportAction: exportAllData,
                    importAction: importAllData
                )

                Divider()

                dataTransferRow(
                    title: "配置",
                    detail: "包含展示、快捷键、颜色、刷新、开机启动等偏好；",
                    exportTitle: "导出配置",
                    importTitle: "导入配置",
                    exportAction: exportConfig,
                    importAction: importConfig
                )

                if let dataTransferStatus {
                    Label(dataTransferStatus.message, systemImage: dataTransferStatus.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(dataTransferStatus.isError ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        } label: {
            Label("导入导出", systemImage: "externaldrive")
                .font(.headline)
        }
    }

    private func dataTransferRow(
        title: String,
        detail: String,
        exportTitle: String,
        importTitle: String,
        exportAction: @escaping () -> Void,
        importAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: exportAction) {
                    Label(exportTitle, systemImage: "square.and.arrow.up")
                }
                Button(action: importAction) {
                    Label(importTitle, systemImage: "square.and.arrow.down")
                }
            }
            .controlSize(.small)
        }
    }

    /// 应用行为包含开机启动、空闲降频和用户可调刷新间隔。
    private var appBehaviorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("开机自动启动", isOn: Binding(
                    get: { configManager.config.launchAtLogin },
                    set: { newValue in
                        configManager.config.launchAtLogin = newValue
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
                ))

                Toggle("空闲时低频刷新", isOn: Binding(
                    get: { configManager.config.usesLowFrequencyUpdatesWhenIdle },
                    set: { configManager.config.idleUsesLowFrequencyUpdates = $0 }
                ))

                HStack {
                    Text("刷新间隔")
                        .frame(width: 80, alignment: .leading)
                    TextField("", text: $refreshIntervalText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isRefreshIntervalFocused)
                        .onSubmit {
                            commitRefreshIntervalText()
                        }
                        .onChange(of: refreshIntervalText) { _, newValue in
                            sanitizeRefreshIntervalText(newValue)
                        }
                        .frame(width: 58)
                    Text("秒")
                        .foregroundColor(.secondary)
                    Stepper("", value: Binding(
                        get: { configManager.config.resolvedRefreshIntervalSeconds },
                        set: { newValue in
                            let clamped = InputValidation.clamped(newValue, in: SalaryConfig.refreshIntervalRange)
                            let stepped = InputValidation.rounded(clamped, step: 0.5)
                            configManager.config.refreshIntervalSeconds = stepped
                            if !isRefreshIntervalFocused {
                                refreshIntervalText = formatRefreshInterval(stepped)
                            }
                        }
                    ), in: SalaryConfig.refreshIntervalRange, step: 0.5)
                    .labelsHidden()
                    .frame(width: 44)
                    Spacer()
                }

                Text("范围 0.5-3600 秒。弹窗打开或状态栏实时薪资开启时按此间隔刷新；没有实时展示且开启空闲低频刷新时，实际间隔不会低于 60 秒。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        } label: {
            Label("应用行为", systemImage: "gearshape")
                .font(.headline)
        }
    }

    private func exportAllData() {
        do {
            guard let url = savePanelURL(
                title: "导出数据",
                defaultName: "SalaryDance-Data-\(dataTransferTimestamp()).json"
            ) else { return }

            let data = try SalaryDataTransfer.encodeDataDocument(
                config: configManager.config,
                offTaskSessions: offTaskTracker.sessions,
                clockOutSessions: workSessionTracker.clockOutSessions,
                overtimeSessions: workSessionTracker.overtimeSessions
            )
            try data.write(to: url, options: [.atomic])
            dataTransferStatus = .success("数据已导出：\(url.lastPathComponent)")
        } catch {
            reportDataTransferFailure("数据导出失败：\(error.localizedDescription)")
        }
    }

    private func importAllData() {
        do {
            guard let url = openPanelURL(title: "导入数据") else { return }
            let data = try Data(contentsOf: url)
            let document = try SalaryDataTransfer.decodeDataDocument(from: data)
            let normalizedSessions = try OffTaskTracker.normalizedImportedSessions(document.offTaskSessions)
            let normalizedClockOutSessions = try WorkSessionTracker.normalizedImportedClockOutSessions(document.clockOutSessions)
            let normalizedOvertimeSessions = try WorkSessionTracker.normalizedImportedOvertimeSessions(document.overtimeSessions)

            guard confirmImport(
                title: "导入数据？",
                message: "这会替换当前薪资数据、补贴、计薪规则、工作时间和所有摸鱼、提前下班、加班记录；展示、快捷键和应用偏好不会改变。"
            ) else { return }

            applyImportedSalaryData(document.salaryData)
            try offTaskTracker.replaceSessionsForImport(normalizedSessions)
            try workSessionTracker.replaceSessionsForImport(clockOut: normalizedClockOutSessions, overtime: normalizedOvertimeSessions)
            dataTransferStatus = .success("数据已导入：\(url.lastPathComponent)")
        } catch {
            reportDataTransferFailure("数据导入失败：\(error.localizedDescription)")
        }
    }

    private func exportConfig() {
        do {
            guard let url = savePanelURL(
                title: "导出配置",
                defaultName: "SalaryDance-Config-\(dataTransferTimestamp()).json"
            ) else { return }

            let data = try SalaryDataTransfer.encodeConfigDocument(
                config: configManager.config,
                settingsSidebarWidth: storedSidebarWidth
            )
            try data.write(to: url, options: [.atomic])
            dataTransferStatus = .success("配置已导出：\(url.lastPathComponent)")
        } catch {
            reportDataTransferFailure("配置导出失败：\(error.localizedDescription)")
        }
    }

    private func importConfig() {
        do {
            guard let url = openPanelURL(title: "导入配置") else { return }
            let data = try Data(contentsOf: url)
            let document = try SalaryDataTransfer.decodeConfigDocument(from: data)

            guard confirmImport(
                title: "导入配置？",
                message: "这会替换当前展示、快捷键、颜色、刷新、开机启动等偏好；薪资、补贴和行为记录不会改变。"
            ) else { return }

            applyImportedPreferenceConfig(document.preferences, sidebarWidth: document.settingsSidebarWidth)
            dataTransferStatus = .success("配置已导入：\(url.lastPathComponent)")
        } catch {
            reportDataTransferFailure("配置导入失败：\(error.localizedDescription)")
        }
    }

    private func applyImportedSalaryData(_ imported: SalaryDataSettings) {
        configManager.replaceSalaryDataForImport(imported)
        refreshInputTextsFromConfig()
        ensureSalaryCycleHolidayData()
    }

    private func applyImportedPreferenceConfig(_ imported: SalaryPreferenceSettings, sidebarWidth importedSidebarWidth: Double?) {
        configManager.replacePreferenceConfigForImport(imported)
        if let importedSidebarWidth {
            let clampedWidth = clampedSidebarWidth(importedSidebarWidth)
            storedSidebarWidth = clampedWidth
            sidebarWidth = clampedWidth
        }
        LaunchAtLoginManager.setEnabled(configManager.config.launchAtLogin)
        GlobalShortcutMonitor.shared.restart()
        refreshInputTextsFromConfig()
    }

    private func savePanelURL(title: String, defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func openPanelURL(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func confirmImport(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "导入")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func reportDataTransferFailure(_ message: String) {
        dataTransferStatus = .failure(message)
        NSSound.beep()
    }

    private func dataTransferTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// 快捷键动作使用点击排序，替代拖拽，避免拖拽重影和误操作。
    private var shortcutActionSection: some View {
        let sequence = configManager.config.resolvedShortcutActionSequence
        let disabledActions = ShortcutAction.allCases.filter { !sequence.contains($0) }

        return VStack(alignment: .leading, spacing: 8) {
            Text("快捷键动作顺序")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(sequence) { action in
                shortcutActionRow(action)
                    .transition(shortcutActionTransition)
            }

            if !disabledActions.isEmpty {
                Text("可添加动作")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                ForEach(disabledActions) { action in
                    shortcutActionRow(action)
                        .transition(shortcutActionTransition)
                }
            }
        }
        .animation(shortcutActionAnimation, value: sequence)
        .animation(shortcutActionAnimation, value: disabledActions)
    }

    /// 添加、删除、上移、下移共用一套短弹簧动画，动作足够轻但不生硬。
    private var shortcutActionAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)
    }

    /// 动作出现和移除使用不同方向，帮助用户理解列表发生了什么变化。
    private var shortcutActionTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity
                .combined(with: .move(edge: .trailing))
                .combined(with: .scale(scale: 0.98, anchor: .center))
        )
    }

    /// 单个快捷键动作行，既可作为已启用动作排序，也可作为待添加动作入口。
    private func shortcutActionRow(_ action: ShortcutAction) -> some View {
        let sequence = configManager.config.resolvedShortcutActionSequence
        let index = sequence.firstIndex(of: action)
        let isEnabled = index != nil

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { configManager.config.resolvedShortcutActionSequence.contains(action) },
                set: { isOn in
                    setShortcutAction(action, enabled: isOn)
                }
            ))
            .labelsHidden()
            .disabled(isEnabled && sequence.count == 1)

            Image(systemName: action.iconName)
                .foregroundColor(isEnabled ? .accentColor : .secondary)
                .frame(width: 18)

            Text(action.title)
                .foregroundColor(isEnabled ? .primary : .secondary)

            Spacer()

            if let index {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 22)

                HStack(spacing: 2) {
                    Button {
                        moveShortcutAction(action, offset: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("上移")

                    Button {
                        moveShortcutAction(action, offset: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == sequence.count - 1)
                    .help("下移")
                }
            }
        }
        .controlSize(.small)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isEnabled ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isEnabled ? Color.accentColor.opacity(0.12) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(shortcutActionAnimation, value: isEnabled)
        .animation(shortcutActionAnimation, value: index)
    }

    /// 至少保留一个快捷键动作，防止用户开启快捷键后没有任何可执行行为。
    private func setShortcutAction(_ action: ShortcutAction, enabled: Bool) {
        var sequence = configManager.config.resolvedShortcutActionSequence
        if enabled {
            guard !sequence.contains(action) else { return }
            sequence.append(action)
        } else {
            guard sequence.count > 1 else { return }
            sequence.removeAll { $0 == action }
        }
        withAnimation(shortcutActionAnimation) {
            configManager.config.shortcutActionSequence = sequence
        }
    }

    /// 用上下按钮改变动作顺序，offset 只允许相邻移动。
    private func moveShortcutAction(_ action: ShortcutAction, offset: Int) {
        var sequence = configManager.config.resolvedShortcutActionSequence
        guard let sourceIndex = sequence.firstIndex(of: action) else {
            return
        }
        let targetIndex = sourceIndex + offset
        guard sequence.indices.contains(targetIndex) else {
            return
        }

        let moving = sequence.remove(at: sourceIndex)
        sequence.insert(moving, at: targetIndex)

        withAnimation(shortcutActionAnimation) {
            configManager.config.shortcutActionSequence = sequence
        }
    }

    private func specialRule(for id: UUID) -> SpecialWorkdayRule? {
        configManager.config.specialWorkdayRules.first { $0.id == id }
    }

    private func addSpecialWorkdayRule() {
        var rule = SpecialWorkdayRule()
        rule.name = "特殊工作日 \(configManager.config.specialWorkdayRules.count + 1)"

        var config = configManager.config
        config.specialWorkdayRules.append(rule)
        configManager.config = config
        ensureSalaryCycleHolidayData()
    }

    private func removeSpecialWorkdayRule(_ id: UUID) {
        var config = configManager.config
        config.specialWorkdayRules.removeAll { $0.id == id }
        configManager.config = config
        ensureSalaryCycleHolidayData()
    }

    private func moveSpecialWorkdayRule(_ id: UUID, offset: Int) {
        var config = configManager.config
        guard let sourceIndex = config.specialWorkdayRules.firstIndex(where: { $0.id == id }) else {
            return
        }
        let targetIndex = sourceIndex + offset
        guard config.specialWorkdayRules.indices.contains(targetIndex) else {
            return
        }

        let moving = config.specialWorkdayRules.remove(at: sourceIndex)
        config.specialWorkdayRules.insert(moving, at: targetIndex)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)) {
            configManager.config = config
        }
    }

    private func updateSpecialWorkdayRule(_ id: UUID, update: (inout SpecialWorkdayRule) -> Void) {
        var config = configManager.config
        guard let index = config.specialWorkdayRules.firstIndex(where: { $0.id == id }) else { return }

        update(&config.specialWorkdayRules[index])
        config.specialWorkdayRules[index].normalize()
        configManager.config = config
        ensureSalaryCycleHolidayData()
    }

    private func specialRuleEnabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { specialRule(for: id)?.enabled ?? true },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.enabled = newValue
                }
            }
        )
    }

    private func specialRuleNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { specialRule(for: id)?.name ?? "" },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.name = String(newValue.prefix(24))
                }
            }
        )
    }

    private func specialRuleKindBinding(for id: UUID) -> Binding<SpecialWorkdayRuleKind> {
        Binding(
            get: { specialRule(for: id)?.kind ?? .dayBeforeRestDay },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.kind = newValue
                }
            }
        )
    }

    private func specialRuleWeekdayBinding(for id: UUID, day: Int) -> Binding<Bool> {
        Binding(
            get: { specialRule(for: id)?.weekdays.contains(day) ?? false },
            set: { isOn in
                updateSpecialWorkdayRule(id) { rule in
                    if isOn {
                        rule.weekdays.insert(day)
                    } else if rule.weekdays.count > 1 {
                        rule.weekdays.remove(day)
                    }
                }
            }
        )
    }

    private func specialRuleIntervalWeeksBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { specialRule(for: id)?.intervalWeeks ?? 2 },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.intervalWeeks = newValue
                }
            }
        )
    }

    private func specialRuleAnchorDateBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { specialRule(for: id)?.anchorDate ?? Date() },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.anchorDate = Calendar.current.startOfDay(for: newValue)
                }
            }
        )
    }

    private func specialRuleExactDateBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { specialRule(for: id)?.exactDate ?? Date() },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.exactDate = Calendar.current.startOfDay(for: newValue)
                }
            }
        )
    }

    private func specialRuleWorkTimeBinding(for id: UUID, _ keyPath: WritableKeyPath<TimeRange, Int>) -> Binding<Int> {
        Binding(
            get: { specialRule(for: id)?.workTime[keyPath: keyPath] ?? 0 },
            set: { newValue in
                updateSpecialWorkdayRule(id) { rule in
                    rule.workTime[keyPath: keyPath] = newValue
                }
            }
        )
    }

    /// 时间输入统一使用支持键盘输入的组件，避免多个设置项行为不一致。
    private func timePicker(hour: Binding<Int>, minute: Binding<Int>) -> some View {
        TimeInputView(hour: hour, minute: minute)
    }

    private var subsidyExplanation: String {
        let config = configManager.config
        let base = """
        按日补贴直接加到日薪，会进入今日收入、剩余收入和秒/分/时薪。
        按月补贴的月度原值会计入月薪和年薪；只有选择“平摊到每天”时，才会按分摊结果进入日薪和实时收入。
        """

        guard !config.subsidies.isEmpty else {
            return base
        }

        return base + "\n关闭的补贴不会参与任何计算。当前已开启日薪补贴合计 \(formatMoney(config.effectiveDailySubsidyTotal))，已开启按月补贴合计 \(formatMoney(config.monthlySubsidyTotal))。"
    }

    private func subsidyEnabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { subsidy(for: id)?.enabled ?? true },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.enabled = newValue
                }
            }
        )
    }

    private func subsidyNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { subsidy(for: id)?.name ?? "" },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.name = String(newValue.prefix(24))
                }
            }
        )
    }

    private func subsidyTypeBinding(for id: UUID) -> Binding<SalarySubsidyType> {
        Binding(
            get: { subsidy(for: id)?.type ?? .daily },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.type = newValue
                }
            }
        )
    }

    private func subsidyAmountBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { subsidy(for: id)?.amount ?? 0 },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.amount = normalizedPositiveAmount(newValue)
                }
            }
        )
    }

    private func monthlySubsidyApplicationBinding(for id: UUID) -> Binding<MonthlySubsidyApplicationMode> {
        Binding(
            get: { subsidy(for: id)?.monthlyApplicationMode ?? .spreadToDailySalary },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.monthlyApplicationMode = newValue
                }
            }
        )
    }

    private func monthlySubsidyProrationBinding(for id: UUID) -> Binding<MonthlySubsidyProrationMode> {
        Binding(
            get: { subsidy(for: id)?.monthlyProrationMode ?? .fixedDays },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.monthlyProrationMode = newValue
                }
            }
        )
    }

    private func subsidyFixedDaysBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { subsidy(for: id)?.fixedProrationDays ?? SalarySubsidy.defaultFixedProrationDays },
            set: { newValue in
                updateSubsidy(id) { subsidy in
                    subsidy.fixedProrationDays = InputValidation.clamped(newValue, in: SalaryConfig.monthlyWorkdaysRange)
                }
            }
        )
    }

    private func subsidy(for id: UUID) -> SalarySubsidy? {
        configManager.config.subsidies.first { $0.id == id }
    }

    private func addSubsidy(type: SalarySubsidyType) {
        var subsidy = SalarySubsidy()
        subsidy.type = type
        subsidy.name = "补贴名"

        var config = configManager.config
        config.subsidies.append(subsidy)
        configManager.config = config
        ensureSalaryCycleHolidayData()
    }

    private func removeSubsidy(_ id: UUID) {
        var config = configManager.config
        config.subsidies.removeAll { $0.id == id }
        configManager.config = config
        ensureSalaryCycleHolidayData()
    }

    private func updateSubsidy(_ id: UUID, update: (inout SalarySubsidy) -> Void) {
        var config = configManager.config
        guard let index = config.subsidies.firstIndex(where: { $0.id == id }) else { return }

        update(&config.subsidies[index])
        config.subsidies[index].normalize(fixedDaysRange: SalaryConfig.monthlyWorkdaysRange)
        configManager.config = config
        ensureSalaryCycleHolidayData()
    }

    private func normalizedPositiveAmount(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private func subsidyImpactSummary(for subsidy: SalarySubsidy) -> String {
        guard subsidy.enabled else {
            return "已关闭"
        }

        switch subsidy.type {
        case .daily:
            return "日薪 +\(formatMoney(subsidy.amount))"
        case .monthly:
            if subsidy.monthlyApplicationMode == .addToMonthlySalary {
                return "月薪 +\(formatMoney(subsidy.amount))"
            }
            let dailyAmount = subsidyDailyEquivalent(for: subsidy)
            return "日薪 +\(formatMoney(dailyAmount)) / 月薪 +\(formatMoney(subsidy.amount))"
        }
    }

    private func monthlySubsidyProrationDescription(for subsidy: SalarySubsidy) -> String {
        guard subsidy.enabled else {
            return "已关闭，不参与任何薪资计算。"
        }

        let config = configManager.config
        let period = config.currentSalaryCyclePeriod
        let divisor = config.monthlySubsidyProrationDays(for: subsidy)
        let dailyAmount = subsidyDailyEquivalent(for: subsidy)
        let divisorText = formatWorkdayCount(divisor)
        let prefix: String

        switch subsidy.monthlyProrationMode {
        case .salaryCycleTotalDays:
            prefix = "当前周期 \(formatSalaryCyclePeriod(period)) 共 \(period.totalDays) 天"
        case .fixedDays:
            prefix = "固定按 \(formatWorkdayCount(subsidy.fixedProrationDays)) 天"
        case .salaryCycleWorkdays:
            prefix = "当前周期 \(formatSalaryCyclePeriod(period)) 计薪 \(period.paidWorkdays) 天"
        }

        return "\(prefix)平摊，实际分母 \(divisorText) 天，折合日补贴 \(formatMoney(dailyAmount))；月薪汇总仍按每月 \(formatMoney(subsidy.amount)) 计入。"
    }

    private func subsidyDailyEquivalent(for subsidy: SalarySubsidy) -> Double {
        guard subsidy.enabled else { return 0 }

        switch subsidy.type {
        case .daily:
            return subsidy.amount
        case .monthly:
            guard subsidy.monthlyApplicationMode == .spreadToDailySalary else { return 0 }
            let divisor = configManager.config.monthlySubsidyProrationDays(for: subsidy)
            guard divisor > 0 else { return 0 }
            return subsidy.amount / divisor
        }
    }

    private func settingsColorControl(title: String, color: NSColor, hex: String, onChange: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            SettingsColorSwatchButton(title: title, color: color, hex: hex, onChange: onChange)
            Text(hex)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
    }

    private func settingsSegmentedControl<Option: Hashable>(
        options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 1)
        )
    }

    /// 日历页仍使用系统 ColorPicker；展示页改用共享色板，避免切页时初始化多个原生色板控件。
    private var holidayPastColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.holidayPastNSColor)
            },
            set: { newColor in
                configManager.config.holidayPastColorHex = SalaryColor.hex(from: NSColor(newColor))
            }
        )
    }

    private var holidayFutureColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.holidayFutureNSColor)
            },
            set: { newColor in
                configManager.config.holidayFutureColorHex = SalaryColor.hex(from: NSColor(newColor))
            }
        )
    }

    /// 薪资设置里的六项换算展示，布局为两行三列，方便横向比较。
    private func salaryMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Color(nsColor: configManager.config.popoverSalaryNSColor))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: configManager.config.popoverSalaryNSColor).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: configManager.config.popoverSalaryNSColor).opacity(0.18), lineWidth: 1)
        )
    }

    private func offTaskStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private func workSessionStatCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func workSessionStatusText(_ summary: WorkSessionDailySummary) -> String {
        if workSessionTracker.activeOvertimeSession(config: configManager.config) != nil {
            return "加班中"
        }
        if workSessionTracker.clockOutSession(for: summary.workday) != nil {
            return "已提前下班"
        }
        return "当前未记录"
    }

    private func workSessionStatusDetail(
        _ summary: WorkSessionDailySummary,
        clockOutAvailability: ClockOutAvailability,
        overtimeAvailability: OvertimeAvailability
    ) -> String {
        if let overtime = workSessionTracker.activeOvertimeSession(config: configManager.config) {
            return "加班到 \(formatOffTaskClock(overtime.end))，今日加班亏损 \(formatMoney(summary.overtimeAmount))"
        }
        if let clockOut = workSessionTracker.clockOutSession(for: summary.workday) {
            return "提前 \(formatOffTaskClock(clockOut.start)) 下班，今日提前下班进账 \(formatMoney(summary.clockOutAmount))"
        }
        if clockOutAvailability.canClockOut {
            return clockOutAvailability.shortMessage
        }
        if overtimeAvailability.canStart {
            return overtimeAvailability.shortMessage
        }
        return summary.hasRecords ? "今日已记录提前下班/加班数据" : "今日暂无提前下班/加班记录"
    }

    private func offTaskStatusText(_ summary: OffTaskDailySummary) -> String {
        if offTaskTracker.isActive {
            return "摸鱼中"
        }
        if summary.isWorkFinished {
            return "今日已结算"
        }
        return "当前未开启"
    }

    private func offTaskStatusDetail(_ summary: OffTaskDailySummary) -> String {
        let summaryText = offTaskDailySummaryText(summary)

        if offTaskTracker.isActive, let start = offTaskTracker.activeSessionStart {
            return "从 \(formatOffTaskClock(start)) 开始，\(summaryText)"
        }

        let availability = offTaskTracker.startAvailability(config: configManager.config)
        if !summary.isWorkFinished && !availability.canStart && !summary.hasRecords {
            return "\(availability.shortMessage)，\(summaryText)"
        }
        return summaryText
    }

    private func offTaskDailySummaryText(_ summary: OffTaskDailySummary) -> String {
        guard summary.hasRecords else {
            return "今日摸鱼：暂无摸鱼记录"
        }
        return "今日摸鱼：\(formatOffTaskDuration(summary.paidSeconds))，\(formatMoney(summary.amount))"
    }

    private func offTaskToggleHelp(isActive: Bool, availability: OffTaskStartAvailability) -> String {
        isActive ? "结束当前摸鱼记录" : availability.helpMessage
    }

    private func formatOffTaskPercent(_ summary: OffTaskDailySummary) -> String {
        let dailySalary = configManager.config.effectiveDailySalary(on: summary.workday)
        guard dailySalary > 0 else { return "0.0%" }
        return String(format: "%.1f%%", summary.amount / dailySalary * 100)
    }

    private func formatOffTaskDuration(_ seconds: TimeInterval) -> String {
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

    private func formatOffTaskClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatWorkSessionClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatOffTaskDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 E"
        return formatter.string(from: date)
    }

    private func formatOffTaskYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年"
        return formatter.string(from: date)
    }

    private func formatOffTaskMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月"
        return formatter.string(from: date)
    }

    private func formatOffTaskDateRange(start: Date, endExclusive: Date) -> String {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: endExclusive)
        let endInclusive = calendar.date(byAdding: .day, value: -1, to: normalizedEnd) ?? normalizedStart

        if calendar.isDate(normalizedStart, inSameDayAs: endInclusive) {
            return formatOffTaskRangeDate(normalizedStart)
        }
        return "\(formatOffTaskRangeDate(normalizedStart)) - \(formatOffTaskRangeDate(endInclusive))"
    }

    private func formatOffTaskRangeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
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

    private func offTaskYearKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func offTaskMonthKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func offTaskDayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 设置页金额格式和弹窗共用小数位配置，但可按场景决定是否显示 ¥。
    private func formatMoney(_ value: Double, showCurrencySymbol: Bool = true) -> String {
        let amount = String(format: "%.\(configManager.config.displayDecimalPlaces)f", value)
        return showCurrencySymbol ? "¥\(amount)" : amount
    }

    /// 薪资换算说明必须随月薪折算和补贴规则变化，避免用户误以为所有金额都只按日薪反推。
    private var salaryConversionDescription: String {
        let config = configManager.config
        let period = config.currentSalaryCyclePeriod
        let periodDescription = "\(config.resolvedSalaryCycleMode.title)：\(formatSalaryCyclePeriod(period))"
        let monthlyDescription: String
        switch config.resolvedMonthlySalaryCalculationMode {
        case .fixedAverage:
            monthlyDescription = "基础月薪 = 基础日薪 × 固定 \(formatWorkdayCount(config.resolvedFixedMonthlyWorkdays)) 天"
        case .salaryCycleWorkdays:
            monthlyDescription = "基础月薪 = 基础日薪 × 当前计薪周期计薪 \(period.paidWorkdays) 天（\(formatSalaryCyclePeriod(period))）"
        }

        return """
        换算说明：
        当前计薪周期 = \(periodDescription)。
        基础薪资先统一折算为基础日薪。
        展示日薪 = 基础日薪 + 按日补贴 + 已平摊到每天的按月补贴。
        \(monthlyDescription)；展示月薪 = 基础月薪 + 按日补贴 × 月薪折算天数 + 按月补贴原值。
        展示年薪 =（基础日薪 + 按日补贴）× 250 + 按月补贴原值 × 12。
        秒薪、分薪和时薪按展示日薪与当前计薪时长 \(formatDuration(config.paidWorkMinutes)) 计算。
        """
    }

    private func formatWorkdayCount(_ value: Double) -> String {
        InputValidation.formattedDecimal(value, maxFractionDigits: 2)
    }

    private func specialWorkdayRuleSummary(_ rule: SpecialWorkdayRule) -> String {
        guard rule.enabled else {
            return "已关闭，不参与特殊工作时间匹配。"
        }
        return "\(specialWorkdayConditionSummary(rule))；命中后工作时间 \(rule.workTime.startString)-\(rule.workTime.endString)。"
    }

    private func specialWorkdayConditionSummary(_ rule: SpecialWorkdayRule) -> String {
        switch rule.kind {
        case .dayBeforeRestDay:
            return "节假日和周末的前一天"
        case .weekly:
            return "每周 \(weekdayListText(rule.weekdays))"
        case .intervalWeeks:
            return "从 \(formatShortDate(rule.anchorDate)) 所在周起，每 \(rule.intervalWeeks) 周的 \(weekdayListText(rule.weekdays))"
        case .exactDate:
            return formatShortDate(rule.exactDate)
        }
    }

    private func weekdayListText(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map(weekdayTitle).joined(separator: "、")
    }

    private func weekdayTitle(_ day: Int) -> String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard (1...7).contains(day) else { return "周五" }
        return names[day - 1]
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: date)
    }

    private func formatSalaryCyclePeriod(_ period: SalaryCyclePeriod) -> String {
        let calendar = Calendar.current
        let startYear = calendar.component(.year, from: period.start)
        let endYear = calendar.component(.year, from: period.endInclusive)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = startYear == endYear ? "MM月dd日" : "yyyy年MM月dd日"
        let start = formatter.string(from: period.start)
        let end = formatter.string(from: period.endInclusive)
        return "\(start)-\(end)"
    }

    /// 周期内工作天数依赖节假日和调休日，切到该模式时主动加载涉及年份。
    private func ensureSalaryCycleHolidayData() {
        let config = configManager.config
        let subsidyUsesCycleWorkdays = config.subsidies.contains { subsidy in
            subsidy.enabled
                && subsidy.type == .monthly
                && subsidy.monthlyApplicationMode == .spreadToDailySalary
                && subsidy.monthlyProrationMode == .salaryCycleWorkdays
        }
        let specialRulesNeedHolidayData = config.specialWorkdayRules.contains { rule in
            rule.enabled && rule.kind == .dayBeforeRestDay
        }
        guard config.workDayRule == .weekdaysOnly,
              config.resolvedMonthlySalaryCalculationMode == .salaryCycleWorkdays || subsidyUsesCycleWorkdays || specialRulesNeedHolidayData else {
            return
        }
        holidayManager.ensureYearsLoaded(config.currentSalaryCycleYears)
    }

    /// 固定天数输入过程中只在合法范围内即时保存，最终失焦时再兜底夹到 1...31。
    private func sanitizeFixedMonthlyWorkdaysText(_ newValue: String) {
        let sanitized = InputValidation.decimalText(newValue, maxIntegerDigits: 2, maxFractionDigits: 2)
        if sanitized != newValue {
            fixedMonthlyWorkdaysText = sanitized
            return
        }

        guard let value = InputValidation.decimalValue(from: sanitized),
              SalaryConfig.monthlyWorkdaysRange.contains(value) else {
            return
        }
        setFixedMonthlyWorkdays(value, syncText: false)
    }

    /// 固定天数提交时允许用户临时输入超范围值，并自动改为最大/最小值。
    private func commitFixedMonthlyWorkdaysText() {
        let sanitized = InputValidation.decimalText(fixedMonthlyWorkdaysText, maxIntegerDigits: 2, maxFractionDigits: 2)
        let fallback = configManager.config.resolvedFixedMonthlyWorkdays
        let rawValue = InputValidation.decimalValue(from: sanitized) ?? fallback
        setFixedMonthlyWorkdays(InputValidation.clamped(rawValue, in: SalaryConfig.monthlyWorkdaysRange))
    }

    private func setFixedMonthlyWorkdays(_ value: Double, syncText: Bool = true) {
        let normalized = InputValidation.clamped(value, in: SalaryConfig.monthlyWorkdaysRange)
        configManager.config.fixedMonthlyWorkdays = normalized
        if syncText {
            fixedMonthlyWorkdaysText = formatWorkdayCount(normalized)
        }
    }

    /// 计薪周期起始日只允许 1...31；2 月缺失日期由计算层折到当月最后一天。
    private func sanitizeSalaryCycleStartDayText(_ newValue: String) {
        let sanitized = InputValidation.integerText(newValue, maxDigits: 2)
        if sanitized != newValue {
            salaryCycleStartDayText = sanitized
            return
        }

        guard let value = Int(sanitized), (1...31).contains(value) else {
            return
        }
        setSalaryCycleStartDay(value, syncText: false)
    }

    private func commitSalaryCycleStartDayText() {
        let sanitized = InputValidation.integerText(salaryCycleStartDayText, maxDigits: 2)
        let fallback = configManager.config.resolvedMonthlySalaryCycleStartDay
        let rawValue = Int(sanitized) ?? fallback
        setSalaryCycleStartDay(min(31, max(1, rawValue)))
    }

    private func setSalaryCycleStartDay(_ value: Int, syncText: Bool = true) {
        let normalized = min(31, max(1, value))
        configManager.config.monthlySalaryCycleStartDay = normalized
        if syncText {
            salaryCycleStartDayText = "\(normalized)"
        }
        ensureSalaryCycleHolidayData()
    }

    /// 刷新间隔按 0.5 秒步进展示，整数不保留小数。
    private func formatRefreshInterval(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    /// 刷新间隔提交时夹到 0.5...3600 秒，避免输入超范围值被错误截断。
    private func commitRefreshIntervalText() {
        let sanitized = InputValidation.decimalText(refreshIntervalText, maxIntegerDigits: 4, maxFractionDigits: 1)
        let parsed = InputValidation.decimalValue(from: sanitized)
        let fallback = configManager.config.resolvedRefreshIntervalSeconds
        let rawValue = parsed ?? fallback
        let clamped = InputValidation.clamped(rawValue, in: SalaryConfig.refreshIntervalRange)
        let stepped = InputValidation.rounded(clamped, step: 0.5)
        configManager.config.refreshIntervalSeconds = stepped
        refreshIntervalText = formatRefreshInterval(stepped)
    }

    private func sanitizeRefreshIntervalText(_ newValue: String) {
        let sanitized = InputValidation.decimalText(newValue, maxIntegerDigits: 4, maxFractionDigits: 1)
        if sanitized != newValue {
            refreshIntervalText = sanitized
        }
    }

    /// 薪资金额输入过程中先做格式清理，再保存合法数字，空值视为 0。
    private func sanitizeAndSaveSalaryAmount(_ newValue: String) {
        let sanitized = InputValidation.decimalText(newValue, maxIntegerDigits: 12, maxFractionDigits: 2)
        if sanitized != newValue {
            tempSalaryAmount = sanitized
            return
        }
        saveSalaryAmount(from: sanitized)
    }

    private func commitSalaryAmountText() {
        let sanitized = InputValidation.decimalText(tempSalaryAmount, maxIntegerDigits: 12, maxFractionDigits: 2)
        saveSalaryAmount(from: sanitized)
        tempSalaryAmount = configManager.config.salaryAmount > 0
            ? InputValidation.formattedDecimal(configManager.config.salaryAmount, maxFractionDigits: 2)
            : ""
    }

    private func saveSalaryAmount(from text: String) {
        guard let value = InputValidation.decimalValue(from: text) else {
            if text.isEmpty {
                configManager.config.salaryAmount = 0
            }
            return
        }

        configManager.config.salaryAmount = max(0, value)
    }

    private func formatDuration(_ minutes: Int) -> String {
        "\(minutes / 60)小时\(minutes % 60)分钟"
    }

    private func formatHolidayDate(_ value: String) -> String {
        guard let date = parseHolidayDate(value) else { return value }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "zh_CN")
        outputFormatter.dateFormat = "MM月dd日 E"
        return outputFormatter.string(from: date)
    }

    /// 日期状态只按今天分界，不受节假日本身名称影响。
    private func holidayDateState(for value: String) -> (label: String, color: Color) {
        if isPastHolidayDate(value) {
            return ("已过", Color(nsColor: configManager.config.holidayPastNSColor))
        }
        return ("未过", Color(nsColor: configManager.config.holidayFutureNSColor))
    }

    private func isPastHolidayDate(_ value: String) -> Bool {
        guard let date = parseHolidayDate(value) else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }

    private func parseHolidayDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func formatGridInterval(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)小时" : "\(minutes)分钟"
    }

}
