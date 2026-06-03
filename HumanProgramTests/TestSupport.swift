import XCTest
import Foundation
@testable import HumanProgram

/// Shared calendars for the test suite. The UTC-vs-local split is deliberate:
/// `utc` builds absolute dates without DST-driven flakiness, while `local` matches how
/// `DailyPage` normalizes its date (`Calendar.current`) so stored dates round-trip to the
/// same local day on store/fetch.
enum TestCalendars {
    static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
    static let local: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()
}

extension XCTestCase {
    /// Midnight (00:00:00) on the given Y/M/D in the supplied calendar.
    func makeDate(year: Int, month: Int, day: Int, in calendar: Calendar) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)!
    }

    /// Shared builder for a `RecurringTaskInput` — used by the generator and
    /// past-page snapshot tests so the input shape lives in one place.
    func makeRecurring(
        id: String = UUID().uuidString,
        title: String,
        rule: RecurrenceRule,
        active: Bool = true
    ) -> RecurringTaskInput {
        RecurringTaskInput(id: id, title: title, notes: "", rule: rule, active: active)
    }
}
