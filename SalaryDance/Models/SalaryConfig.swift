import Foundation
import Cocoa
import Carbon.HIToolbox

/// 用户输入金额的薪资口径。计算时统一先折算为日薪。
enum SalaryType: String, Codable, CaseIterable {
    case monthly = "月薪"
    case daily = "日薪"
    case yearly = "年薪"
}

/// 决定哪些自然日参与计薪。
enum WorkDayRule: String, Codable, CaseIterable {
    case weekdaysOnly = "仅工作日"
    case everyday = "每天都计薪"
    case custom = "自定义工作日"
}

/// 月薪和日薪互相折算时使用的计薪日来源。
enum MonthlySalaryCalculationMode: String, Codable, CaseIterable, Identifiable {
    case fixedAverage = "固定指定天数"
    case salaryCycleWorkdays = "按薪资周期计薪日"

    var id: String { rawValue }
}

/// 补贴的发放口径。按日补贴直接进入日薪，按月补贴再决定是否平摊到日薪。
enum SalarySubsidyType: String, Codable, CaseIterable, Identifiable {
    case daily = "按日补贴"
    case monthly = "按月补贴"

    var id: String { rawValue }
}

/// 按月补贴的计入方式：只汇入月薪，或拆成每天收入参与实时累计。
enum MonthlySubsidyApplicationMode: String, Codable, CaseIterable, Identifiable {
    case addToMonthlySalary = "加到月薪"
    case spreadToDailySalary = "平摊到每天"

    var id: String { rawValue }
}

/// 按月补贴平摊到每天时使用的分母来源。
enum MonthlySubsidyProrationMode: String, Codable, CaseIterable, Identifiable {
    case salaryCycleTotalDays = "周期内总天数"
    case fixedDays = "固定天数"
    case salaryCycleWorkdays = "周期内工作日天数"

    var id: String { rawValue }
}

/// 单条补贴配置。金额始终保存为非负数，按月补贴的固定平摊天数默认 21.75。
struct SalarySubsidy: Codable, Equatable, Identifiable {
    static let defaultFixedProrationDays = 21.75

    var id: UUID = UUID()
    var enabled: Bool = true
    var name: String = "补贴名"
    var type: SalarySubsidyType = .daily
    var amount: Double = 0
    var monthlyApplicationMode: MonthlySubsidyApplicationMode = .spreadToDailySalary
    var monthlyProrationMode: MonthlySubsidyProrationMode = .fixedDays
    var fixedProrationDays: Double = Self.defaultFixedProrationDays

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "补贴名" : trimmed
    }

    mutating func normalize(fixedDaysRange: ClosedRange<Double>) {
        amount = amount.isFinite ? max(0, amount) : 0
        fixedProrationDays = min(
            fixedDaysRange.upperBound,
            max(fixedDaysRange.lowerBound, fixedProrationDays.isFinite ? fixedProrationDays : Self.defaultFixedProrationDays)
        )
    }
}

/// 状态栏实时金额的数字变化效果。
enum StatusBarSalaryAnimationStyle: String, Codable, CaseIterable, Identifiable {
    case rolling = "滚动"
    case bounce = "跳动"
    case none = "关闭"

    var id: String { rawValue }
}

/// 快捷键动作序列里的单个动作。
enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case showStatusBarEarnings
    case hideStatusBarEarnings
    case openPrivatePopover
    case openPlainPopover
    case closePopover

    var id: String { rawValue }

    static let defaultSequence: [ShortcutAction] = [
        .showStatusBarEarnings,
        .hideStatusBarEarnings
    ]

    var title: String {
        switch self {
        case .showStatusBarEarnings:
            return "打开状态栏实时显示"
        case .hideStatusBarEarnings:
            return "关闭状态栏实时显示"
        case .openPrivatePopover:
            return "脱敏打开窗口"
        case .openPlainPopover:
            return "不脱敏打开窗口"
        case .closePopover:
            return "关闭窗口"
        }
    }

    var iconName: String {
        switch self {
        case .showStatusBarEarnings:
            return "yensign.circle"
        case .hideStatusBarEarnings:
            return "yensign.circle.fill"
        case .openPrivatePopover:
            return "eye.slash"
        case .openPlainPopover:
            return "eye"
        case .closePopover:
            return "xmark.circle"
        }
    }
}

/// 只保存时分的时间段，支持结束时间小于开始时间来表达跨夜。
struct TimeRange: Codable, Equatable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }
    var durationMinutes: Int {
        if endMinutes > startMinutes {
            return endMinutes - startMinutes
        }
        if endMinutes < startMinutes {
            return endMinutes + 24 * 60 - startMinutes
        }
        return 0
    }

    var startString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    static let defaultWorkTime = TimeRange(startHour: 10, startMinute: 0, endHour: 21, endMinute: 0)
    static let defaultLunchBreak = TimeRange(startHour: 12, startMinute: 0, endHour: 14, endMinute: 0)
    static let defaultDinnerBreak = TimeRange(startHour: 18, startMinute: 0, endHour: 19, endMinute: 0)

    mutating func normalizeClockFields() {
        startHour = Self.clamped(startHour, in: 0...23)
        startMinute = Self.clamped(startMinute, in: 0...59)
        endHour = Self.clamped(endHour, in: 0...23)
        endMinute = Self.clamped(endMinute, in: 0...59)
    }

    private static func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

/// 当前薪资周期范围，以及该周期内按规则统计出的计薪日数量。
struct SalaryCyclePeriod: Equatable {
    let start: Date
    let endExclusive: Date
    let totalDays: Int
    let paidWorkdays: Int

    var endInclusive: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
    }
}

/// 集中处理用户可配置颜色，所有颜色持久化为十六进制字符串。
enum SalaryColor {
    static let defaultWorkProgressHex = "#F60000"
    static let defaultLunchBreakHex = "#8CACED"
    static let defaultDinnerBreakHex = "#8CACED"
    static let defaultHolidayPastHex = "#EF4444"
    static let defaultHolidayFutureHex = "#22C55E"
    static let defaultPopoverSalaryHex = "#F60000"
    static let defaultStatusBarSalaryHex = "#FFFFFF"

    static func normalizedHex(_ value: String?, fallback: String) -> String {
        let color = nsColor(hex: value, fallbackHex: fallback)
        return hex(from: color)
    }

    static func nsColor(hex value: String?, fallbackHex: String) -> NSColor {
        parseHex(value) ?? parseHex(fallbackHex) ?? .systemBlue
    }

    static func hex(from color: NSColor) -> String {
        let converted = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", clampColor(red), clampColor(green), clampColor(blue))
    }

    private static func parseHex(_ value: String?) -> NSColor? {
        guard let value else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var number: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&number) else { return nil }

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        if cleaned.count == 8 {
            red = (number >> 24) & 0xff
            green = (number >> 16) & 0xff
            blue = (number >> 8) & 0xff
            alpha = number & 0xff
        } else {
            red = (number >> 16) & 0xff
            green = (number >> 8) & 0xff
            blue = number & 0xff
            alpha = 0xff
        }

        return NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }

    private static func clampColor(_ value: Int) -> Int {
        min(255, max(0, value))
    }
}

/// App 的完整配置模型。新增配置优先直接加字段，不做旧字段迁移。
struct SalaryConfig: Codable, Equatable {
    static let refreshIntervalRange: ClosedRange<Double> = 0.5...3600
    static let workProgressGridIntervalOptions = [15, 30, 60, 120]
    static let workProgressDecimalPlacesRange = 0...3
    static let averageMonthlyWorkDays = 21.75
    static let monthlyWorkdaysRange: ClosedRange<Double> = 1...31
    static let yearlyWorkDays = 250.0
    static let defaultShortcutModifiers = Int(NSEvent.ModifierFlags([.option, .command]).rawValue)

    var salaryType: SalaryType = .monthly
    var salaryAmount: Double = 0
    var monthlySalaryCalculationMode: MonthlySalaryCalculationMode = .fixedAverage
    var fixedMonthlyWorkdays: Double = Self.averageMonthlyWorkDays
    var monthlySalaryCycleStartDay: Int = 1
    var subsidies: [SalarySubsidy] = []
    var workTime: TimeRange = .defaultWorkTime
    var lunchBreakEnabled: Bool = true
    var lunchBreak: TimeRange = .defaultLunchBreak
    var dinnerBreakEnabled: Bool = true
    var dinnerBreak: TimeRange = .defaultDinnerBreak
    var workDayRule: WorkDayRule = .weekdaysOnly
    var customWorkDays: Set<Int> = [1, 3, 4, 5]
    var launchAtLogin: Bool = false
    var shortcutModifiers: Int = Self.defaultShortcutModifiers
    var shortcutKeyCode: UInt16 = ShortcutKey.defaultKeyCode
    var shortcutEnabled: Bool = true
    var statusBarShowsEarnings: Bool = true
    var popoverShowsCurrentEarnings: Bool = true
    var popoverShowsRemainingEarnings: Bool = true
    var popoverShowsWorkStatus: Bool = true
    var popoverShowsSecondSalary: Bool = true
    var popoverShowsMinuteSalary: Bool = true
    var popoverShowsHourlySalary: Bool = true
    var popoverShowsDailySalary: Bool = false
    var popoverShowsMonthlySalary: Bool = false
    var popoverShowsYearlySalary: Bool = false
    var popoverShowsWorkProgress: Bool = true
    var popoverShowsQuote: Bool = true
    var statusItemClickShowsPrivatePopover: Bool = true
    var statusBarShowsAppIcon: Bool = false
    var statusBarShowsCurrencySymbol: Bool = true
    var statusBarSalaryAnimationStyle: StatusBarSalaryAnimationStyle = .rolling
    var moneyDecimalPlaces: Int = 2
    var shortcutActionSequence: [ShortcutAction] = ShortcutAction.defaultSequence
    var idleUsesLowFrequencyUpdates: Bool = true
    var refreshIntervalSeconds: Double = 1
    var lunchBreakShowsColor: Bool = false
    var dinnerBreakShowsColor: Bool = false
    var workProgressShowsGrid: Bool = true
    var workProgressShowsSegmentLabels: Bool = true
    var workProgressGridMinutes: Int = 60
    /// 工作进度百分比的小数位，默认 0 位以延续原来的整数百分比展示。
    var workProgressDecimalPlaces: Int = 0
    var breakTimeCountsAsPaidWork: Bool = false
    var workProgressColorHex: String = SalaryColor.defaultWorkProgressHex
    var lunchBreakColorHex: String = SalaryColor.defaultLunchBreakHex
    var dinnerBreakColorHex: String = SalaryColor.defaultDinnerBreakHex
    var holidayPastColorHex: String = SalaryColor.defaultHolidayPastHex
    var holidayFutureColorHex: String = SalaryColor.defaultHolidayFutureHex
    var popoverSalaryColorHex: String = SalaryColor.defaultPopoverSalaryHex
    var statusBarSalaryColorHex: String? = nil

    var shortcutDisplayString: String {
        let flags = shortcutModifierFlags
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        let keyDisplay = ShortcutKey.displayName(for: resolvedShortcutKeyCode)
        return parts.joined() + keyDisplay
    }

    var shortcutModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(shortcutModifiers))
            .intersection(.shortcutModifierMask)
    }

    var resolvedShortcutKeyCode: UInt16 {
        shortcutKeyCode
    }

    var displaysEarningsInStatusBar: Bool {
        statusBarShowsEarnings
    }

    var usesLowFrequencyUpdatesWhenIdle: Bool {
        idleUsesLowFrequencyUpdates
    }

    var resolvedRefreshIntervalSeconds: Double {
        min(Self.refreshIntervalRange.upperBound, max(Self.refreshIntervalRange.lowerBound, refreshIntervalSeconds))
    }

    var popoverDisplaysCurrentEarnings: Bool {
        popoverShowsCurrentEarnings
    }

    var popoverDisplaysRemainingEarnings: Bool {
        popoverShowsRemainingEarnings
    }

    var popoverDisplaysWorkStatus: Bool {
        popoverShowsWorkStatus
    }

    var popoverDisplaysSecondSalary: Bool {
        popoverShowsSecondSalary
    }

    var popoverDisplaysMinuteSalary: Bool {
        popoverShowsMinuteSalary
    }

    var popoverDisplaysHourlySalary: Bool {
        popoverShowsHourlySalary
    }

    var popoverDisplaysDailySalary: Bool {
        popoverShowsDailySalary
    }

    var popoverDisplaysMonthlySalary: Bool {
        popoverShowsMonthlySalary
    }

    var popoverDisplaysYearlySalary: Bool {
        popoverShowsYearlySalary
    }

    var popoverDisplaysAnySalaryRate: Bool {
        popoverDisplaysSecondSalary
            || popoverDisplaysMinuteSalary
            || popoverDisplaysHourlySalary
            || popoverDisplaysDailySalary
            || popoverDisplaysMonthlySalary
            || popoverDisplaysYearlySalary
    }

    var popoverDisplaysWorkProgress: Bool {
        popoverShowsWorkProgress
    }

    var popoverDisplaysQuote: Bool {
        popoverShowsQuote
    }

    var usesLunchBreak: Bool {
        lunchBreakEnabled
    }

    var displaysLunchBreakColor: Bool {
        lunchBreakShowsColor
    }

    var displaysDinnerBreakColor: Bool {
        dinnerBreakShowsColor
    }

    var statusBarDisplaysAppIcon: Bool {
        statusBarShowsAppIcon
    }

    var statusBarDisplaysCurrencySymbol: Bool {
        statusBarShowsCurrencySymbol
    }

    var resolvedStatusBarSalaryAnimationStyle: StatusBarSalaryAnimationStyle {
        statusBarSalaryAnimationStyle
    }

    var workProgressDisplaysGrid: Bool {
        workProgressShowsGrid
    }

    var workProgressDisplaysSegmentLabels: Bool {
        workProgressShowsSegmentLabels
    }

    var workProgressGridIntervalMinutes: Int {
        Self.workProgressGridIntervalOptions.contains(workProgressGridMinutes) ? workProgressGridMinutes : 60
    }

    var workProgressDisplayDecimalPlaces: Int {
        min(Self.workProgressDecimalPlacesRange.upperBound, max(Self.workProgressDecimalPlacesRange.lowerBound, workProgressDecimalPlaces))
    }

    var countsBreakTimeAsPaidWork: Bool {
        breakTimeCountsAsPaidWork
    }

    var resolvedWorkProgressColorHex: String {
        SalaryColor.normalizedHex(workProgressColorHex, fallback: SalaryColor.defaultWorkProgressHex)
    }

    var resolvedLunchBreakColorHex: String {
        SalaryColor.normalizedHex(lunchBreakColorHex, fallback: SalaryColor.defaultLunchBreakHex)
    }

    var resolvedDinnerBreakColorHex: String {
        SalaryColor.normalizedHex(dinnerBreakColorHex, fallback: SalaryColor.defaultDinnerBreakHex)
    }

    var resolvedHolidayPastColorHex: String {
        SalaryColor.normalizedHex(holidayPastColorHex, fallback: SalaryColor.defaultHolidayPastHex)
    }

    var resolvedHolidayFutureColorHex: String {
        SalaryColor.normalizedHex(holidayFutureColorHex, fallback: SalaryColor.defaultHolidayFutureHex)
    }

    var resolvedPopoverSalaryColorHex: String {
        SalaryColor.normalizedHex(popoverSalaryColorHex, fallback: SalaryColor.defaultPopoverSalaryHex)
    }

    var resolvedStatusBarSalaryColorHex: String {
        SalaryColor.normalizedHex(statusBarSalaryColorHex, fallback: SalaryColor.defaultStatusBarSalaryHex)
    }

    var lunchBreakNSColor: NSColor {
        SalaryColor.nsColor(hex: lunchBreakColorHex, fallbackHex: SalaryColor.defaultLunchBreakHex)
    }

    var workProgressNSColor: NSColor {
        SalaryColor.nsColor(hex: workProgressColorHex, fallbackHex: SalaryColor.defaultWorkProgressHex)
    }

    var dinnerBreakNSColor: NSColor {
        SalaryColor.nsColor(hex: dinnerBreakColorHex, fallbackHex: SalaryColor.defaultDinnerBreakHex)
    }

    var holidayPastNSColor: NSColor {
        SalaryColor.nsColor(hex: holidayPastColorHex, fallbackHex: SalaryColor.defaultHolidayPastHex)
    }

    var holidayFutureNSColor: NSColor {
        SalaryColor.nsColor(hex: holidayFutureColorHex, fallbackHex: SalaryColor.defaultHolidayFutureHex)
    }

    var popoverSalaryNSColor: NSColor {
        SalaryColor.nsColor(hex: popoverSalaryColorHex, fallbackHex: SalaryColor.defaultPopoverSalaryHex)
    }

    var statusBarSalaryNSColor: NSColor {
        SalaryColor.nsColor(hex: statusBarSalaryColorHex, fallbackHex: SalaryColor.defaultStatusBarSalaryHex)
    }

    var opensPrivatePopoverFromStatusItemClick: Bool {
        statusItemClickShowsPrivatePopover
    }

    var displayDecimalPlaces: Int {
        min(3, max(0, moneyDecimalPlaces))
    }

    var resolvedShortcutActionSequence: [ShortcutAction] {
        shortcutActionSequence.isEmpty ? ShortcutAction.defaultSequence : shortcutActionSequence
    }

    var hasPopoverInformationEnabled: Bool {
        popoverDisplaysCurrentEarnings
            || popoverDisplaysRemainingEarnings
            || popoverDisplaysWorkStatus
            || popoverDisplaysAnySalaryRate
            || popoverDisplaysWorkProgress
            || popoverDisplaysQuote
    }

    var resolvedMonthlySalaryCalculationMode: MonthlySalaryCalculationMode {
        monthlySalaryCalculationMode
    }

    var resolvedMonthlySalaryCycleStartDay: Int {
        min(31, max(1, monthlySalaryCycleStartDay))
    }

    var resolvedFixedMonthlyWorkdays: Double {
        min(Self.monthlyWorkdaysRange.upperBound, max(Self.monthlyWorkdaysRange.lowerBound, fixedMonthlyWorkdays))
    }

    var currentSalaryCyclePeriod: SalaryCyclePeriod {
        salaryCyclePeriod(containing: Date())
    }

    var currentSalaryCycleYears: Set<Int> {
        yearsCovered(by: currentSalaryCyclePeriod)
    }

    /// 当前月薪折算天数，固定模式使用用户配置，动态模式使用当前周期计薪日。
    var monthlySalaryWorkdayCount: Double {
        switch resolvedMonthlySalaryCalculationMode {
        case .fixedAverage:
            return resolvedFixedMonthlyWorkdays
        case .salaryCycleWorkdays:
            // 节假日数据未就绪或周期无计薪日时，回退到固定天数，避免除以 0。
            let count = currentSalaryCyclePeriod.paidWorkdays
            return count > 0 ? Double(count) : resolvedFixedMonthlyWorkdays
        }
    }

    /// 只包含用户输入的基础薪资，不含任何补贴；补贴需要按自身规则单独计入。
    var baseDailySalary: Double {
        switch salaryType {
        case .daily:
            return salaryAmount
        case .monthly:
            return salaryAmount / monthlySalaryWorkdayCount
        case .yearly:
            return salaryAmount / Self.yearlyWorkDays
        }
    }

    /// 按日补贴直接进入日薪，因此会影响实时收入、秒薪、分薪和时薪。
    var dailySubsidyTotal: Double {
        subsidies.reduce(0) { total, subsidy in
            guard subsidy.enabled, subsidy.type == .daily else { return total }
            return total + subsidy.amount
        }
    }

    /// 按月补贴的月度原值，用于月薪和年薪汇总；是否平摊只影响日薪和实时收入。
    var monthlySubsidyTotal: Double {
        subsidies.reduce(0) { total, subsidy in
            guard subsidy.enabled, subsidy.type == .monthly else { return total }
            return total + subsidy.amount
        }
    }

    var monthlySubsidyAddedToMonthlyTotal: Double {
        subsidies.reduce(0) { total, subsidy in
            guard subsidy.enabled,
                  subsidy.type == .monthly,
                  subsidy.monthlyApplicationMode == .addToMonthlySalary else {
                return total
            }
            return total + subsidy.amount
        }
    }

    /// 只有选择“平摊到每天”的按月补贴会折进日薪，分母按每条补贴自己的规则计算。
    var monthlySubsidySpreadDailyTotal: Double {
        subsidies.reduce(0) { total, subsidy in
            guard subsidy.enabled,
                  subsidy.type == .monthly,
                  subsidy.monthlyApplicationMode == .spreadToDailySalary else {
                return total
            }
            let divisor = monthlySubsidyProrationDays(for: subsidy)
            guard divisor > 0 else { return total }
            return total + subsidy.amount / divisor
        }
    }

    var effectiveDailySubsidyTotal: Double {
        dailySubsidyTotal + monthlySubsidySpreadDailyTotal
    }

    var monthlySalary: Double {
        let recurringDailyCompensation = baseDailySalary + dailySubsidyTotal
        return recurringDailyCompensation * monthlySalaryWorkdayCount + monthlySubsidyTotal
    }

    var dailySalary: Double {
        baseDailySalary + effectiveDailySubsidyTotal
    }

    var yearlySalary: Double {
        let recurringDailyCompensation = baseDailySalary + dailySubsidyTotal
        return recurringDailyCompensation * Self.yearlyWorkDays + monthlySubsidyTotal * 12
    }

    var hasCompensation: Bool {
        salaryAmount > 0 || subsidies.contains { $0.enabled && $0.amount > 0 }
    }

    var salaryPerHour: Double {
        salaryPerSecond * 3600
    }

    var salaryPerMinute: Double {
        salaryPerSecond * 60
    }

    var workTimelineStartMinutes: Int {
        workTime.startMinutes
    }

    var workTimelineEndMinutes: Int {
        workTime.startMinutes + workTime.durationMinutes
    }

    var workDurationMinutes: Int {
        workTime.durationMinutes
    }

    /// 返回指定日期所在的薪资周期，支持每月非 1 号起算和 2 月短月兜底。
    func salaryCyclePeriod(containing date: Date, calendar: Calendar = .current) -> SalaryCyclePeriod {
        let start = salaryCycleStart(containing: date, calendar: calendar)
        let nextStart = nextSalaryCycleStart(after: start, calendar: calendar)
        let totalDays = max(0, calendar.dateComponents([.day], from: start, to: nextStart).day ?? 0)
        let paidWorkdays = paidWorkdayCount(from: start, to: nextStart, calendar: calendar)
        return SalaryCyclePeriod(start: start, endExclusive: nextStart, totalDays: totalDays, paidWorkdays: paidWorkdays)
    }

    func monthlySubsidyProrationDays(for subsidy: SalarySubsidy) -> Double {
        switch subsidy.monthlyProrationMode {
        case .salaryCycleTotalDays:
            let days = currentSalaryCyclePeriod.totalDays
            return days > 0 ? Double(days) : subsidy.fixedProrationDays
        case .fixedDays:
            return subsidy.fixedProrationDays
        case .salaryCycleWorkdays:
            let workdays = currentSalaryCyclePeriod.paidWorkdays
            return workdays > 0 ? Double(workdays) : subsidy.fixedProrationDays
        }
    }

    /// 判断某一天是否计薪，节假日和调休日只在“仅工作日”模式下生效。
    func shouldCountSalary(on date: Date, calendar: Calendar = .current) -> Bool {
        switch workDayRule {
        case .everyday:
            return true
        case .weekdaysOnly:
            return ChineseHolidays.shared.isWorkday(date)
        case .custom:
            let weekday = calendar.component(.weekday, from: date)
            let mappedDay = weekday == 1 ? 7 : weekday - 1
            return customWorkDays.contains(mappedDay)
        }
    }

    func clampedIntervalsInWorkTime(for range: TimeRange) -> [(startMinutes: Int, endMinutes: Int)] {
        let workStart = workTimelineStartMinutes
        let workEnd = workTimelineEndMinutes
        let rangeDuration = range.durationMinutes
        guard workEnd > workStart, rangeDuration > 0 else { return [] }

        // 休息段和工作段都允许跨夜；用前一天、当天、后一天三份投影来找交集。
        return [-24 * 60, 0, 24 * 60].compactMap { offset in
            let start = range.startMinutes + offset
            let end = start + rangeDuration
            let clampedStart = max(start, workStart)
            let clampedEnd = min(end, workEnd)
            guard clampedEnd > clampedStart else { return nil }
            return (startMinutes: clampedStart, endMinutes: clampedEnd)
        }
    }

    /// 工作窗口内实际生效的休息时间，已经裁剪到工作时间范围并合并重叠段。
    var breakIntervalsWithinWorkTime: [(startMinutes: Int, endMinutes: Int)] {
        guard workDurationMinutes > 0 else { return [] }

        var intervals: [(startMinutes: Int, endMinutes: Int)] = []

        if usesLunchBreak {
            intervals.append(contentsOf: clampedIntervalsInWorkTime(for: lunchBreak))
        }
        if dinnerBreakEnabled {
            intervals.append(contentsOf: clampedIntervalsInWorkTime(for: dinnerBreak))
        }

        let sorted = intervals.sorted { $0.startMinutes < $1.startMinutes }
        return sorted.reduce(into: []) { result, interval in
            guard let last = result.last else {
                result.append(interval)
                return
            }

            // 午休和晚饭可能被用户配置成重叠，计薪扣减前先合并避免重复扣。
            if interval.startMinutes <= last.endMinutes {
                result[result.count - 1] = (
                    startMinutes: last.startMinutes,
                    endMinutes: max(last.endMinutes, interval.endMinutes)
                )
            } else {
                result.append(interval)
            }
        }
    }

    var breakMinutesWithinWorkTime: Int {
        breakIntervalsWithinWorkTime.reduce(0) { total, interval in
            total + interval.endMinutes - interval.startMinutes
        }
    }

    var workMinutesExcludingBreaks: Int {
        max(0, workDurationMinutes - breakMinutesWithinWorkTime)
    }

    var paidWorkMinutes: Int {
        countsBreakTimeAsPaidWork
            ? max(0, workDurationMinutes)
            : workMinutesExcludingBreaks
    }

    var salaryPerSecond: Double {
        let workSeconds = Double(paidWorkMinutes) * 60
        guard workSeconds > 0 else { return 0 }
        return dailySalary / workSeconds
    }

    var isValid: Bool {
        hasCompensation && paidWorkMinutes > 0
    }

    /// 每次保存前统一修正越界值，避免设置页输入非法值后污染持久化配置。
    mutating func normalize() {
        salaryAmount = salaryAmount.isFinite ? max(0, salaryAmount) : 0
        subsidies = subsidies.map { subsidy in
            var normalized = subsidy
            normalized.normalize(fixedDaysRange: Self.monthlyWorkdaysRange)
            return normalized
        }
        workTime.normalizeClockFields()
        lunchBreak.normalizeClockFields()
        dinnerBreak.normalizeClockFields()
        customWorkDays = Set(customWorkDays.filter { (1...7).contains($0) })
        fixedMonthlyWorkdays = min(Self.monthlyWorkdaysRange.upperBound, max(Self.monthlyWorkdaysRange.lowerBound, fixedMonthlyWorkdays.isFinite ? fixedMonthlyWorkdays : Self.averageMonthlyWorkDays))
        monthlySalaryCycleStartDay = min(31, max(1, monthlySalaryCycleStartDay))
        shortcutModifiers = Int(shortcutModifierFlags.rawValue)
        if !ShortcutKey.isRecordable(shortcutKeyCode) {
            shortcutKeyCode = ShortcutKey.defaultKeyCode
        }
        moneyDecimalPlaces = min(3, max(0, moneyDecimalPlaces))
        refreshIntervalSeconds = Self.normalizedRefreshInterval(refreshIntervalSeconds)
        if !Self.workProgressGridIntervalOptions.contains(workProgressGridMinutes) {
            workProgressGridMinutes = 60
        }
        workProgressDecimalPlaces = min(Self.workProgressDecimalPlacesRange.upperBound, max(Self.workProgressDecimalPlacesRange.lowerBound, workProgressDecimalPlaces))
        shortcutActionSequence = Self.normalizedShortcutActionSequence(shortcutActionSequence)
        workProgressColorHex = resolvedWorkProgressColorHex
        lunchBreakColorHex = resolvedLunchBreakColorHex
        dinnerBreakColorHex = resolvedDinnerBreakColorHex
        holidayPastColorHex = resolvedHolidayPastColorHex
        holidayFutureColorHex = resolvedHolidayFutureColorHex
        popoverSalaryColorHex = resolvedPopoverSalaryColorHex
        if statusBarSalaryColorHex != nil {
            statusBarSalaryColorHex = resolvedStatusBarSalaryColorHex
        }
    }

    private static func normalizedRefreshInterval(_ value: Double) -> Double {
        let finiteValue = value.isFinite ? value : 1
        let clamped = min(refreshIntervalRange.upperBound, max(refreshIntervalRange.lowerBound, finiteValue))
        return (clamped * 2).rounded() / 2
    }

    private static func normalizedShortcutActionSequence(_ sequence: [ShortcutAction]) -> [ShortcutAction] {
        var seen = Set<ShortcutAction>()
        let unique = sequence.filter { action in
            guard !seen.contains(action) else { return false }
            seen.insert(action)
            return true
        }
        return unique.isEmpty ? ShortcutAction.defaultSequence : unique
    }

    private func salaryCycleStart(containing date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: dayStart)
        guard let year = components.year,
              let month = components.month else {
            return dayStart
        }

        let currentMonthStart = salaryCycleStart(year: year, month: month, calendar: calendar)
        if dayStart >= currentMonthStart {
            return currentMonthStart
        }

        let previous = shiftedMonth(year: year, month: month, offset: -1, calendar: calendar)
        return salaryCycleStart(year: previous.year, month: previous.month, calendar: calendar)
    }

    private func nextSalaryCycleStart(after start: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: start)
        guard let year = components.year,
              let month = components.month else {
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        }

        let next = shiftedMonth(year: year, month: month, offset: 1, calendar: calendar)
        return salaryCycleStart(year: next.year, month: next.month, calendar: calendar)
    }

    private func salaryCycleStart(year: Int, month: Int, calendar: Calendar) -> Date {
        let firstDay = DateComponents(calendar: calendar, year: year, month: month, day: 1)
        guard let firstDate = calendar.date(from: firstDay),
              let days = calendar.range(of: .day, in: .month, for: firstDate) else {
            return Date()
        }

        let day = min(resolvedMonthlySalaryCycleStartDay, days.count)
        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        return calendar.startOfDay(for: calendar.date(from: components) ?? firstDate)
    }

    private func shiftedMonth(year: Int, month: Int, offset: Int, calendar: Calendar) -> (year: Int, month: Int) {
        let start = DateComponents(calendar: calendar, year: year, month: month, day: 1)
        guard let date = calendar.date(from: start),
              let shifted = calendar.date(byAdding: .month, value: offset, to: date) else {
            return (year, month)
        }
        let components = calendar.dateComponents([.year, .month], from: shifted)
        return (components.year ?? year, components.month ?? month)
    }

    private func paidWorkdayCount(from start: Date, to endExclusive: Date, calendar: Calendar) -> Int {
        guard start < endExclusive else { return 0 }

        var count = 0
        var cursor = calendar.startOfDay(for: start)
        while cursor < endExclusive {
            if shouldCountSalary(on: cursor, calendar: calendar) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return count
    }

    private func yearsCovered(by period: SalaryCyclePeriod, calendar: Calendar = .current) -> Set<Int> {
        guard period.start < period.endExclusive else {
            return [calendar.component(.year, from: period.start)]
        }

        var years = Set<Int>()
        var cursor = calendar.startOfDay(for: period.start)
        while cursor < period.endExclusive {
            years.insert(calendar.component(.year, from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return years
    }
}

/// Carbon 全局快捷键使用 keyCode 注册，这里维护 keyCode 到展示文案的映射和校验。
enum ShortcutKey {
    static let defaultKeyCode: UInt16 = 6

    private static let namesByKeyCode: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Esc",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear",
        75: "Keypad /", 76: "Keypad Return", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
        86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
        91: "Keypad 8", 92: "Keypad 9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10",
        111: "F12", 114: "Help", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    private static let functionKeyCodes: Set<UInt16> = [
        96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122
    ]

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func displayName(for keyCode: UInt16) -> String {
        namesByKeyCode[keyCode] ?? "Key \(keyCode)"
    }

    static func displayName(for event: NSEvent) -> String {
        if let knownName = namesByKeyCode[event.keyCode] {
            return knownName
        }
        return normalizedFallback(event.charactersIgnoringModifiers ?? "", defaultValue: "Key \(event.keyCode)")
    }

    static func canRegisterWithoutModifiers(_ keyCode: UInt16) -> Bool {
        functionKeyCodes.contains(keyCode)
    }

    static func isRecordable(_ keyCode: UInt16) -> Bool {
        !modifierKeyCodes.contains(keyCode)
    }

    private static func normalizedFallback(_ value: String, defaultValue: String = "") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        if trimmed == " " { return "Space" }
        return trimmed.count == 1 ? trimmed.uppercased() : trimmed
    }
}

extension NSEvent.ModifierFlags {
    static let shortcutModifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var carbonShortcutModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

/// 统一读写用户配置。当前策略是不做兼容迁移，解码失败时回到默认配置。
final class SalaryConfigManager: ObservableObject {
    static let shared = SalaryConfigManager()

    @Published var config: SalaryConfig {
        didSet {
            normalizeAndSave()
        }
    }

    private let defaults = UserDefaults.standard
    private let configKey = "salary_config"

    init() {
        if let data = defaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(SalaryConfig.self, from: data) {
            var normalized = decoded
            normalized.normalize()
            config = normalized
            save()
        } else {
            config = SalaryConfig()
            save()
        }
    }

    private func normalizeAndSave() {
        var normalized = config
        normalized.normalize()
        guard normalized == config else {
            config = normalized
            return
        }
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
    }
}
