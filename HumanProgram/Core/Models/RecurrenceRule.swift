import Foundation

public enum RecurrenceFrequency: String, Codable, Hashable, CaseIterable, Sendable {
    case everyDay
    case weekdays        // Mon–Fri (weekday 2–6)
    case weekends        // Sat–Sun (weekday 1, 7)
    case selectedWeekdays
    case everyNDays
    case everyNWeeks
    case everyOtherDay
    case fourDaySplit    // repeating 4-day exercise cycle (workout A, workout B, workout C, rest)
}

public struct RecurrenceRule: Codable, Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    public var weekdays: [Int]       // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    public var interval: Int         // for everyNDays/everyNWeeks (must be >= 1)
    public var anchorDate: Date?
    public var startDate: Date?
    public var endDate: Date?
    public var occurrenceLimit: Int?

    public init(
        frequency: RecurrenceFrequency,
        weekdays: [Int] = [],
        interval: Int = 1,
        anchorDate: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        occurrenceLimit: Int? = nil
    ) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.interval = max(1, interval)
        self.anchorDate = anchorDate
        self.startDate = startDate
        self.endDate = endDate
        self.occurrenceLimit = occurrenceLimit
    }

    // MARK: - Convenience Factories

    public static func daily() -> RecurrenceRule {
        RecurrenceRule(frequency: .everyDay)
    }

    public static func weekdays() -> RecurrenceRule {
        RecurrenceRule(frequency: .weekdays)
    }

    public static func weekends() -> RecurrenceRule {
        RecurrenceRule(frequency: .weekends)
    }

    public static func on(_ weekdays: [Int]) -> RecurrenceRule {
        RecurrenceRule(frequency: .selectedWeekdays, weekdays: weekdays)
    }

    public static func everyNDays(_ n: Int, anchor: Date) -> RecurrenceRule {
        RecurrenceRule(frequency: .everyNDays, interval: n, anchorDate: anchor)
    }

    public static func everyNWeeks(_ n: Int, on weekdays: [Int], anchor: Date) -> RecurrenceRule {
        RecurrenceRule(frequency: .everyNWeeks, weekdays: weekdays, interval: n, anchorDate: anchor)
    }

    // MARK: - Core Matching

    /// Returns true if this rule fires on the given date.
    /// Does NOT check occurrenceLimit (caller counts occurrences if needed).
    /// DOES check startDate/endDate bounds.
    public func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        // Check date range bounds
        let dayStart = calendar.startOfDay(for: date)

        if let start = startDate {
            let startDay = calendar.startOfDay(for: start)
            if dayStart < startDay { return false }
        }

        if let end = endDate {
            let endDay = calendar.startOfDay(for: end)
            if dayStart > endDay { return false }
        }

        let weekday = calendar.component(.weekday, from: date)

        switch frequency {
        case .everyDay:
            return true

        case .weekdays:
            // Monday=2 through Friday=6
            return (2...6).contains(weekday)

        case .weekends:
            // Sunday=1, Saturday=7
            return weekday == 1 || weekday == 7

        case .selectedWeekdays:
            return self.weekdays.contains(weekday)

        case .everyNDays:
            let anchor = resolvedAnchor(calendar: calendar)
            let days = daysBetween(anchor, and: date, calendar: calendar)
            guard days >= 0 else { return false }
            return days % max(1, interval) == 0

        case .everyNWeeks:
            let anchor = resolvedAnchor(calendar: calendar)
            let days = daysBetween(anchor, and: date, calendar: calendar)
            guard days >= 0 else { return false }
            // Count whole weeks between the anchor's week and the date's week, both
            // aligned to the start of their (Sunday-based) week. This fires EVERY
            // selected weekday in a qualifying week — not just the anchor's own
            // weekday, which the old `remainder == 0` gate incorrectly required.
            let anchorWeekStart = startOfWeek(anchor, calendar: calendar)
            let dateWeekStart = startOfWeek(dayStart, calendar: calendar)
            let weeks = daysBetween(anchorWeekStart, and: dateWeekStart, calendar: calendar) / 7
            guard weeks % max(1, interval) == 0 else { return false }
            return self.weekdays.contains(weekday)

        case .everyOtherDay:
            let anchor = resolvedAnchor(calendar: calendar)
            let days = daysBetween(anchor, and: date, calendar: calendar)
            guard days >= 0 else { return false }
            return days % 2 == 0

        case .fourDaySplit:
            // 4-day cycle: day 0 = Workout A, day 1 = Workout B, day 2 = Workout C, day 3 = Rest
            // Active positions are 0, 1, 2 (not rest day 3)
            let anchor = resolvedAnchor(calendar: calendar)
            let days = daysBetween(anchor, and: date, calendar: calendar)
            guard days >= 0 else { return false }
            let cycleIndex = days % 4
            return cycleIndex != 3
        }
    }

    // MARK: - Private Helpers

    /// Returns the anchor to use for interval calculations.
    /// Falls back to startDate, then Unix epoch start if neither is set.
    private func resolvedAnchor(calendar: Calendar) -> Date {
        if let anchor = anchorDate {
            return calendar.startOfDay(for: anchor)
        }
        if let start = startDate {
            return calendar.startOfDay(for: start)
        }
        // Unix epoch start: 1970-01-01
        return Date(timeIntervalSince1970: 0)
    }

    /// Returns the number of whole days between two dates (start of day to start of day).
    /// Returns a negative value if `to` is before `from`.
    private func daysBetween(_ from: Date, and to: Date, calendar: Calendar) -> Int {
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        let components = calendar.dateComponents([.day], from: fromDay, to: toDay)
        return components.day ?? 0
    }

    /// Start of the (Sunday-based) week containing `date`, using the app's
    /// 1=Sun … 7=Sat weekday encoding. Locale-independent (always Sunday-aligned).
    private func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)   // 1=Sun … 7=Sat
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: dayStart) ?? dayStart
    }
}
