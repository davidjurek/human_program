import Foundation

/// A pure, stateless struct providing higher-level helpers built on top of RecurrenceRule.
/// No SwiftData, no UIKit dependencies.
public struct RecurrenceEngine: Sendable {

    public init() {}

    // MARK: - matches(_:on:calendar:)

    /// Returns true if the rule matches the given date.
    /// Handles occurrenceLimit by counting prior occurrences since startDate/anchorDate.
    public func matches(_ rule: RecurrenceRule, on date: Date, calendar: Calendar = .current) -> Bool {
        // First check base frequency match (includes startDate/endDate bounds)
        guard rule.occurs(on: date, calendar: calendar) else { return false }

        // Check occurrence limit if set
        if let limit = rule.occurrenceLimit {
            let priorCount = countOccurrences(of: rule, before: date, calendar: calendar)
            if priorCount >= limit {
                return false
            }
        }

        return true
    }

    // MARK: - nextOccurrence(of:from:withinDays:calendar:)

    /// Returns the next date >= 'from' where the rule fires, up to 'limit' days ahead.
    /// Returns nil if none found within limit.
    public func nextOccurrence(
        of rule: RecurrenceRule,
        from: Date,
        withinDays limit: Int = 365,
        calendar: Calendar = .current
    ) -> Date? {
        let startDay = calendar.startOfDay(for: from)

        for offset in 0..<limit {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                continue
            }
            if matches(rule, on: candidate, calendar: calendar) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - occurrences(of:in:calendar:)

    /// Returns all dates in [start...end] where the rule fires.
    public func occurrences(
        of rule: RecurrenceRule,
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [Date] {
        var results: [Date] = []

        let startDay = calendar.startOfDay(for: range.lowerBound)
        let endDay = calendar.startOfDay(for: range.upperBound)

        // Count days in range to iterate
        let components = calendar.dateComponents([.day], from: startDay, to: endDay)
        guard let totalDays = components.day, totalDays >= 0 else { return [] }

        for offset in 0...totalDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                continue
            }
            if matches(rule, on: candidate, calendar: calendar) {
                results.append(candidate)
            }
        }

        return results
    }

    // MARK: - Private Helpers

    /// Counts how many times the rule fires from its origin up to (but not including) the given date.
    /// Origin is rule.startDate ?? rule.anchorDate ?? epoch start.
    private func countOccurrences(
        of rule: RecurrenceRule,
        before date: Date,
        calendar: Calendar
    ) -> Int {
        // Determine the counting origin
        let origin: Date
        if let start = rule.startDate {
            origin = calendar.startOfDay(for: start)
        } else if let anchor = rule.anchorDate {
            origin = calendar.startOfDay(for: anchor)
        } else {
            origin = Date(timeIntervalSince1970: 0)
        }

        let targetDay = calendar.startOfDay(for: date)

        // If the target is at or before the origin, no prior occurrences
        guard targetDay > origin else { return 0 }

        // Count days from origin to (but not including) target
        let components = calendar.dateComponents([.day], from: origin, to: targetDay)
        guard let totalDays = components.day, totalDays > 0 else { return 0 }

        // We use the base occurs(on:) rather than matches() to avoid recursive limit checking
        var count = 0
        for offset in 0..<totalDays {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: origin) else {
                continue
            }
            if rule.occurs(on: candidate, calendar: calendar) {
                count += 1
            }
        }

        return count
    }
}
