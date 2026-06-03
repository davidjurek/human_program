import Foundation

/// Cached `DateFormatter`s for on-screen date strings.
///
/// `DateFormatter` creation is one of the most expensive Foundation allocations, and these
/// format strings were being rebuilt inside SwiftUI bodies/rows that re-run on every render.
/// Each format gets ONE shared instance, reused everywhere.
///
/// NOTE: like the inline formatters they replace, these honor the DEVICE locale (no explicit
/// locale set). They deliberately do NOT yet read the user's `settings.dateFormat` preference —
/// wiring that in is a separate, behavior-changing task.
enum AppDateFormat {
    /// "Jun 1"
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    /// "Jun 1, 2026"
    static func monthDayYear(_ date: Date) -> String { monthDayYearFormatter.string(from: date) }
    /// "June 2026"
    static func monthYear(_ date: Date) -> String { monthYearFormatter.string(from: date) }
    /// "Monday, Jun 1, 2026"
    static func weekdayMonthDayYear(_ date: Date) -> String { weekdayMonthDayYearFormatter.string(from: date) }
    /// "Monday, Jun 1"
    static func weekdayMonthDay(_ date: Date) -> String { weekdayMonthDayFormatter.string(from: date) }
    /// "Mon" — short weekday, unique within a week.
    static func weekdayShort(_ date: Date) -> String { weekdayShortFormatter.string(from: date) }
    /// "Jun 1 – Jun 7"
    static func monthDayRange(_ start: Date, _ end: Date) -> String {
        "\(monthDay(start)) – \(monthDay(end))"
    }

    /// Formats a date using the user's chosen Date Format setting
    /// (`settings.dateFormat`, default "MMM d, yyyy" — includes the year). Honors
    /// the device locale like the others. Reuses one formatter, re-pointing its
    /// pattern only when the setting changes (called on the main thread).
    static func userPreferred(_ date: Date) -> String {
        let pattern = UserDefaults.standard.string(forKey: DefaultsKey.dateFormat) ?? "MMM d, yyyy"
        if userFormatter.dateFormat != pattern { userFormatter.dateFormat = pattern }
        return userFormatter.string(from: date)
    }
    private static let userFormatter = make("MMM d, yyyy")

    // MARK: - Cached instances

    private static let monthDayFormatter           = make("MMM d")
    private static let monthDayYearFormatter        = make("MMM d, yyyy")
    private static let monthYearFormatter           = make("MMMM yyyy")
    private static let weekdayMonthDayYearFormatter = make("EEEE, MMM d, yyyy")
    private static let weekdayMonthDayFormatter     = make("EEEE, MMM d")
    private static let weekdayShortFormatter        = make("EEE")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}
