import XCTest
import SwiftData
import Foundation
@testable import HumanProgram

/// A gregorian calendar pinned to a named timezone — the tests need to write dates the
/// way a device in another part of the world would.
private func tzCalendar(_ id: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: id)!
    return c
}

/// Regression tests for the timezone bug: day records used to be looked up by their
/// stored INSTANT (local midnight), so travelling made every lookup miss — the app
/// generated a fresh empty page over a day that already had one, wiping edits and
/// bringing completed days back unchecked. Everything here pins the day key. [tz-daykey]
@MainActor
final class DayKeyTimezoneTests: XCTestCase {

    private let berlin = tzCalendar("Europe/Berlin")            // UTC+1/+2
    private let losAngeles = tzCalendar("America/Los_Angeles")  // UTC-7/-8
    private let auckland = tzCalendar("Pacific/Auckland")       // UTC+12/+13

    private func midnight(_ y: Int, _ m: Int, _ d: Int, in cal: Calendar) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 0; c.minute = 0; c.second = 0
        return cal.date(from: c)!
    }

    // MARK: - The key itself

    func testKeyIsTheCalendarDay() {
        XCTAssertEqual(DayKey.make(midnight(2026, 8, 26, in: berlin), calendar: berlin), 20_260_826)
        XCTAssertEqual(DayKey.make(midnight(2026, 1, 1, in: losAngeles), calendar: losAngeles), 20_260_101)
    }

    /// The heart of the fix: a midnight written in ONE timezone still resolves to the
    /// day it was meant to be, no matter where it's read.
    func testStoredMidnightResolvesToTheSameDayFromAnyTimezone() {
        for writer in [berlin, losAngeles, auckland, TestCalendars.utc] {
            let stored = midnight(2026, 8, 20, in: writer)
            XCTAssertEqual(DayKey.fromStoredInstant(stored), 20_260_820,
                           "instant written in \(writer.timeZone.identifier) lost its day")
        }
    }

    func testStartOfDayRoundTripsTheKey() {
        let anchor = DayKey.startOfDay(20_260_820, calendar: losAngeles)
        XCTAssertEqual(DayKey.make(anchor, calendar: losAngeles), 20_260_820)
        XCTAssertEqual(anchor, midnight(2026, 8, 20, in: losAngeles))
    }

    // MARK: - The bug, end to end

    /// Write a page the way the pre-fix app did (midnight in Berlin, no day key), then
    /// look it up from Los Angeles. It must find THAT page — not miss and let the
    /// caller build a second one.
    func testPageWrittenInAnotherTimezoneIsStillFound() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = DailyPageRepository(context: context)

        let legacy = DailyPage(date: midnight(2026, 8, 20, in: berlin))
        legacy.date = midnight(2026, 8, 20, in: berlin)   // as written abroad
        legacy.dayKey = nil                               // as written before the fix
        legacy.dayComplete = true
        context.insert(legacy)
        try context.save()

        let found = try repo.fetch(date: midnight(2026, 8, 20, in: losAngeles), calendar: losAngeles)
        XCTAssertEqual(found?.id, legacy.id, "the day's existing page was not found after a timezone change")
        XCTAssertEqual(found?.dayKey, 20_260_820, "the legacy page should adopt its day key on first read")
    }

    /// The whole reported failure in one test: a completed past day plus the empty
    /// duplicate the missed lookup generated over it. After the repair there is ONE
    /// page for that day, it's the completed one, and it's locked.
    func testRepairMergesDuplicatesAndKeepsTheCompletedDay() throws {
        let context = ModelContext(try makeTestModelContainer())
        let cal = losAngeles
        let today = midnight(2026, 8, 26, in: cal)

        // The real day, written abroad: two tasks, both checked off.
        let real = DailyPage(date: midnight(2026, 8, 20, in: berlin))
        real.date = midnight(2026, 8, 20, in: berlin)
        real.dayKey = nil
        real.dayComplete = true
        real.isPastLocked = false          // as history actually sat: never locked
        context.insert(real)
        for title in ["Run", "Read"] {
            let t = DailyPageTask(title: title, sourceType: .recurring, sourceId: title, sortOrder: 0)
            t.completed = true
            t.page = real
            context.insert(t)
        }

        // The empty duplicate the app generated for the same day after landing.
        let duplicate = DailyPage(date: midnight(2026, 8, 20, in: cal))
        duplicate.dayKey = 20_260_820
        context.insert(duplicate)
        let stray = DailyPageTask(title: "Run", sourceType: .recurring, sourceId: "Run", sortOrder: 0)
        stray.page = duplicate
        context.insert(stray)
        try context.save()

        let report = try DayKeyRepairService.run(context: context, today: today, calendar: cal)
        XCTAssertEqual(report.pagesMerged, 1)

        let pages = try context.fetch(FetchDescriptor<DailyPage>())
        XCTAssertEqual(pages.count, 1, "the day should end up with exactly one page")
        let survivor = pages[0]
        XCTAssertEqual(survivor.id, real.id, "the completed day must survive, not the empty duplicate")
        XCTAssertTrue(survivor.dayComplete, "a completed past day must stay complete")
        XCTAssertEqual(survivor.tasks.count, 2)
        XCTAssertEqual(survivor.dayKey, 20_260_820)
        XCTAssertEqual(survivor.date, midnight(2026, 8, 20, in: cal), "date should re-anchor to local midnight")
        XCTAssertTrue(survivor.isPastLocked, "a day in the past must end up locked")
    }

    /// A merge must never drop work the user did by hand on the losing page.
    func testRepairRescuesHandTypedAndCompletedTasksFromTheDuplicate() throws {
        let context = ModelContext(try makeTestModelContainer())
        let cal = TestCalendars.local
        let today = midnight(2026, 8, 26, in: cal)

        let winner = DailyPage(date: midnight(2026, 8, 20, in: cal))
        winner.dayKey = nil
        winner.date = midnight(2026, 8, 20, in: berlin)
        context.insert(winner)
        let done = DailyPageTask(title: "Run", sourceType: .recurring, sourceId: "Run", sortOrder: 0)
        done.completed = true
        done.page = winner
        context.insert(done)

        let loser = DailyPage(date: midnight(2026, 8, 20, in: cal))
        loser.dayKey = 20_260_820
        context.insert(loser)
        let typed = DailyPageTask(title: "Call plumber", sourceType: .manual, sourceId: nil, sortOrder: 0)
        typed.page = loser
        context.insert(typed)
        let template = DailyPageTask(title: "Read", sourceType: .recurring, sourceId: "Read", sortOrder: 1)
        template.page = loser
        context.insert(template)
        try context.save()

        try DayKeyRepairService.run(context: context, today: today, calendar: cal)

        let pages = try context.fetch(FetchDescriptor<DailyPage>())
        XCTAssertEqual(pages.count, 1)
        let titles = Set(pages[0].tasks.map { $0.title })
        XCTAssertTrue(titles.contains("Call plumber"), "a hand-typed task must never be dropped by the merge")
        XCTAssertFalse(titles.contains("Read"), "an unchecked template leftover should not be rescued")
    }

    /// Even if a past page's stored date is skewed enough to slip into the "today and
    /// future" fetch, the day-key guard must keep the refresh off it.
    func testRefreshNeverTouchesAPastDayWithASkewedStoredDate() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = DailyPageRepository(context: context)
        let cal = TestCalendars.local
        let today = midnight(2026, 8, 26, in: cal)

        let past = DailyPage(date: midnight(2026, 8, 25, in: cal))
        past.dayKey = 20_260_825
        past.isPastLocked = false
        past.dayComplete = true
        past.date = today.addingTimeInterval(3 * 3600)   // skewed forward past "today"
        context.insert(past)
        let task = DailyPageTask(title: "Run", sourceType: .recurring, sourceId: "gone", sortOrder: 0)
        task.completed = true
        task.page = past
        context.insert(task)
        try context.save()

        // No templates at all: an unguarded refresh would strip the task and mark the
        // day incomplete.
        try repo.refreshTodayAndFuture(today: today, recurringTemplates: [], backlogItems: [],
                                       scheduleTemplates: [], calendar: cal)

        XCTAssertEqual(past.tasks.count, 1, "a past day's tasks must not be regenerated")
        XCTAssertTrue(past.dayComplete, "a past day must not be marked incomplete by a refresh")
    }

    /// Per-day calendar overrides were lost the same way page edits were.
    func testCalendarOverrideWrittenInAnotherTimezoneIsStillFound() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = CalendarLocalStateRepository(context: context)

        let state = CalendarEventLocalState(date: midnight(2026, 8, 20, in: berlin), eventId: "evt-1")
        state.date = midnight(2026, 8, 20, in: berlin)
        state.dayKey = nil
        state.hidden = true
        context.insert(state)
        try context.save()

        let hidden = try repo.hiddenEventIds(for: midnight(2026, 8, 20, in: TestCalendars.local))
        XCTAssertEqual(hidden, ["evt-1"], "a hidden calendar event must survive a timezone change")
    }
}

/// A past day's `dayComplete` is a CACHED answer to the completion rule, and it goes
/// stale for any day that passed while the app never opened it — most visibly an empty
/// day, which the rule counts as done. [empty-day-complete]
@MainActor
final class PastDayCompletionTests: XCTestCase {

    private let cal = TestCalendars.local

    private func midnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        makeDate(year: y, month: m, day: d, in: cal)
    }

    /// The reported bug: an empty past day that refuses to go green.
    func testEmptyPastDayBecomesComplete() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = DailyPageRepository(context: context)
        let today = midnight(2026, 8, 26)

        // Written while it was still a FUTURE day, where the rule says "never complete".
        let page = DailyPage(date: midnight(2026, 8, 25))
        page.dayComplete = false
        page.isPastLocked = true
        context.insert(page)
        try context.save()

        let changed = try repo.recalculatePastCompletion(today: today, calendar: cal)

        XCTAssertEqual(changed, 1)
        XCTAssertTrue(page.dayComplete, "an empty past day counts as complete — nothing to do = done")
    }

    /// Opening the day fixes it on the spot, without waiting for the next launch.
    func testOpeningAStalePastDayFixesItImmediately() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = DailyPageRepository(context: context)
        let today = midnight(2026, 8, 26)

        let page = DailyPage(date: midnight(2026, 8, 25))
        page.dayComplete = false
        page.isPastLocked = true
        context.insert(page)
        try context.save()

        let loaded = try repo.getOrCreate(date: midnight(2026, 8, 25), today: today,
                                          recurringTemplates: [], backlogItems: [],
                                          scheduleTemplates: [], calendar: cal)

        XCTAssertEqual(loaded.id, page.id)
        XCTAssertTrue(loaded.dayComplete)
        XCTAssertTrue(loaded.isPastLocked, "re-deriving completion must not disturb the lock")
    }

    /// It re-derives, it doesn't rubber-stamp: an unfinished past day stays incomplete,
    /// and its tasks are left exactly alone.
    func testUnfinishedPastDayStaysIncompleteAndUntouched() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = DailyPageRepository(context: context)
        let today = midnight(2026, 8, 26)

        let page = DailyPage(date: midnight(2026, 8, 25))
        page.dayComplete = true            // wrongly cached as done
        context.insert(page)
        let done = DailyPageTask(title: "Run", sourceType: .manual, sourceId: nil, sortOrder: 0)
        done.completed = true
        done.page = page
        context.insert(done)
        let notDone = DailyPageTask(title: "Read", sourceType: .manual, sourceId: nil, sortOrder: 1)
        notDone.page = page
        context.insert(notDone)
        try context.save()

        try repo.recalculatePastCompletion(today: today, calendar: cal)

        XCTAssertFalse(page.dayComplete, "a day with an unchecked task is not complete")
        XCTAssertEqual(page.tasks.count, 2, "re-deriving completion must never touch tasks")
    }

    /// Today and the future are the other services' business — this pass must not
    /// reach them (a future day is never complete, and today is handled on refresh).
    func testFutureDayIsNotTouched() throws {
        let context = ModelContext(try makeTestModelContainer())
        let repo = DailyPageRepository(context: context)
        let today = midnight(2026, 8, 26)

        let future = DailyPage(date: midnight(2026, 8, 30))
        future.dayComplete = false
        context.insert(future)
        try context.save()

        let changed = try repo.recalculatePastCompletion(today: today, calendar: cal)
        XCTAssertEqual(changed, 0)
        XCTAssertFalse(future.dayComplete)
    }
}
