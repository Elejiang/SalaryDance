import Foundation

/// 自动获取并缓存中国节假日 / 调休日，供“仅工作日”和动态薪资周期使用。
final class ChineseHolidays: ObservableObject {
    static let shared = ChineseHolidays()

    @Published var holidays: Set<String> = []
    @Published var extraWorkdays: Set<String> = []
    @Published var holidayNames: [String: String] = [:]
    @Published var extraWorkdayNames: [String: String] = [:]
    @Published var isLoading = false
    @Published var lastError: String?

    private let defaults = UserDefaults.standard
    private let holidaysKey = "chinese_holidays_data_by_year"
    private let cacheRefreshInterval: TimeInterval = 7 * 24 * 60 * 60
    private var cachedHolidaysByYear: [Int: CachedHolidays] = [:]
    private var loadingYears = Set<Int>()

    init() {
        loadFromCache()
        // 避免在 SwiftUI 创建观察对象的视图更新过程中同步发布 isLoading。
        DispatchQueue.main.async { [weak self] in
            self?.fetchDefaultYearsIfNeeded()
        }
    }

    /// 判断某天是否为法定节假日。
    func isHoliday(_ date: Date) -> Bool {
        holidays.contains(formatDate(date))
    }

    /// 判断某天是否应视为工作日；调休日优先级高于周末。
    func isWorkday(_ date: Date) -> Bool {
        let key = formatDate(date)
        if extraWorkdays.contains(key) { return true }
        if holidays.contains(key) { return false }
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday >= 2 && weekday <= 6
    }

    /// 设置页手动重试入口，重新拉取默认年份范围。
    func retryFetch() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for year in self.defaultYearsToLoad() {
                self.fetchFromAPI(year: year)
            }
        }
    }

    /// 动态薪资周期可能跨年，按需补齐涉及年份的节假日数据。
    func ensureYearsLoaded(_ years: Set<Int>) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for year in years {
                self.fetchIfNeeded(year: year)
            }
        }
    }

    private func loadFromCache() {
        if let data = defaults.data(forKey: holidaysKey),
           let cached = try? JSONDecoder().decode([CachedHolidays].self, from: data) {
            cachedHolidaysByYear = Dictionary(uniqueKeysWithValues: cached.map { ($0.year, $0) })
            rebuildPublishedCache()
        }
    }

    private func saveToCache() {
        if let encoded = try? JSONEncoder().encode(Array(cachedHolidaysByYear.values)) {
            defaults.set(encoded, forKey: holidaysKey)
        }
    }

    private func fetchDefaultYearsIfNeeded() {
        for year in defaultYearsToLoad() {
            fetchIfNeeded(year: year)
        }
    }

    /// 缓存超过刷新间隔时自动更新，避免每次启动都访问网络。
    private func fetchIfNeeded(year: Int) {
        let cached = cachedHolidaysByYear[year]
        let isStale = cached?.fetchedAt.map { Date().timeIntervalSince($0) > cacheRefreshInterval } ?? true
        if cached == nil || isStale {
            fetchFromAPI(year: year)
        }
    }

    /// 从 timor.tech 拉取节假日数据；失败信息直接显示在设置页。
    private func fetchFromAPI(year: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.fetchFromAPI(year: year)
            }
            return
        }

        guard !loadingYears.contains(year) else { return }
        loadingYears.insert(year)
        updateLoadingState()
        lastError = nil

        guard let url = URL(string: "https://timor.tech/api/holiday/year/\(year)") else {
            loadingYears.remove(year)
            updateLoadingState()
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.loadingYears.remove(year)
                self?.updateLoadingState()
                if let error = error {
                    self?.lastError = "\(year) 年节假日获取失败：\(error.localizedDescription)"
                    return
                }
                guard let data = data else { return }
                self?.parseAPIResponse(data, year: year)
            }
        }.resume()
    }

    /// API 返回的日期可能是 MM-dd，入库前统一补全年份。
    private func parseAPIResponse(_ data: Data, year: Int) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int, code == 0,
                  let holidayDict = json["holiday"] as? [String: Any] else {
                lastError = "数据格式异常"
                return
            }

            var hols: [String] = []
            var works: [String] = []
            var holNames: [String: String] = [:]
            var workNames: [String: String] = [:]

            for (dateStr, info) in holidayDict {
                guard let detail = info as? [String: Any] else { continue }
                let isHoliday = detail["holiday"] as? Bool ?? false
                let normalizedDate = normalizedDateString(dateStr, year: year)
                let name = detail["name"] as? String
                if isHoliday {
                    hols.append(normalizedDate)
                    if let name, !name.isEmpty {
                        holNames[normalizedDate] = name
                    }
                } else {
                    works.append(normalizedDate)
                    if let name, !name.isEmpty {
                        workNames[normalizedDate] = name
                    }
                }
            }

            cachedHolidaysByYear[year] = CachedHolidays(
                year: year,
                holidays: hols,
                extraWorkdays: works,
                holidayNames: holNames,
                extraWorkdayNames: workNames,
                fetchedAt: Date()
            )
            rebuildPublishedCache()
            saveToCache()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 默认加载当前年；年初/年末额外加载相邻年份，覆盖跨年薪资周期。
    private func defaultYearsToLoad() -> Set<Int> {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        var years: Set<Int> = [year]
        if month == 1 {
            years.insert(year - 1)
        }
        if month == 12 {
            years.insert(year + 1)
        }
        return years
    }

    /// 从按年缓存重建扁平集合，便于计算逻辑 O(1) 查询。
    private func rebuildPublishedCache() {
        let cached = cachedHolidaysByYear.values
        holidays = Set(cached.flatMap { data in
            data.holidays.map { normalizedDateString($0, year: data.year) }
        })
        extraWorkdays = Set(cached.flatMap { data in
            data.extraWorkdays.map { normalizedDateString($0, year: data.year) }
        })
        holidayNames = cached.reduce(into: [:]) { result, data in
            result.merge(normalizedNames(data.holidayNames ?? [:], year: data.year)) { _, new in new }
        }
        extraWorkdayNames = cached.reduce(into: [:]) { result, data in
            result.merge(normalizedNames(data.extraWorkdayNames ?? [:], year: data.year)) { _, new in new }
        }
    }

    private func updateLoadingState() {
        isLoading = !loadingYears.isEmpty
    }

    private func normalizedNames(_ names: [String: String], year: Int) -> [String: String] {
        Dictionary(uniqueKeysWithValues: names.map { key, value in
            (normalizedDateString(key, year: year), value)
        })
    }

    private func normalizedDateString(_ value: String, year: Int) -> String {
        if value.count == 5, value[value.index(value.startIndex, offsetBy: 2)] == "-" {
            return "\(year)-\(value)"
        }
        return value
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// 单年份节假日缓存。字段保持简单 Codable，避免 NSSecureCoding 相关风险。
struct CachedHolidays: Codable {
    let year: Int
    let holidays: [String]
    let extraWorkdays: [String]
    let holidayNames: [String: String]?
    let extraWorkdayNames: [String: String]?
    let fetchedAt: Date?
}
