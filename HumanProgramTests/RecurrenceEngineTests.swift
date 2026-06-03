import XCTest
import Foundation
@testable import HumanProgram

final class RecurrenceEngineTests: XCTestCase {

    // MARK: - Helpers

    /// gregorian calendar with UTC time zone to avoid DST-driven flakiness
    let gregorianUTC = TestCalendars.utc

    /// The fixed anchor date used throughout: 2025-01-06, a Monday (weekday 2)
    var anchor: Date { makeDate(year: 2025, month: 1, day: 6) }

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        makeDate(year: year, month: month, day: day, in: gregorianUTC)
    }

    /// Convenience: anchor + N calendar days
    func anchorPlus(_ days: Int) -> Date {
        gregorianUTC.date(byAdding: .day, value: days, to: anchor)!
    }

    let engine = RecurrenceEngine()

    // MARK: - 1. everyDay matches every day

    func test_everyDay_matchesEveryDay() {
        let rule = RecurrenceRule.daily()
        for offset in 0..<5 {
            let date = anchorPlus(offset)
            XCTAssertTrue(engine.matches(rule, on: date, calendar: gregorianUTC),
                          "everyDay should match anchor+\(offset)")
        }
    }

    // MARK: - 2. weekdays matches Mon–Fri, not Sat/Sun

    func test_weekdays_matchesMonThroughFri() {
        let rule = RecurrenceRule.weekdays()
        // anchor is Monday (2025-01-06). +0=Mon, +1=Tue, +2=Wed, +3=Thu, +4=Fri
        for offset in 0..<5 {
            XCTAssertTrue(engine.matches(rule, on: anchorPlus(offset), calendar: gregorianUTC),
                          "weekdays should match Mon–Fri (offset \(offset))")
        }
        // +5=Sat, +6=Sun
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(5), calendar: gregorianUTC),
                       "weekdays should not match Saturday")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(6), calendar: gregorianUTC),
                       "weekdays should not match Sunday")
    }

    // MARK: - 3. weekends matches Sat/Sun, not Mon

    func test_weekends_matchesSatSun() {
        let rule = RecurrenceRule.weekends()
        let saturday = anchorPlus(5) // Mon+5 = Sat
        let sunday   = anchorPlus(6) // Mon+6 = Sun
        let monday   = anchor         // anchor is Mon

        XCTAssertTrue(engine.matches(rule, on: saturday, calendar: gregorianUTC),
                      "weekends should match Saturday")
        XCTAssertTrue(engine.matches(rule, on: sunday, calendar: gregorianUTC),
                      "weekends should match Sunday")
        XCTAssertFalse(engine.matches(rule, on: monday, calendar: gregorianUTC),
                       "weekends should not match Monday")
    }

    // MARK: - 4. selectedWeekdays [2,4] matches Mon and Wed, not Tue

    func test_selectedWeekdays_matchesOnlyListedDays() {
        // weekday 2 = Mon, weekday 4 = Wed
        let rule = RecurrenceRule.on([2, 4])
        let monday    = anchor          // weekday 2
        let tuesday   = anchorPlus(1)   // weekday 3
        let wednesday = anchorPlus(2)   // weekday 4

        XCTAssertTrue(engine.matches(rule, on: monday, calendar: gregorianUTC),
                      "selectedWeekdays [2,4] should match Monday")
        XCTAssertFalse(engine.matches(rule, on: tuesday, calendar: gregorianUTC),
                       "selectedWeekdays [2,4] should not match Tuesday")
        XCTAssertTrue(engine.matches(rule, on: wednesday, calendar: gregorianUTC),
                      "selectedWeekdays [2,4] should match Wednesday")
    }

    // MARK: - 5. everyNDays interval=2 matches alternating days from anchor

    func test_everyNDays_interval2_matchesAlternate() {
        let rule = RecurrenceRule.everyNDays(2, anchor: anchor)
        // anchor+0 = day 0 → 0%2==0 → match
        // anchor+1 = day 1 → 1%2==1 → no match
        // anchor+2 = day 2 → 2%2==0 → match
        // anchor+4 = day 4 → 4%2==0 → match
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC))
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC))
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC))
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC))
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(4), calendar: gregorianUTC))
    }

    // MARK: - 6. everyNDays interval=3 matches every third day

    func test_everyNDays_interval3() {
        let rule = RecurrenceRule.everyNDays(3, anchor: anchor)
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "day 0 should match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                       "day 1 should not match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                       "day 2 should not match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC),
                      "day 3 should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(6), calendar: gregorianUTC),
                      "day 6 should match")
    }

    // MARK: - 7. everyNWeeks interval=1 matches same weekday weekly

    func test_everyNWeeks_interval1_matchesSameWeekdayWeekly() {
        // anchor = Monday; rule fires every Monday
        let rule = RecurrenceRule.everyNWeeks(1, on: [2], anchor: anchor)
        // anchor+0, +7, +14 are all Mondays
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "week 0 Monday should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(7), calendar: gregorianUTC),
                      "week 1 Monday should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(14), calendar: gregorianUTC),
                      "week 2 Monday should match")
        // Mid-week days should not match
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC),
                       "Thursday should not match")
    }

    // MARK: - 8. everyNWeeks interval=2 matches every other Monday

    func test_everyNWeeks_interval2_matchesEveryOtherMonday() {
        let rule = RecurrenceRule.everyNWeeks(2, on: [2], anchor: anchor)
        // anchor+0 = week 0 → 0%2==0 → match
        // anchor+7 = week 1 → 1%2==1 → no match
        // anchor+14 = week 2 → 2%2==0 → match
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "anchor (week 0) should match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(7), calendar: gregorianUTC),
                       "week 1 Monday should not match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(14), calendar: gregorianUTC),
                      "week 2 Monday should match")
    }

    // MARK: - 8c. occurrences() with an occurrenceLimit equals the per-day matches() result

    func test_occurrences_withOccurrenceLimit_equalsPerDayMatches() {
        // every day, capped at 3 occurrences, starting at the anchor.
        let rule = RecurrenceRule(frequency: .everyDay, anchorDate: anchor,
                                  startDate: anchor, occurrenceLimit: 3)
        let result = engine.occurrences(of: rule, in: anchor...anchorPlus(10), calendar: gregorianUTC)

        // Only the first 3 days fire, then the limit stops it.
        XCTAssertEqual(result, [anchorPlus(0), anchorPlus(1), anchorPlus(2)])

        // The optimized running-count path must equal filtering each day through matches().
        let viaMatches = (0...10).map { anchorPlus($0) }
            .filter { engine.matches(rule, on: $0, calendar: gregorianUTC) }
        XCTAssertEqual(result, viaMatches)

        // nextOccurrence respects the same limit: from within the cap it returns the day,
        // from beyond it (4th day onward) there is no further occurrence.
        XCTAssertEqual(engine.nextOccurrence(of: rule, from: anchorPlus(1), withinDays: 30, calendar: gregorianUTC),
                       anchorPlus(1))
        XCTAssertNil(engine.nextOccurrence(of: rule, from: anchorPlus(3), withinDays: 30, calendar: gregorianUTC))
    }

    // MARK: - 8b. everyNWeeks fires on ALL selected weekdays in a qualifying week

    func test_everyNWeeks_multipleWeekdays_fireOnEverySelectedDayInQualifyingWeeks() {
        // anchor = Monday 2025-01-06. "Every 2 weeks on Mon (2), Wed (4), Fri (6)".
        let rule = RecurrenceRule.everyNWeeks(2, on: [2, 4, 6], anchor: anchor)

        // Week 0 (the anchor's week): all three selected weekdays must fire — this is
        // the regression: the old code only fired the anchor's own weekday (Monday).
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "week 0 Monday should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                      "week 0 Wednesday should match (was dropped before the fix)")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(4), calendar: gregorianUTC),
                      "week 0 Friday should match (was dropped before the fix)")
        // A non-selected weekday in week 0 must NOT fire.
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                       "week 0 Tuesday is not selected")

        // Week 1 is the OFF week (1 % 2 != 0): no selected weekday fires.
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(9), calendar: gregorianUTC),
                       "week 1 Wednesday is in an off week")

        // Week 2 is ON again (2 % 2 == 0): all three fire.
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(14), calendar: gregorianUTC),
                      "week 2 Monday should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(16), calendar: gregorianUTC),
                      "week 2 Wednesday should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(18), calendar: gregorianUTC),
                      "week 2 Friday should match")
    }

    // MARK: - 9. everyOtherDay matches alternating days (same as everyNDays(2))

    func test_everyOtherDay_matchesAlternate() {
        let rule = RecurrenceRule(frequency: .everyOtherDay, anchorDate: anchor)
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC))
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC))
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC))
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC))
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(4), calendar: gregorianUTC))
    }

    // MARK: - 9b. everyOtherDay is equivalent to everyNDays(2) across a range [#184]

    func test_everyOtherDay_equalsEveryNDays2_overRange() {
        let everyOther = RecurrenceRule(frequency: .everyOtherDay, anchorDate: anchor)
        let everyTwo   = RecurrenceRule.everyNDays(2, anchor: anchor)
        for offset in 0..<20 {
            let date = anchorPlus(offset)
            XCTAssertEqual(
                engine.matches(everyOther, on: date, calendar: gregorianUTC),
                engine.matches(everyTwo, on: date, calendar: gregorianUTC),
                "everyOtherDay must match everyNDays(2) on anchor+\(offset)"
            )
        }
    }

    // MARK: - 10. startDate exclusion

    func test_startDate_exclusion() {
        let startDate = anchorPlus(3)
        let rule = RecurrenceRule(frequency: .everyDay, startDate: startDate)

        // Day before startDate must not match
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                       "date before startDate should return false")
        // startDate itself must match
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC),
                      "startDate itself should return true")
    }

    // MARK: - 11. endDate exclusion

    func test_endDate_exclusion() {
        let endDate = anchorPlus(5)
        let rule = RecurrenceRule(frequency: .everyDay, endDate: endDate)

        // Day after endDate must not match
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(6), calendar: gregorianUTC),
                       "date after endDate should return false")
        // endDate itself must match
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(5), calendar: gregorianUTC),
                      "endDate itself should return true")
    }

    // MARK: - 12. startDate and endDate are inclusive

    func test_startAndEndDate_inclusive() {
        let startDate = anchorPlus(2)
        let endDate   = anchorPlus(4)
        let rule = RecurrenceRule(frequency: .everyDay, startDate: startDate, endDate: endDate)

        XCTAssertTrue(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                      "startDate should be inclusive")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC),
                      "middle date should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(4), calendar: gregorianUTC),
                      "endDate should be inclusive")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                       "day before start should not match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(5), calendar: gregorianUTC),
                       "day after end should not match")
    }

    // MARK: - 13. occurrenceLimit: returns false after limit is reached

    func test_occurrenceLimit_returnsAfterLimitReached() {
        // everyDay rule with startDate = anchor and occurrenceLimit = 3
        // Should match days 0, 1, 2 (three occurrences) and reject day 3+
        let rule = RecurrenceRule(
            frequency: .everyDay,
            startDate: anchor,
            occurrenceLimit: 3
        )

        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "1st occurrence should match (within limit)")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                      "2nd occurrence should match (within limit)")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                      "3rd occurrence should match (at limit)")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC),
                       "4th occurrence should not match (limit exceeded)")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(10), calendar: gregorianUTC),
                       "far future date should not match (limit exceeded)")
    }

    func test_occurrenceLimit_1_onlyFirstOccurrenceMatches() {
        // Only the first occurrence (anchorDate itself) should match
        let rule = RecurrenceRule(
            frequency: .everyDay,
            startDate: anchor,
            occurrenceLimit: 1
        )
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "1st occurrence should match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                       "2nd occurrence should not match when limit is 1")
    }

    func test_occurrenceLimit_withWeekdays() {
        // weekdays rule + occurrenceLimit = 2, starting from anchor (Monday)
        // Occurrences: anchor+0 (Mon), anchor+1 (Tue), anchor+2 (Wed)...
        // Limit 2 means only the first 2 weekday occurrences match
        let rule = RecurrenceRule(
            frequency: .weekdays,
            startDate: anchor,
            occurrenceLimit: 2
        )
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "1st weekday occurrence (Monday) should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                      "2nd weekday occurrence (Tuesday) should match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                       "3rd weekday occurrence (Wednesday) should not match (limit exceeded)")
    }

    // MARK: - 14. fourDaySplit active days (0,1,2 match; 3 = rest does not)

    func test_fourDaySplit_activeDays() {
        let rule = RecurrenceRule(frequency: .fourDaySplit, anchorDate: anchor)
        // cycle: day 0=WorkoutA, day 1=WorkoutB, day 2=WorkoutC, day 3=Rest
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(0), calendar: gregorianUTC),
                      "day 0 (Workout A) should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(1), calendar: gregorianUTC),
                      "day 1 (Workout B) should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(2), calendar: gregorianUTC),
                      "day 2 (Workout C) should match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(3), calendar: gregorianUTC),
                       "day 3 (Rest) should not match")
    }

    // MARK: - 15. fourDaySplit cycle repeats

    func test_fourDaySplit_cycle_repeats() {
        let rule = RecurrenceRule(frequency: .fourDaySplit, anchorDate: anchor)
        // day 4 = start of second cycle (index 0 mod 4), should match
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(4), calendar: gregorianUTC),
                      "day 4 = day 0 of second cycle, should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(5), calendar: gregorianUTC),
                      "day 5 = day 1 of second cycle, should match")
        XCTAssertTrue(engine.matches(rule, on: anchorPlus(6), calendar: gregorianUTC),
                      "day 6 = day 2 of second cycle, should match")
        XCTAssertFalse(engine.matches(rule, on: anchorPlus(7), calendar: gregorianUTC),
                       "day 7 = day 3 (Rest) of second cycle, should not match")
    }
}
