import Foundation
import Cocoa
import Carbon.HIToolbox

/// 用户输入金额的薪资口径。计算时统一先折算为日薪。
enum SalaryType: String, Codable, CaseIterable {
    case monthly
    case daily
    case yearly

    var title: String {
        switch self {
        case .monthly: return "月薪"
        case .daily: return "日薪"
        case .yearly: return "年薪"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.monthly.rawValue, "月薪":
            self = .monthly
        case Self.daily.rawValue, "日薪":
            self = .daily
        case Self.yearly.rawValue, "年薪":
            self = .yearly
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown SalaryType: \(value)"))
        }
    }
}

/// 决定哪些自然日参与计薪。
enum WorkDayRule: String, Codable, CaseIterable {
    case weekdaysOnly
    case everyday
    case custom

    var title: String {
        switch self {
        case .weekdaysOnly: return "仅工作日"
        case .everyday: return "每天都计薪"
        case .custom: return "自定义工作日"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.weekdaysOnly.rawValue, "仅工作日":
            self = .weekdaysOnly
        case Self.everyday.rawValue, "每天都计薪":
            self = .everyday
        case Self.custom.rawValue, "自定义工作日":
            self = .custom
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown WorkDayRule: \(value)"))
        }
    }
}

/// 特殊工作日的命中条件。规则只覆盖当天上下班时间，不改变当天是否计薪。
enum SpecialWorkdayRuleKind: String, Codable, CaseIterable, Identifiable {
    case dayBeforeRestDay
    case weekly
    case intervalWeeks
    case exactDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dayBeforeRestDay: return "节假日和周末的前一天"
        case .weekly: return "固定星期"
        case .intervalWeeks: return "隔周循环"
        case .exactDate: return "指定日期"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.dayBeforeRestDay.rawValue, "休息日前一天", "节假日和周末的前一天":
            self = .dayBeforeRestDay
        case Self.weekly.rawValue, "固定星期":
            self = .weekly
        case Self.intervalWeeks.rawValue, "隔周循环":
            self = .intervalWeeks
        case Self.exactDate.rawValue, "指定日期":
            self = .exactDate
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown SpecialWorkdayRuleKind: \(value)"))
        }
    }
}

/// 月薪结算覆盖的日期范围；这个周期只决定归属范围，不直接决定日薪折算分母。
enum SalaryCycleMode: String, Codable, CaseIterable, Identifiable {
    case naturalMonth
    case fixedMonthlyCycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .naturalMonth: return "自然月"
        case .fixedMonthlyCycle: return "固定周期"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.naturalMonth.rawValue, "自然月", "按自然月":
            self = .naturalMonth
        case Self.fixedMonthlyCycle.rawValue, "固定周期", "自定义周期", "按薪资周期":
            self = .fixedMonthlyCycle
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown SalaryCycleMode: \(value)"))
        }
    }
}

/// 月薪和日薪互相折算时使用的计薪日来源；周期范围由 SalaryCycleMode 独立决定。
enum MonthlySalaryCalculationMode: String, Codable, CaseIterable, Identifiable {
    case fixedAverage
    case salaryCycleWorkdays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixedAverage: return "固定天数"
        case .salaryCycleWorkdays: return "周期内工作天数"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.fixedAverage.rawValue, "固定指定天数", "固定天数":
            self = .fixedAverage
        case Self.salaryCycleWorkdays.rawValue, "按薪资周期计薪日", "周期内工作天数":
            self = .salaryCycleWorkdays
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown MonthlySalaryCalculationMode: \(value)"))
        }
    }
}

/// 补贴的发放口径。按日补贴直接进入日薪，按月补贴再决定是否平摊到日薪。
enum SalarySubsidyType: String, Codable, CaseIterable, Identifiable {
    case daily
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "按日补贴"
        case .monthly: return "按月补贴"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.daily.rawValue, "按日补贴":
            self = .daily
        case Self.monthly.rawValue, "按月补贴":
            self = .monthly
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown SalarySubsidyType: \(value)"))
        }
    }
}

/// 按月补贴的计入方式：只汇入月薪，或拆成每天收入参与实时累计。
enum MonthlySubsidyApplicationMode: String, Codable, CaseIterable, Identifiable {
    case addToMonthlySalary
    case spreadToDailySalary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addToMonthlySalary: return "加到月薪"
        case .spreadToDailySalary: return "平摊到每天"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.addToMonthlySalary.rawValue, "加到月薪":
            self = .addToMonthlySalary
        case Self.spreadToDailySalary.rawValue, "平摊到每天":
            self = .spreadToDailySalary
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown MonthlySubsidyApplicationMode: \(value)"))
        }
    }
}

/// 按月补贴平摊到每天时使用的分母来源。
enum MonthlySubsidyProrationMode: String, Codable, CaseIterable, Identifiable {
    case salaryCycleTotalDays
    case fixedDays
    case salaryCycleWorkdays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .salaryCycleTotalDays: return "周期内总天数"
        case .fixedDays: return "固定天数"
        case .salaryCycleWorkdays: return "周期内工作日天数"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.salaryCycleTotalDays.rawValue, "周期内总天数":
            self = .salaryCycleTotalDays
        case Self.fixedDays.rawValue, "固定天数":
            self = .fixedDays
        case Self.salaryCycleWorkdays.rawValue, "周期内工作日天数":
            self = .salaryCycleWorkdays
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown MonthlySubsidyProrationMode: \(value)"))
        }
    }
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

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case name
        case type
        case amount
        case monthlyApplicationMode
        case monthlyProrationMode
        case fixedProrationDays
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SalarySubsidy()

        id = container.decodeLossy(UUID.self, forKey: .id, default: defaults.id)
        enabled = container.decodeLossy(Bool.self, forKey: .enabled, default: defaults.enabled)
        name = container.decodeLossy(String.self, forKey: .name, default: defaults.name)
        type = container.decodeLossy(SalarySubsidyType.self, forKey: .type, default: defaults.type)
        amount = container.decodeLossy(Double.self, forKey: .amount, default: defaults.amount)
        monthlyApplicationMode = container.decodeLossy(MonthlySubsidyApplicationMode.self, forKey: .monthlyApplicationMode, default: defaults.monthlyApplicationMode)
        monthlyProrationMode = container.decodeLossy(MonthlySubsidyProrationMode.self, forKey: .monthlyProrationMode, default: defaults.monthlyProrationMode)
        fixedProrationDays = container.decodeLossy(Double.self, forKey: .fixedProrationDays, default: defaults.fixedProrationDays)
    }

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
    case rolling
    case bounce
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rolling: return "滚动"
        case .bounce: return "跳动"
        case .none: return "关闭"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.rolling.rawValue, "滚动":
            self = .rolling
        case Self.bounce.rawValue, "跳动":
            self = .bounce
        case Self.none.rawValue, "关闭":
            self = .none
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown StatusBarSalaryAnimationStyle: \(value)"))
        }
    }
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
    static let defaultSpecialWorkdayTime = TimeRange(startHour: 10, startMinute: 0, endHour: 18, endMinute: 0)
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

/// 单条特殊工作日规则。数组顺序就是优先级，第一条启用且命中的规则生效。
struct SpecialWorkdayRule: Codable, Equatable, Identifiable {
    static let intervalWeeksRange = 1...12

    var id: UUID = UUID()
    var enabled: Bool = true
    var name: String = "特殊工作日"
    var kind: SpecialWorkdayRuleKind = .dayBeforeRestDay
    var weekdays: Set<Int> = [5]
    var intervalWeeks: Int = 2
    var anchorDate: Date = Calendar.current.startOfDay(for: Date())
    var exactDate: Date = Calendar.current.startOfDay(for: Date())
    var workTime: TimeRange = .defaultSpecialWorkdayTime

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case name
        case kind
        case weekdays
        case intervalWeeks
        case anchorDate
        case exactDate
        case workTime
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SpecialWorkdayRule()

        id = container.decodeLossy(UUID.self, forKey: .id, default: defaults.id)
        enabled = container.decodeLossy(Bool.self, forKey: .enabled, default: defaults.enabled)
        name = container.decodeLossy(String.self, forKey: .name, default: defaults.name)
        kind = container.decodeLossy(SpecialWorkdayRuleKind.self, forKey: .kind, default: defaults.kind)
        weekdays = container.decodeLossy(Set<Int>.self, forKey: .weekdays, default: defaults.weekdays)
        intervalWeeks = container.decodeLossy(Int.self, forKey: .intervalWeeks, default: defaults.intervalWeeks)
        anchorDate = container.decodeLossy(Date.self, forKey: .anchorDate, default: defaults.anchorDate)
        exactDate = container.decodeLossy(Date.self, forKey: .exactDate, default: defaults.exactDate)
        workTime = container.decodeLossy(TimeRange.self, forKey: .workTime, default: defaults.workTime)
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "特殊工作日" : trimmed
    }

    mutating func normalize(calendar: Calendar = .current) {
        name = String(name.prefix(24))
        weekdays = Set(weekdays.filter { (1...7).contains($0) })
        if weekdays.isEmpty {
            weekdays = [5]
        }
        intervalWeeks = min(Self.intervalWeeksRange.upperBound, max(Self.intervalWeeksRange.lowerBound, intervalWeeks))
        anchorDate = calendar.startOfDay(for: anchorDate)
        exactDate = calendar.startOfDay(for: exactDate)
        workTime.normalizeClockFields()
    }
}

/// 当前计薪周期范围，以及该周期内按规则统计出的计薪日数量。
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

/// 配置兼容解码工具：新增字段缺失或单个字段损坏时使用默认值，避免整份配置被重置。
private extension KeyedDecodingContainer {
    func decodeLossy<Value: Decodable>(_ type: Value.Type, forKey key: Key, default defaultValue: Value) -> Value {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue
    }

    func decodeLossyOptional<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            return nil
        }
    }
}

/// App 的完整配置模型。新增字段必须提供兼容解码默认值，避免旧版本配置整体失效。
struct SalaryConfig: Codable, Equatable {
    static let refreshIntervalRange: ClosedRange<Double> = 0.5...3600
    static let workProgressGridIntervalOptions = [15, 30, 60, 120]
    static let workProgressDecimalPlacesRange = 0...3
    static let averageMonthlyWorkDays = 21.75
    static let monthlyWorkdaysRange: ClosedRange<Double> = 1...31
    static let yearlyWorkDays = 250.0
    static let defaultShortcutModifiers = Int(NSEvent.ModifierFlags([.option, .command]).rawValue)
    static let defaultOffTaskShortcutKeyCode: UInt16 = 7

    var salaryType: SalaryType = .monthly
    var salaryAmount: Double = 0
    var salaryCycleMode: SalaryCycleMode = .naturalMonth
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
    var specialWorkdayRules: [SpecialWorkdayRule] = []
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
    var popoverShowsOffTaskStatus: Bool = true
    var popoverShowsTodayOffTaskSalary: Bool = false
    var popoverShowsWeekOffTaskSalary: Bool = false
    var popoverShowsSalaryCycleOffTaskSalary: Bool = false
    var popoverShowsHistoricalOffTaskSalary: Bool = false
    var popoverShowsTodayOffTaskDuration: Bool = false
    var popoverShowsWeekOffTaskDuration: Bool = false
    var popoverShowsSalaryCycleOffTaskDuration: Bool = false
    var popoverShowsHistoricalOffTaskDuration: Bool = false
    var statusItemClickShowsPrivatePopover: Bool = true
    var statusBarShowsAppIcon: Bool = false
    var statusBarShowsCurrencySymbol: Bool = true
    var statusBarShowsOffTaskStatusIcon: Bool = true
    var statusBarSalaryAnimationStyle: StatusBarSalaryAnimationStyle = .rolling
    var moneyDecimalPlaces: Int = 2
    var shortcutActionSequence: [ShortcutAction] = ShortcutAction.defaultSequence
    var offTaskShortcutEnabled: Bool = true
    var offTaskShortcutModifiers: Int = Self.defaultShortcutModifiers
    var offTaskShortcutKeyCode: UInt16 = Self.defaultOffTaskShortcutKeyCode
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

    private enum CodingKeys: String, CodingKey {
        case salaryType
        case salaryAmount
        case salaryCycleMode
        case monthlySalaryCalculationMode
        case fixedMonthlyWorkdays
        case monthlySalaryCycleStartDay
        case subsidies
        case workTime
        case lunchBreakEnabled
        case lunchBreak
        case dinnerBreakEnabled
        case dinnerBreak
        case workDayRule
        case customWorkDays
        case specialWorkdayRules
        case launchAtLogin
        case shortcutModifiers
        case shortcutKeyCode
        case shortcutEnabled
        case statusBarShowsEarnings
        case popoverShowsCurrentEarnings
        case popoverShowsRemainingEarnings
        case popoverShowsWorkStatus
        case popoverShowsSecondSalary
        case popoverShowsMinuteSalary
        case popoverShowsHourlySalary
        case popoverShowsDailySalary
        case popoverShowsMonthlySalary
        case popoverShowsYearlySalary
        case popoverShowsWorkProgress
        case popoverShowsQuote
        case popoverShowsOffTaskStatus
        case popoverShowsTodayOffTaskSalary
        case popoverShowsWeekOffTaskSalary
        case popoverShowsSalaryCycleOffTaskSalary
        case popoverShowsHistoricalOffTaskSalary
        case popoverShowsTodayOffTaskDuration
        case popoverShowsWeekOffTaskDuration
        case popoverShowsSalaryCycleOffTaskDuration
        case popoverShowsHistoricalOffTaskDuration
        case statusItemClickShowsPrivatePopover
        case statusBarShowsAppIcon
        case statusBarShowsCurrencySymbol
        case statusBarShowsOffTaskStatusIcon
        case statusBarSalaryAnimationStyle
        case moneyDecimalPlaces
        case shortcutActionSequence
        case offTaskShortcutEnabled
        case offTaskShortcutModifiers
        case offTaskShortcutKeyCode
        case idleUsesLowFrequencyUpdates
        case refreshIntervalSeconds
        case lunchBreakShowsColor
        case dinnerBreakShowsColor
        case workProgressShowsGrid
        case workProgressShowsSegmentLabels
        case workProgressGridMinutes
        case workProgressDecimalPlaces
        case breakTimeCountsAsPaidWork
        case workProgressColorHex
        case lunchBreakColorHex
        case dinnerBreakColorHex
        case holidayPastColorHex
        case holidayFutureColorHex
        case popoverSalaryColorHex
        case statusBarSalaryColorHex
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SalaryConfig()

        salaryType = container.decodeLossy(SalaryType.self, forKey: .salaryType, default: defaults.salaryType)
        salaryAmount = container.decodeLossy(Double.self, forKey: .salaryAmount, default: defaults.salaryAmount)
        monthlySalaryCalculationMode = container.decodeLossy(MonthlySalaryCalculationMode.self, forKey: .monthlySalaryCalculationMode, default: defaults.monthlySalaryCalculationMode)
        fixedMonthlyWorkdays = container.decodeLossy(Double.self, forKey: .fixedMonthlyWorkdays, default: defaults.fixedMonthlyWorkdays)
        monthlySalaryCycleStartDay = container.decodeLossy(Int.self, forKey: .monthlySalaryCycleStartDay, default: defaults.monthlySalaryCycleStartDay)
        salaryCycleMode = container.decodeLossyOptional(SalaryCycleMode.self, forKey: .salaryCycleMode)
            ?? (monthlySalaryCycleStartDay == defaults.monthlySalaryCycleStartDay ? .naturalMonth : .fixedMonthlyCycle)
        subsidies = container.decodeLossy([SalarySubsidy].self, forKey: .subsidies, default: defaults.subsidies)
        workTime = container.decodeLossy(TimeRange.self, forKey: .workTime, default: defaults.workTime)
        lunchBreakEnabled = container.decodeLossy(Bool.self, forKey: .lunchBreakEnabled, default: defaults.lunchBreakEnabled)
        lunchBreak = container.decodeLossy(TimeRange.self, forKey: .lunchBreak, default: defaults.lunchBreak)
        dinnerBreakEnabled = container.decodeLossy(Bool.self, forKey: .dinnerBreakEnabled, default: defaults.dinnerBreakEnabled)
        dinnerBreak = container.decodeLossy(TimeRange.self, forKey: .dinnerBreak, default: defaults.dinnerBreak)
        workDayRule = container.decodeLossy(WorkDayRule.self, forKey: .workDayRule, default: defaults.workDayRule)
        customWorkDays = container.decodeLossy(Set<Int>.self, forKey: .customWorkDays, default: defaults.customWorkDays)
        specialWorkdayRules = container.decodeLossy([SpecialWorkdayRule].self, forKey: .specialWorkdayRules, default: defaults.specialWorkdayRules)
        launchAtLogin = container.decodeLossy(Bool.self, forKey: .launchAtLogin, default: defaults.launchAtLogin)
        shortcutModifiers = container.decodeLossy(Int.self, forKey: .shortcutModifiers, default: defaults.shortcutModifiers)
        shortcutKeyCode = container.decodeLossy(UInt16.self, forKey: .shortcutKeyCode, default: defaults.shortcutKeyCode)
        shortcutEnabled = container.decodeLossy(Bool.self, forKey: .shortcutEnabled, default: defaults.shortcutEnabled)
        statusBarShowsEarnings = container.decodeLossy(Bool.self, forKey: .statusBarShowsEarnings, default: defaults.statusBarShowsEarnings)
        popoverShowsCurrentEarnings = container.decodeLossy(Bool.self, forKey: .popoverShowsCurrentEarnings, default: defaults.popoverShowsCurrentEarnings)
        popoverShowsRemainingEarnings = container.decodeLossy(Bool.self, forKey: .popoverShowsRemainingEarnings, default: defaults.popoverShowsRemainingEarnings)
        popoverShowsWorkStatus = container.decodeLossy(Bool.self, forKey: .popoverShowsWorkStatus, default: defaults.popoverShowsWorkStatus)
        popoverShowsSecondSalary = container.decodeLossy(Bool.self, forKey: .popoverShowsSecondSalary, default: defaults.popoverShowsSecondSalary)
        popoverShowsMinuteSalary = container.decodeLossy(Bool.self, forKey: .popoverShowsMinuteSalary, default: defaults.popoverShowsMinuteSalary)
        popoverShowsHourlySalary = container.decodeLossy(Bool.self, forKey: .popoverShowsHourlySalary, default: defaults.popoverShowsHourlySalary)
        popoverShowsDailySalary = container.decodeLossy(Bool.self, forKey: .popoverShowsDailySalary, default: defaults.popoverShowsDailySalary)
        popoverShowsMonthlySalary = container.decodeLossy(Bool.self, forKey: .popoverShowsMonthlySalary, default: defaults.popoverShowsMonthlySalary)
        popoverShowsYearlySalary = container.decodeLossy(Bool.self, forKey: .popoverShowsYearlySalary, default: defaults.popoverShowsYearlySalary)
        popoverShowsWorkProgress = container.decodeLossy(Bool.self, forKey: .popoverShowsWorkProgress, default: defaults.popoverShowsWorkProgress)
        popoverShowsQuote = container.decodeLossy(Bool.self, forKey: .popoverShowsQuote, default: defaults.popoverShowsQuote)
        popoverShowsOffTaskStatus = container.decodeLossy(Bool.self, forKey: .popoverShowsOffTaskStatus, default: defaults.popoverShowsOffTaskStatus)
        popoverShowsTodayOffTaskSalary = container.decodeLossy(Bool.self, forKey: .popoverShowsTodayOffTaskSalary, default: defaults.popoverShowsTodayOffTaskSalary)
        popoverShowsWeekOffTaskSalary = container.decodeLossy(Bool.self, forKey: .popoverShowsWeekOffTaskSalary, default: defaults.popoverShowsWeekOffTaskSalary)
        popoverShowsSalaryCycleOffTaskSalary = container.decodeLossy(Bool.self, forKey: .popoverShowsSalaryCycleOffTaskSalary, default: defaults.popoverShowsSalaryCycleOffTaskSalary)
        popoverShowsHistoricalOffTaskSalary = container.decodeLossy(Bool.self, forKey: .popoverShowsHistoricalOffTaskSalary, default: defaults.popoverShowsHistoricalOffTaskSalary)
        popoverShowsTodayOffTaskDuration = container.decodeLossy(Bool.self, forKey: .popoverShowsTodayOffTaskDuration, default: defaults.popoverShowsTodayOffTaskDuration)
        popoverShowsWeekOffTaskDuration = container.decodeLossy(Bool.self, forKey: .popoverShowsWeekOffTaskDuration, default: defaults.popoverShowsWeekOffTaskDuration)
        popoverShowsSalaryCycleOffTaskDuration = container.decodeLossy(Bool.self, forKey: .popoverShowsSalaryCycleOffTaskDuration, default: defaults.popoverShowsSalaryCycleOffTaskDuration)
        popoverShowsHistoricalOffTaskDuration = container.decodeLossy(Bool.self, forKey: .popoverShowsHistoricalOffTaskDuration, default: defaults.popoverShowsHistoricalOffTaskDuration)
        statusItemClickShowsPrivatePopover = container.decodeLossy(Bool.self, forKey: .statusItemClickShowsPrivatePopover, default: defaults.statusItemClickShowsPrivatePopover)
        statusBarShowsAppIcon = container.decodeLossy(Bool.self, forKey: .statusBarShowsAppIcon, default: defaults.statusBarShowsAppIcon)
        statusBarShowsCurrencySymbol = container.decodeLossy(Bool.self, forKey: .statusBarShowsCurrencySymbol, default: defaults.statusBarShowsCurrencySymbol)
        statusBarShowsOffTaskStatusIcon = container.decodeLossy(Bool.self, forKey: .statusBarShowsOffTaskStatusIcon, default: defaults.statusBarShowsOffTaskStatusIcon)
        statusBarSalaryAnimationStyle = container.decodeLossy(StatusBarSalaryAnimationStyle.self, forKey: .statusBarSalaryAnimationStyle, default: defaults.statusBarSalaryAnimationStyle)
        moneyDecimalPlaces = container.decodeLossy(Int.self, forKey: .moneyDecimalPlaces, default: defaults.moneyDecimalPlaces)
        shortcutActionSequence = container.decodeLossy([ShortcutAction].self, forKey: .shortcutActionSequence, default: defaults.shortcutActionSequence)
        offTaskShortcutEnabled = container.decodeLossy(Bool.self, forKey: .offTaskShortcutEnabled, default: defaults.offTaskShortcutEnabled)
        offTaskShortcutModifiers = container.decodeLossy(Int.self, forKey: .offTaskShortcutModifiers, default: defaults.offTaskShortcutModifiers)
        offTaskShortcutKeyCode = container.decodeLossy(UInt16.self, forKey: .offTaskShortcutKeyCode, default: defaults.offTaskShortcutKeyCode)
        idleUsesLowFrequencyUpdates = container.decodeLossy(Bool.self, forKey: .idleUsesLowFrequencyUpdates, default: defaults.idleUsesLowFrequencyUpdates)
        refreshIntervalSeconds = container.decodeLossy(Double.self, forKey: .refreshIntervalSeconds, default: defaults.refreshIntervalSeconds)
        lunchBreakShowsColor = container.decodeLossy(Bool.self, forKey: .lunchBreakShowsColor, default: defaults.lunchBreakShowsColor)
        dinnerBreakShowsColor = container.decodeLossy(Bool.self, forKey: .dinnerBreakShowsColor, default: defaults.dinnerBreakShowsColor)
        workProgressShowsGrid = container.decodeLossy(Bool.self, forKey: .workProgressShowsGrid, default: defaults.workProgressShowsGrid)
        workProgressShowsSegmentLabels = container.decodeLossy(Bool.self, forKey: .workProgressShowsSegmentLabels, default: defaults.workProgressShowsSegmentLabels)
        workProgressGridMinutes = container.decodeLossy(Int.self, forKey: .workProgressGridMinutes, default: defaults.workProgressGridMinutes)
        workProgressDecimalPlaces = container.decodeLossy(Int.self, forKey: .workProgressDecimalPlaces, default: defaults.workProgressDecimalPlaces)
        breakTimeCountsAsPaidWork = container.decodeLossy(Bool.self, forKey: .breakTimeCountsAsPaidWork, default: defaults.breakTimeCountsAsPaidWork)
        workProgressColorHex = container.decodeLossy(String.self, forKey: .workProgressColorHex, default: defaults.workProgressColorHex)
        lunchBreakColorHex = container.decodeLossy(String.self, forKey: .lunchBreakColorHex, default: defaults.lunchBreakColorHex)
        dinnerBreakColorHex = container.decodeLossy(String.self, forKey: .dinnerBreakColorHex, default: defaults.dinnerBreakColorHex)
        holidayPastColorHex = container.decodeLossy(String.self, forKey: .holidayPastColorHex, default: defaults.holidayPastColorHex)
        holidayFutureColorHex = container.decodeLossy(String.self, forKey: .holidayFutureColorHex, default: defaults.holidayFutureColorHex)
        popoverSalaryColorHex = container.decodeLossy(String.self, forKey: .popoverSalaryColorHex, default: defaults.popoverSalaryColorHex)
        statusBarSalaryColorHex = container.decodeLossyOptional(String.self, forKey: .statusBarSalaryColorHex)
    }

    var shortcutDisplayString: String {
        shortcutDisplayString(modifiers: shortcutModifierFlags, keyCode: resolvedShortcutKeyCode)
    }

    var offTaskShortcutDisplayString: String {
        shortcutDisplayString(modifiers: offTaskShortcutModifierFlags, keyCode: resolvedOffTaskShortcutKeyCode)
    }

    private func shortcutDisplayString(modifiers flags: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        let keyDisplay = ShortcutKey.displayName(for: keyCode)
        return parts.joined() + keyDisplay
    }

    var shortcutModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(shortcutModifiers))
            .intersection(.shortcutModifierMask)
    }

    var resolvedShortcutKeyCode: UInt16 {
        shortcutKeyCode
    }

    var offTaskShortcutModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(offTaskShortcutModifiers))
            .intersection(.shortcutModifierMask)
    }

    var resolvedOffTaskShortcutKeyCode: UInt16 {
        offTaskShortcutKeyCode
    }

    var displaysEarningsInStatusBar: Bool {
        statusBarShowsEarnings
    }

    var statusBarDisplaysOffTaskStatusIcon: Bool {
        statusBarShowsOffTaskStatusIcon
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

    var popoverDisplaysOffTaskStatus: Bool {
        popoverShowsOffTaskStatus
    }

    var popoverDisplaysTodayOffTaskSalary: Bool {
        popoverShowsTodayOffTaskSalary
    }

    var popoverDisplaysWeekOffTaskSalary: Bool {
        popoverShowsWeekOffTaskSalary
    }

    var popoverDisplaysSalaryCycleOffTaskSalary: Bool {
        popoverShowsSalaryCycleOffTaskSalary
    }

    var popoverDisplaysHistoricalOffTaskSalary: Bool {
        popoverShowsHistoricalOffTaskSalary
    }

    var popoverDisplaysTodayOffTaskDuration: Bool {
        popoverShowsTodayOffTaskDuration
    }

    var popoverDisplaysWeekOffTaskDuration: Bool {
        popoverShowsWeekOffTaskDuration
    }

    var popoverDisplaysSalaryCycleOffTaskDuration: Bool {
        popoverShowsSalaryCycleOffTaskDuration
    }

    var popoverDisplaysHistoricalOffTaskDuration: Bool {
        popoverShowsHistoricalOffTaskDuration
    }

    var popoverDisplaysAnyOffTaskSalaryMetric: Bool {
        popoverDisplaysTodayOffTaskSalary
            || popoverDisplaysWeekOffTaskSalary
            || popoverDisplaysSalaryCycleOffTaskSalary
            || popoverDisplaysHistoricalOffTaskSalary
    }

    var popoverDisplaysAnyOffTaskDurationMetric: Bool {
        popoverDisplaysTodayOffTaskDuration
            || popoverDisplaysWeekOffTaskDuration
            || popoverDisplaysSalaryCycleOffTaskDuration
            || popoverDisplaysHistoricalOffTaskDuration
    }

    var popoverDisplaysAnyOffTaskMetric: Bool {
        popoverDisplaysAnyOffTaskSalaryMetric
            || popoverDisplaysAnyOffTaskDurationMetric
    }

    var popoverDisplaysAnyOffTaskInformation: Bool {
        popoverDisplaysOffTaskStatus || popoverDisplaysAnyOffTaskMetric
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
            || popoverDisplaysAnyOffTaskInformation
            || popoverDisplaysQuote
    }

    var resolvedMonthlySalaryCalculationMode: MonthlySalaryCalculationMode {
        monthlySalaryCalculationMode
    }

    var resolvedSalaryCycleMode: SalaryCycleMode {
        salaryCycleMode
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
        workTimelineStartMinutes(for: workTime)
    }

    var workTimelineEndMinutes: Int {
        workTimelineEndMinutes(for: workTime)
    }

    var workDurationMinutes: Int {
        workDurationMinutes(for: workTime)
    }

    func workTimelineStartMinutes(for workTime: TimeRange) -> Int {
        workTime.startMinutes
    }

    func workTimelineEndMinutes(for workTime: TimeRange) -> Int {
        workTime.startMinutes + workTime.durationMinutes
    }

    func workDurationMinutes(for workTime: TimeRange) -> Int {
        workTime.durationMinutes
    }

    /// 特殊工作日只覆盖命中当天的上下班时间，休息、补贴和月薪/年薪折算仍沿用基础配置。
    func effectiveWorkTime(on date: Date, calendar: Calendar = .current) -> TimeRange {
        guard let rule = matchingSpecialWorkdayRule(on: date, calendar: calendar),
              rule.workTime.durationMinutes > 0 else {
            return workTime
        }
        return rule.workTime
    }

    func effectiveDailySalary(on date: Date, calendar: Calendar = .current) -> Double {
        dailySalary
    }

    func salaryPerSecond(on date: Date, calendar: Calendar = .current) -> Double {
        salaryPerSecond(workTime: effectiveWorkTime(on: date, calendar: calendar))
    }

    func salaryPerMinute(on date: Date, calendar: Calendar = .current) -> Double {
        salaryPerSecond(on: date, calendar: calendar) * 60
    }

    func salaryPerHour(on date: Date, calendar: Calendar = .current) -> Double {
        salaryPerSecond(on: date, calendar: calendar) * 3600
    }

    func paidWorkMinutes(on date: Date, calendar: Calendar = .current) -> Int {
        paidWorkMinutes(workTime: effectiveWorkTime(on: date, calendar: calendar))
    }

    func matchingSpecialWorkdayRule(on date: Date, calendar: Calendar = .current) -> SpecialWorkdayRule? {
        let day = calendar.startOfDay(for: date)
        guard shouldCountSalary(on: day, calendar: calendar) else { return nil }

        return specialWorkdayRules.first { rule in
            rule.enabled && specialWorkdayRule(rule, matches: day, calendar: calendar)
        }
    }

    /// 返回指定日期所在的计薪周期，支持每月非 1 号起算和 2 月短月兜底。
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

    private func specialWorkdayRule(_ rule: SpecialWorkdayRule, matches day: Date, calendar: Calendar) -> Bool {
        switch rule.kind {
        case .dayBeforeRestDay:
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
            return !shouldCountSalary(on: nextDay, calendar: calendar)
        case .weekly:
            return rule.weekdays.contains(mappedWeekday(for: day, calendar: calendar))
        case .intervalWeeks:
            guard rule.weekdays.contains(mappedWeekday(for: day, calendar: calendar)) else { return false }
            let interval = min(SpecialWorkdayRule.intervalWeeksRange.upperBound, max(SpecialWorkdayRule.intervalWeeksRange.lowerBound, rule.intervalWeeks))
            let dateWeekStart = weekStart(containing: day, calendar: calendar)
            let anchorWeekStart = weekStart(containing: rule.anchorDate, calendar: calendar)
            let dayDelta = calendar.dateComponents([.day], from: anchorWeekStart, to: dateWeekStart).day ?? 0
            guard dayDelta % 7 == 0 else { return false }
            return (dayDelta / 7) % interval == 0
        case .exactDate:
            return calendar.isDate(day, inSameDayAs: rule.exactDate)
        }
    }

    private func mappedWeekday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = mappedWeekday(for: day, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1 - weekday, to: day) ?? day
    }

    func clampedIntervalsInWorkTime(for range: TimeRange) -> [(startMinutes: Int, endMinutes: Int)] {
        clampedIntervalsInWorkTime(for: range, workTime: workTime)
    }

    func clampedIntervalsInWorkTime(for range: TimeRange, workTime: TimeRange) -> [(startMinutes: Int, endMinutes: Int)] {
        let workStart = workTimelineStartMinutes(for: workTime)
        let workEnd = workTimelineEndMinutes(for: workTime)
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
        breakIntervalsWithinWorkTime(workTime: workTime)
    }

    func breakIntervalsWithinWorkTime(workTime: TimeRange) -> [(startMinutes: Int, endMinutes: Int)] {
        guard workDurationMinutes(for: workTime) > 0 else { return [] }

        var intervals: [(startMinutes: Int, endMinutes: Int)] = []

        if usesLunchBreak {
            intervals.append(contentsOf: clampedIntervalsInWorkTime(for: lunchBreak, workTime: workTime))
        }
        if dinnerBreakEnabled {
            intervals.append(contentsOf: clampedIntervalsInWorkTime(for: dinnerBreak, workTime: workTime))
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
        breakMinutesWithinWorkTime(workTime: workTime)
    }

    func breakMinutesWithinWorkTime(workTime: TimeRange) -> Int {
        breakIntervalsWithinWorkTime(workTime: workTime).reduce(0) { total, interval in
            total + interval.endMinutes - interval.startMinutes
        }
    }

    var workMinutesExcludingBreaks: Int {
        workMinutesExcludingBreaks(workTime: workTime)
    }

    func workMinutesExcludingBreaks(workTime: TimeRange) -> Int {
        max(0, workDurationMinutes(for: workTime) - breakMinutesWithinWorkTime(workTime: workTime))
    }

    var paidWorkMinutes: Int {
        paidWorkMinutes(workTime: workTime)
    }

    func paidWorkMinutes(workTime: TimeRange) -> Int {
        countsBreakTimeAsPaidWork
            ? max(0, workDurationMinutes(for: workTime))
            : workMinutesExcludingBreaks(workTime: workTime)
    }

    var salaryPerSecond: Double {
        salaryPerSecond(workTime: workTime)
    }

    private func salaryPerSecond(workTime: TimeRange) -> Double {
        let workSeconds = Double(paidWorkMinutes(workTime: workTime)) * 60
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
        specialWorkdayRules = specialWorkdayRules.map { rule in
            var normalized = rule
            normalized.normalize()
            return normalized
        }
        fixedMonthlyWorkdays = min(Self.monthlyWorkdaysRange.upperBound, max(Self.monthlyWorkdaysRange.lowerBound, fixedMonthlyWorkdays.isFinite ? fixedMonthlyWorkdays : Self.averageMonthlyWorkDays))
        monthlySalaryCycleStartDay = min(31, max(1, monthlySalaryCycleStartDay))
        shortcutModifiers = Int(shortcutModifierFlags.rawValue)
        if !ShortcutKey.isRecordable(shortcutKeyCode) {
            shortcutKeyCode = ShortcutKey.defaultKeyCode
        }
        offTaskShortcutModifiers = Int(offTaskShortcutModifierFlags.rawValue)
        if !ShortcutKey.isRecordable(offTaskShortcutKeyCode) {
            offTaskShortcutKeyCode = Self.defaultOffTaskShortcutKeyCode
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

        let day = resolvedSalaryCycleMode == .naturalMonth ? 1 : min(resolvedMonthlySalaryCycleStartDay, days.count)
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

/// 统一读写用户配置。
final class SalaryConfigManager: ObservableObject {
    static let shared = SalaryConfigManager()
    private static let failedConfigBackupKey = "salary_config_decode_failed_backup"
    private static let failedConfigErrorKey = "salary_config_decode_failed_error"

    @Published var config: SalaryConfig {
        didSet {
            normalizeAndSave()
        }
    }

    private let defaults = UserDefaults.standard
    private let configKey = "salary_config"

    init() {
        if let data = defaults.data(forKey: configKey) {
            do {
                let decoded = try JSONDecoder().decode(SalaryConfig.self, from: data)
                var normalized = decoded
                normalized.normalize()
                config = normalized
                save()
            } catch {
                Self.backupFailedConfig(data, error: error, defaults: defaults)
                config = SalaryConfig()
            }
        } else {
            config = SalaryConfig()
            save()
        }
    }

    private static func backupFailedConfig(_ data: Data, error: Error, defaults: UserDefaults) {
        defaults.set(data, forKey: failedConfigBackupKey)
        defaults.set(String(describing: error), forKey: failedConfigErrorKey)
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
