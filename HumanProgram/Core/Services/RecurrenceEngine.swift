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

        // Count occurrences before `from` ONCE (instead of re-counting per candidate via
        // matches()). The first occurrence >= from has exactly this many prior occurrences,
        // so it fires iff priorCount < occurrenceLimit.
        let priorCount = rule.occurrenceLimit != nil
            ? countOccurrences(of: rule, before: startDay, calendar: calendar)
            : 0

        var result: Date? = nil
        forEachDay(from: startDay, offsets: 0..<limit, calendar: calendar) { candidate, stop in
            guard rule.occurs(on: candidate, calendar: calendar) else { return }
            if let occLimit = rule.occurrenceLimit, priorCount >= occLimit { stop = true; return }
            result = candidate
            stop = true
        }

        return result
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

        // Count occurrences before the range ONCE, then carry a running total forward so the
        // occurrenceLimit check is O(1) per day. matches() re-counts from the origin (back to
        // 1970 when no start/anchor is set) on every call, which made this O(range × origin).
        var priorCount = rule.occurrenceLimit != nil
            ? countOccurrences(of: rule, before: startDay, calendar: calendar)
            : 0

        forEachDay(from: startDay, offsets: 0...totalDays, calendar: calendar) { candidate, stop in
            guard rule.occurs(on: candidate, calendar: calendar) else { return }
            if let limit = rule.occurrenceLimit {
                if priorCount >= limit { stop = true; return }   // limit reached — no later day can fire
                priorCount += 1
            }
            results.append(candidate)
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
        forEachDay(from: origin, offsets: 0..<totalDays, calendar: calendar) { candidate, _ in
            if rule.occurs(on: candidate, calendar: calendar) {
                count += 1
            }
        }

        return count
    }

    /// Steps day-by-day from `start`, calling `body` with the date at each offset in
    /// `offsets`. Set the `inout stop` flag to end the walk early. Centralizes the
    /// day-stepping loop the three methods above used to each rebuild. [#61]
    ///
    /// The `guard let … else { continue }` is defensive only: `calendar.date(byAdding:)`
    /// never returns nil for these normal whole-day offsets, so skipping a nil candidate
    /// can't drop a real occurrence. [#59]
    private func forEachDay<S: Sequence>(
        from start: Date,
        offsets: S,
        calendar: Calendar,
        _ body: (_ date: Date, _ stop: inout Bool) -> Void
    ) where S.Element == Int {
        for offset in offsets {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else {
                continue
            }
            var stop = false
            body(candidate, &stop)
            if stop { break }
        }
    }
}
