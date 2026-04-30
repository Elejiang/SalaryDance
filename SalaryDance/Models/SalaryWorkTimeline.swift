import Foundation

/// 展开后的单个工作日窗口，跨夜班次的 end 会落在次日。
struct SalaryWorkWindow: Equatable, Identifiable {
    var id: Date { workday }

    let workday: Date
    let start: Date
    let end: Date
    let workTime: TimeRange
    let dailySalary: Double
    let salaryPerSecond: Double
    let paidWorkMinutes: Int
}

/// 统一生成真实工作窗口和有效计薪区间，供实时收入与摸鱼统计使用同一套时间边界。
enum SalaryWorkTimeline {
    static func workWindow(startingOn day: Date, config: SalaryConfig, calendar: Calendar = .current) -> SalaryWorkWindow? {
        let workday = calendar.startOfDay(for: day)
        guard config.shouldCountSalary(on: workday, calendar: calendar) else { return nil }

        let workTime = config.effectiveWorkTime(on: workday, calendar: calendar)
        let workDurationMinutes = config.workDurationMinutes(for: workTime)
        guard workDurationMinutes > 0 else { return nil }

        guard let start = calendar.date(byAdding: .minute, value: workTime.startMinutes, to: workday),
              let end = calendar.date(byAdding: .minute, value: workTime.startMinutes + workDurationMinutes, to: workday) else {
            return nil
        }

        return SalaryWorkWindow(
            workday: workday,
            start: start,
            end: end,
            workTime: workTime,
            dailySalary: config.effectiveDailySalary(on: workday, calendar: calendar),
            salaryPerSecond: config.salaryPerSecond(on: workday, calendar: calendar),
            paidWorkMinutes: config.paidWorkMinutes(workTime: workTime)
        )
    }

    static func activeWindow(containing date: Date, config: SalaryConfig, calendar: Calendar = .current) -> SalaryWorkWindow? {
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        for day in [yesterday, today] {
            guard let window = workWindow(startingOn: day, config: config, calendar: calendar) else { continue }
            if date >= window.start, date < window.end {
                return window
            }
        }

        return nil
    }

    static func paidInterval(containing date: Date, in window: SalaryWorkWindow, config: SalaryConfig, calendar: Calendar = .current) -> DateInterval? {
        paidIntervals(in: window, config: config, calendar: calendar).first { interval in
            date >= interval.start && date < interval.end
        }
    }

    static func unpaidBreakName(containing date: Date, in window: SalaryWorkWindow, config: SalaryConfig, calendar: Calendar = .current) -> String? {
        guard !config.countsBreakTimeAsPaidWork else { return nil }

        return namedBreakIntervals(in: window, config: config, calendar: calendar).first { namedInterval in
            date >= namedInterval.interval.start && date < namedInterval.interval.end
        }?.name
    }

    static func relevantWorkday(for date: Date, config: SalaryConfig, calendar: Calendar = .current) -> Date {
        if let activeWindow = activeWindow(containing: date, config: config, calendar: calendar) {
            return activeWindow.workday
        }

        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let todayWindow = workWindow(startingOn: today, config: config, calendar: calendar)

        // 跨夜班次刚结束后，弹窗里的“今日摸鱼”和下班总结仍应指向刚收工的工作日。
        if let yesterdayWindow = workWindow(startingOn: yesterday, config: config, calendar: calendar),
           yesterdayWindow.end > today,
           date >= yesterdayWindow.end,
           todayWindow.map({ date < $0.start }) ?? true {
            return yesterdayWindow.workday
        }

        return today
    }

    /// 返回窗口内真正会产生收入的时间段；休息时间不计薪时会从工作窗口中扣掉。
    static func paidIntervals(in window: SalaryWorkWindow, config: SalaryConfig, calendar: Calendar = .current) -> [DateInterval] {
        let workStart = config.workTimelineStartMinutes(for: window.workTime)
        let workEnd = config.workTimelineEndMinutes(for: window.workTime)
        guard workEnd > workStart else { return [] }

        var minuteIntervals = [(start: workStart, end: workEnd)]
        if !config.countsBreakTimeAsPaidWork {
            for breakInterval in config.breakIntervalsWithinWorkTime(workTime: window.workTime) {
                minuteIntervals = subtract(breakInterval, from: minuteIntervals)
            }
        }

        return minuteIntervals.compactMap { interval in
            guard interval.end > interval.start,
                  let start = calendar.date(byAdding: .minute, value: interval.start - workStart, to: window.start),
                  let end = calendar.date(byAdding: .minute, value: interval.end - workStart, to: window.start),
                  end > start else {
                return nil
            }
            return DateInterval(start: start, end: end)
        }
    }

    static func paidOverlapSeconds(from start: Date, to end: Date, in window: SalaryWorkWindow, config: SalaryConfig, calendar: Calendar = .current) -> TimeInterval {
        guard end > start else { return 0 }

        return paidIntervals(in: window, config: config, calendar: calendar).reduce(0) { total, interval in
            let overlapStart = max(start, interval.start)
            let overlapEnd = min(end, interval.end)
            guard overlapEnd > overlapStart else { return total }
            return total + overlapEnd.timeIntervalSince(overlapStart)
        }
    }

    private static func namedBreakIntervals(in window: SalaryWorkWindow, config: SalaryConfig, calendar: Calendar) -> [(name: String, interval: DateInterval)] {
        var minuteIntervals: [(name: String, startMinutes: Int, endMinutes: Int)] = []

        if config.usesLunchBreak {
            minuteIntervals.append(contentsOf: config.clampedIntervalsInWorkTime(for: config.lunchBreak, workTime: window.workTime).map { interval in
                (name: "午休", startMinutes: interval.startMinutes, endMinutes: interval.endMinutes)
            })
        }

        if config.dinnerBreakEnabled {
            minuteIntervals.append(contentsOf: config.clampedIntervalsInWorkTime(for: config.dinnerBreak, workTime: window.workTime).map { interval in
                (name: "晚饭", startMinutes: interval.startMinutes, endMinutes: interval.endMinutes)
            })
        }

        let workStart = config.workTimelineStartMinutes(for: window.workTime)
        return minuteIntervals.compactMap { interval in
            guard interval.endMinutes > interval.startMinutes,
                  let start = calendar.date(byAdding: .minute, value: interval.startMinutes - workStart, to: window.start),
                  let end = calendar.date(byAdding: .minute, value: interval.endMinutes - workStart, to: window.start),
                  end > start else {
                return nil
            }

            return (name: interval.name, interval: DateInterval(start: start, end: end))
        }
    }

    /// 从一组有序分钟区间里扣除一个休息区间，保留扣除后的工作片段。
    private static func subtract(
        _ excluded: (startMinutes: Int, endMinutes: Int),
        from intervals: [(start: Int, end: Int)]
    ) -> [(start: Int, end: Int)] {
        intervals.flatMap { interval -> [(start: Int, end: Int)] in
            let overlapStart = max(interval.start, excluded.startMinutes)
            let overlapEnd = min(interval.end, excluded.endMinutes)
            guard overlapEnd > overlapStart else { return [interval] }

            var result: [(start: Int, end: Int)] = []
            if interval.start < overlapStart {
                result.append((interval.start, overlapStart))
            }
            if overlapEnd < interval.end {
                result.append((overlapEnd, interval.end))
            }
            return result
        }
    }
}
