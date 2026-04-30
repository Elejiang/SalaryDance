import SwiftUI

/// 设置页左侧导航分类。分类数量较多时保持这里的 title/subtitle/icon 同步，避免侧边栏和内容区语义漂移。
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case salary
    case time
    case display
    case shortcut
    case calendar
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salary: return "薪资"
        case .time: return "时间"
        case .display: return "展示"
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
        case .shortcut: return "快捷键录制和动作顺序"
        case .calendar: return "计薪规则、节假日和调休日"
        case .app: return "启动和刷新策略"
        }
    }

    var iconName: String {
        switch self {
        case .salary: return "yensign.circle"
        case .time: return "clock"
        case .display: return "menubar.rectangle"
        case .shortcut: return "keyboard"
        case .calendar: return "calendar"
        case .app: return "gearshape"
        }
    }
}

/// 补贴启停使用滑动开关表达“参与/不参与计算”，绿色开启、红色关闭，便于做金额对比。
private struct SubsidyStatusToggleStyle: ToggleStyle {
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
        .accessibilityLabel(Text(configuration.isOn ? "补贴已开启" : "补贴已关闭"))
        .help(configuration.isOn ? "关闭补贴" : "开启补贴")
    }
}

/// 设置窗口主体。当前采用“左侧分类 + 右侧预加载页面”的结构，减少栏目切换时的重新创建成本。
struct SettingsView: View {
    @ObservedObject var configManager = SalaryConfigManager.shared
    @ObservedObject var holidayManager = ChineseHolidays.shared
    @ObservedObject var shortcutMonitor = GlobalShortcutMonitor.shared
    @State private var tempSalaryAmount: String = ""
    @State private var refreshIntervalText: String = ""
    @State private var fixedMonthlyWorkdaysText: String = ""
    @State private var salaryCycleStartDayText: String = ""
    @State private var selectedCategory: SettingsCategory = .salary
    @FocusState private var isSalaryAmountFocused: Bool
    @FocusState private var isRefreshIntervalFocused: Bool
    @FocusState private var isFixedMonthlyWorkdaysFocused: Bool
    @FocusState private var isSalaryCycleStartDayFocused: Bool
    @AppStorage("settings_sidebar_width") private var storedSidebarWidth: Double = 218
    @State private var sidebarWidth: Double = 218
    private let sidebarWidthRange: ClosedRange<Double> = 168...310

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
            tempSalaryAmount = configManager.config.salaryAmount > 0
                ? InputValidation.formattedDecimal(configManager.config.salaryAmount, maxFractionDigits: 2)
                : ""
            refreshIntervalText = formatRefreshInterval(configManager.config.resolvedRefreshIntervalSeconds)
            fixedMonthlyWorkdaysText = formatWorkdayCount(configManager.config.resolvedFixedMonthlyWorkdays)
            salaryCycleStartDayText = "\(configManager.config.resolvedMonthlySalaryCycleStartDay)"
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

    /// 所有页面常驻在 ZStack 中，只切换透明度和命中区域；展示页这种重页面因此不会每次点击重新构建。
    @ViewBuilder
    private var settingsMainContent: some View {
        // 设置窗口打开时预加载全部栏目，切换栏目只改可见性，减少“展示”页首次点击延迟。
        ZStack(alignment: .topLeading) {
            ForEach(SettingsCategory.allCases) { category in
                settingsPage(category)
                    .opacity(selectedCategory == category ? 1 : 0)
                    .allowsHitTesting(selectedCategory == category)
                    .accessibilityHidden(selectedCategory != category)
                    .zIndex(selectedCategory == category ? 1 : 0)
            }
        }
    }

    /// 单个设置页统一放进 ScrollView，右侧预览和设置项可以一起滚动对照。
    @ViewBuilder
    private func settingsPage(_ category: SettingsCategory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsHeader(for: category)
                settingsContent(for: category)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        case .shortcut:
            shortcutSettingsSection
        case .calendar:
            workDaySection
        case .app:
            appBehaviorSection
        }
    }

    /// 薪资设置包含基础薪资、补贴、月薪折算方式和六个薪资换算结果。
    private var salarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("薪资类型")
                        .frame(width: 80, alignment: .leading)
                    Picker("", selection: $configManager.config.salaryType) {
                        ForEach(SalaryType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .focusable(false)
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

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                        salaryMetricCard(title: "秒薪", value: formatMoney(configManager.config.salaryPerSecond))
                        salaryMetricCard(title: "分薪", value: formatMoney(configManager.config.salaryPerMinute))
                        salaryMetricCard(title: "时薪", value: formatMoney(configManager.config.salaryPerHour))
                        salaryMetricCard(title: "日薪", value: formatMoney(configManager.config.dailySalary))
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

    /// 月薪折算支持固定指定天数和按当前薪资周期动态计薪日两种模式。
    private var monthlySalaryCalculationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("月薪折算")
                    .frame(width: 80, alignment: .leading)
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

            if configManager.config.resolvedMonthlySalaryCalculationMode == .salaryCycleWorkdays {
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

                Text("固定模式始终用这个天数做月薪和日薪换算，不随自然月或薪资周期变化。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if configManager.config.resolvedMonthlySalaryCalculationMode == .salaryCycleWorkdays {
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

                    Text("每月 \(configManager.config.resolvedMonthlySalaryCycleStartDay) 日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                    Spacer()
                }

                let period = configManager.config.currentSalaryCyclePeriod
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.secondary)
                    Text("当前周期 \(formatSalaryCyclePeriod(period))，计薪 \(period.paidWorkdays) 天")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Text("计薪天数按“日历”里的计薪规则统计；当月没有对应日期时，按当月最后一天作为周期起点。")
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
        VStack(alignment: .leading, spacing: 10) {
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
                VStack(spacing: 8) {
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

                Picker("", selection: monthlySubsidyApplicationBinding(for: subsidy.id)) {
                    ForEach(MonthlySubsidyApplicationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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
                    .disabled(!configManager.config.displaysEarningsInStatusBar)

                    Toggle("显示 ¥ 符号", isOn: Binding(
                        get: { configManager.config.statusBarDisplaysCurrencySymbol },
                        set: { configManager.config.statusBarShowsCurrencySymbol = $0 }
                    ))
                    .disabled(!configManager.config.displaysEarningsInStatusBar)

                    HStack {
                        Text("数字动画")
                            .frame(width: 70, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { configManager.config.resolvedStatusBarSalaryAnimationStyle },
                            set: { setConfigValue(\.statusBarSalaryAnimationStyle, to: $0) }
                        )) {
                            ForEach(StatusBarSalaryAnimationStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }
                    .disabled(!configManager.config.displaysEarningsInStatusBar)

                    HStack {
                        Text("金额颜色")
                            .frame(width: 70, alignment: .leading)
                        ColorPicker("", selection: statusBarSalaryColorBinding, supportsOpacity: false)
                            .labelsHidden()
                        Text(configManager.config.resolvedStatusBarSalaryColorHex)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
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
                        Picker("", selection: Binding(
                            get: { configManager.config.displayDecimalPlaces },
                            set: { setConfigValue(\.moneyDecimalPlaces, to: $0) }
                        )) {
                            ForEach(0...3, id: \.self) { digits in
                                Text("\(digits)").tag(digits)
                            }
                        }
                        .pickerStyle(.segmented)
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

                displayPreviewPanel
                    .frame(width: 300, alignment: .top)
            }
        }
    }

    /// 预览只模拟弹窗本体，不再额外画一条假的状态栏，减少认知干扰。
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

    /// 弹窗内容开关逐项独立控制，避免“全部展示/全部隐藏”的粗粒度体验。
    private var popoverDisplaySection: some View {
        GroupBox {
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

                    HStack(spacing: 10) {
                        popoverContentToggle("打工语录", isOn: Binding(
                            get: { configManager.config.popoverDisplaysQuote },
                            set: { configManager.config.popoverShowsQuote = $0 }
                        ))

                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Text("薪资颜色")
                        .frame(width: 80, alignment: .leading)
                    ColorPicker("", selection: popoverSalaryColorBinding, supportsOpacity: false)
                        .labelsHidden()
                    Text(configManager.config.resolvedPopoverSalaryColorHex)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
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
                    ColorPicker("", selection: workProgressColorBinding, supportsOpacity: false)
                        .labelsHidden()
                    Text(configManager.config.resolvedWorkProgressColorHex)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
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
                    Picker("", selection: Binding(
                        get: { configManager.config.workProgressDisplayDecimalPlaces },
                        set: { setConfigValue(\.workProgressDecimalPlaces, to: $0) }
                    )) {
                        ForEach(SalaryConfig.workProgressDecimalPlacesRange, id: \.self) { digits in
                            Text("\(digits)").tag(digits)
                        }
                    }
                    .pickerStyle(.segmented)
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
                    ColorPicker("", selection: lunchBreakColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!configManager.config.displaysLunchBreakColor)
                    Text(configManager.config.resolvedLunchBreakColorHex)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Toggle("显示晚饭颜色", isOn: Binding(
                    get: { configManager.config.displaysDinnerBreakColor },
                    set: { configManager.config.dinnerBreakShowsColor = $0 }
                ))

                HStack {
                    Text("晚饭颜色")
                        .frame(width: 80, alignment: .leading)
                    ColorPicker("", selection: dinnerBreakColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!configManager.config.displaysDinnerBreakColor)
                    Text(configManager.config.resolvedDinnerBreakColorHex)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
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

    /// 弹窗内容开关使用统一宽度，保证两列排列时不会因为文字长短错位。
    private func popoverContentToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .frame(maxWidth: .infinity, alignment: .leading)
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

                    if let registrationError = shortcutMonitor.registrationError {
                        Label(registrationError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(12)
        } label: {
            Label("快捷键", systemImage: "keyboard")
                .font(.headline)
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

    /// 时间输入统一使用支持键盘输入的组件，避免多个设置项行为不一致。
    private func timePicker(hour: Binding<Int>, minute: Binding<Int>) -> some View {
        TimeInputView(hour: hour, minute: minute)
    }

    /// Segmented Picker 可能在 SwiftUI 的视图更新栈里回写 selection；延后一拍写配置可避免 @Published 同步发布警告。
    private func setConfigValue<Value: Equatable>(_ keyPath: WritableKeyPath<SalaryConfig, Value>, to value: Value) {
        DispatchQueue.main.async {
            guard configManager.config[keyPath: keyPath] != value else { return }
            configManager.config[keyPath: keyPath] = value
        }
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

    /// 下面这些颜色 Binding 负责在 SwiftUI Color 和配置中的 hex 字符串之间转换。
    private var lunchBreakColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.lunchBreakNSColor)
            },
            set: { newColor in
                configManager.config.lunchBreakColorHex = SalaryColor.hex(from: NSColor(newColor))
            }
        )
    }

    private var workProgressColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.workProgressNSColor)
            },
            set: { newColor in
                configManager.config.workProgressColorHex = SalaryColor.hex(from: NSColor(newColor))
            }
        )
    }

    private var dinnerBreakColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.dinnerBreakNSColor)
            },
            set: { newColor in
                configManager.config.dinnerBreakColorHex = SalaryColor.hex(from: NSColor(newColor))
            }
        )
    }

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

    private var popoverSalaryColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.popoverSalaryNSColor)
            },
            set: { newColor in
                configManager.config.popoverSalaryColorHex = SalaryColor.hex(from: NSColor(newColor))
            }
        )
    }

    private var statusBarSalaryColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: configManager.config.statusBarSalaryNSColor)
            },
            set: { newColor in
                configManager.config.statusBarSalaryColorHex = SalaryColor.hex(from: NSColor(newColor))
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

    /// 设置页金额格式和弹窗共用小数位配置，但可按场景决定是否显示 ¥。
    private func formatMoney(_ value: Double, showCurrencySymbol: Bool = true) -> String {
        let amount = String(format: "%.\(configManager.config.displayDecimalPlaces)f", value)
        return showCurrencySymbol ? "¥\(amount)" : amount
    }

    /// 薪资换算说明必须随月薪折算和补贴规则变化，避免用户误以为所有金额都只按日薪反推。
    private var salaryConversionDescription: String {
        let config = configManager.config
        let monthlyDescription: String
        switch config.resolvedMonthlySalaryCalculationMode {
        case .fixedAverage:
            monthlyDescription = "基础月薪 = 基础日薪 × 固定 \(formatWorkdayCount(config.resolvedFixedMonthlyWorkdays)) 天"
        case .salaryCycleWorkdays:
            let period = config.currentSalaryCyclePeriod
            monthlyDescription = "基础月薪 = 基础日薪 × 当前薪资周期计薪 \(period.paidWorkdays) 天（\(formatSalaryCyclePeriod(period))）"
        }

        return """
        换算说明：
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

    /// 动态薪资周期依赖节假日和调休日，切到该模式时主动加载涉及年份。
    private func ensureSalaryCycleHolidayData() {
        let config = configManager.config
        let subsidyUsesCycleWorkdays = config.subsidies.contains { subsidy in
            subsidy.enabled
                && subsidy.type == .monthly
                && subsidy.monthlyApplicationMode == .spreadToDailySalary
                && subsidy.monthlyProrationMode == .salaryCycleWorkdays
        }
        guard config.workDayRule == .weekdaysOnly,
              config.resolvedMonthlySalaryCalculationMode == .salaryCycleWorkdays || subsidyUsesCycleWorkdays else {
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

    /// 薪资周期起始日只允许 1...31；2 月缺失日期由计算层折到当月最后一天。
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
