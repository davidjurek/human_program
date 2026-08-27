import Foundation

/// A calendar day as a timezone-independent integer (`yyyymmdd`) — the key every
/// per-day record (`DailyPage`, `CalendarEventLocalState`) is filed and looked up under.
///
/// WHY THIS EXISTS — read before changing any day lookup. Day records used to be
/// found by matching their stored `date`, which is an INSTANT: local midnight at the
/// moment the record was written. Exact-instant matching only works while the device
/// never leaves the timezone it was written in. Change timezone (travel) and "midnight"
/// becomes a different instant, so EVERY lookup misses — the app can't see the page it
/// already has, generates a fresh empty one for the same day, and the user's edits
/// disappear while completed past days come back unchecked and break streaks.
/// An integer day key cannot drift, so lookups survive any timezone change. [tz-daykey]
public enum DayKey {

    /// The key for the calendar day `date` falls on in `calendar` — the day the user
    /// means when they're looking at that date on screen.
    public static func make(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// The day a LEGACY record was filed under, recovered from its stored instant
    /// WITHOUT knowing which timezone wrote it.
    ///
    /// A stored value is always some timezone's midnight, so it sits within ±12h of
    /// that day's UTC midnight. Shifting by 12 hours and reading the day in UTC
    /// therefore lands back on the intended day for every offset from UTC-12 through
    /// UTC+12 — i.e. it recovers the true day no matter where the record was written.
    /// (The three UTC+13/+14 zones round to the previous day; they are not worth a
    /// heuristic that would misfile everyone else.) [tz-daykey]
    public static func fromStoredInstant(_ date: Date) -> Int {
        make(date.addingTimeInterval(12 * 3600), calendar: utcCalendar)
    }

    /// Local start-of-day for a key — the canonical `date` a record is re-anchored to,
    /// so date-based display and grouping stay correct in the CURRENT timezone.
    public static func startOfDay(_ key: Int, calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = key / 10_000
        c.month = (key / 100) % 100
        c.day = key % 100
        guard let d = calendar.date(from: c) else { return Date() }
        return calendar.startOfDay(for: d)
    }

    /// The key a record currently resolves to: its stored key when it has one, or the
    /// legacy instant-derived key when it predates this field.
    public static func resolve(storedKey: Int?, storedDate: Date) -> Int {
        storedKey ?? fromStoredInstant(storedDate)
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }()
}
