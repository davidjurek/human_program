import XCTest
import SwiftData
import Foundation
@testable import HumanProgram

/// Integration tests for the past-page protection invariant:
/// "Template changes update today and future pages only. Past pages are NEVER rewritten."
@MainActor
final class PastPageSnapshotTests: XCTestCase {

    // MARK: - Helpers

    // Must match how DailyPage normalizes its date (Calendar.current / local TZ),
    // otherwise UTC-built dates get shifted to a different local day on store/fetch.
    let localCalendar = TestCalendars.local

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        makeDate(year: year, month: month, day: day, in: localCalendar)
    }

    /// A fixed "today" for all tests: Wednesday 2025-05-21 (weekday 4).
    var today: Date { makeDate(year: 2025, month: 5, day: 21) }

    /// The day before today: Tuesday 2025-05-20 (weekday 3).
    var yesterday: Date { makeDate(year: 2025, month: 5, day: 20) }

    // makeRecurring(...) is shared from TestSupport.swift.

    // MARK: - Test 1: Changing a template's weekday does not rewrite yesterday's page

    /// Scenario:
    ///   1. Create yesterday's page with template T1 that matches Tuesday (weekday 3).
    ///   2. Change T1 so it no longer matches Tuesday (now only matches Monday/weekday 2).
    ///   3. Call refreshTodayAndFuture(today: today).
    ///   4. Assert: yesterday's page still contains task A from the original T1.
    func testPastPageNotRewrittenAfterTemplateWeekdayChange() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let templateId = UUID().uuidString

        // T1 originally fires every Tuesday (weekday 3).
        let originalTemplate = makeRecurring(
            id: templateId,
            title: "Task A",
            rule: RecurrenceRule.on([3])  // Tuesday
        )

        // Create yesterday's page with T1 matching Tuesday.
        let yesterdayPage = try repo.getOrCreate(
            date: yesterday,
            today: today,
            recurringTemplates: [originalTemplate],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // Verify the page was created with task A.
        XCTAssertEqual(yesterdayPage.tasks.count, 1)
        XCTAssertEqual(yesterdayPage.tasks.first?.title, "Task A")
        XCTAssertTrue(yesterdayPage.isPastLocked, "Yesterday's page should be past-locked on creation.")

        // Now change T1 so it no longer matches Tuesday — only Monday (weekday 2).
        let changedTemplate = makeRecurring(
            id: templateId,
            title: "Task A",
            rule: RecurrenceRule.on([2])  // Monday only
        )

        // Refresh today and future with the modified template.
        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [changedTemplate],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // Re-fetch yesterday's page and assert it is untouched.
        let fetchedYesterday = try XCTUnwrap(
            try repo.fetch(date: yesterday, calendar: localCalendar),
            "Yesterday's page should still exist."
        )
        let tasks = fetchedYesterday.tasks
        XCTAssertEqual(tasks.count, 1, "Yesterday's page should still have exactly one task.")
        XCTAssertEqual(tasks.first?.title, "Task A", "Yesterday's task A should not have been removed.")
    }

    // MARK: - Test 2: getOrCreate for a past date returns the existing snapshot

    /// Scenario:
    ///   1. Create yesterday's page via getOrCreate (it becomes a snapshot).
    ///   2. Call getOrCreate again for the same date with different templates.
    ///   3. Assert: the returned page is the same existing page, not freshly generated.
    func testGetOrCreateReturnsPastPageSnapshot() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let templateId = UUID().uuidString

        // First call: yesterday's page is created from T1 matching Tuesday.
        let originalTemplate = makeRecurring(
            id: templateId,
            title: "Original Task",
            rule: RecurrenceRule.on([3])  // Tuesday
        )

        let firstPage = try repo.getOrCreate(
            date: yesterday,
            today: today,
            recurringTemplates: [originalTemplate],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        XCTAssertEqual(firstPage.tasks.count, 1)
        XCTAssertEqual(firstPage.tasks.first?.title, "Original Task")
        XCTAssertTrue(firstPage.isPastLocked)

        // Second call with a completely different template (no Tuesday match).
        let differentTemplate = makeRecurring(
            id: UUID().uuidString,
            title: "New Task That Should Not Appear",
            rule: RecurrenceRule.daily()
        )

        let secondPage = try repo.getOrCreate(
            date: yesterday,
            today: today,
            recurringTemplates: [differentTemplate],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // Must be the same page object (same id).
        XCTAssertEqual(firstPage.id, secondPage.id, "getOrCreate must return the existing past page, not a new one.")

        // Tasks must be unchanged — no "New Task" added.
        XCTAssertEqual(secondPage.tasks.count, 1, "Past page must not gain tasks from new templates.")
        XCTAssertEqual(secondPage.tasks.first?.title, "Original Task", "Existing task must be preserved as-is.")
    }

    // MARK: - Test 3: Today's page gains the new template task; yesterday is untouched

    /// Scenario:
    ///   1. Create yesterday's page with template T1.
    ///   2. Create today's page with template T1 only.
    ///   3. Add a new template T2 that also matches today (Wednesday, weekday 4).
    ///   4. Call refreshTodayAndFuture().
    ///   5. Assert: today has BOTH tasks (T1 + T2); yesterday is unchanged (only T1 task).
    func testRefreshAddNewTemplateToTodayWithoutTouchingYesterday() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let t1Id = UUID().uuidString
        let t2Id = UUID().uuidString

        // T1 fires every day.
        let t1 = makeRecurring(id: t1Id, title: "Daily Task", rule: RecurrenceRule.daily())

        // Create yesterday's page — only T1 was present at that time.
        let yesterdayPage = try repo.getOrCreate(
            date: yesterday,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        XCTAssertEqual(yesterdayPage.tasks.count, 1)
        XCTAssertEqual(yesterdayPage.tasks.first?.title, "Daily Task")

        // Create today's page with T1 only.
        let todayPage = try repo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        XCTAssertEqual(todayPage.tasks.count, 1)

        // Now add T2 which matches Wednesday (weekday 4 = today).
        let t2 = makeRecurring(id: t2Id, title: "New Wednesday Task", rule: RecurrenceRule.on([4]))

        // Refresh today and future with both T1 and T2.
        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1, t2],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // Today's page should now have both tasks.
        let refreshedToday = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        let todayTitles = Set(refreshedToday.tasks.map { $0.title })
        XCTAssertTrue(todayTitles.contains("Daily Task"), "Today's page must retain the original task.")
        XCTAssertTrue(todayTitles.contains("New Wednesday Task"), "Today's page must gain the new template task after refresh.")
        XCTAssertEqual(refreshedToday.tasks.count, 2, "Today's page must have exactly 2 tasks.")

        // Yesterday's page must not have gained the new task.
        let fetchedYesterday = try XCTUnwrap(try repo.fetch(date: yesterday, calendar: localCalendar))
        XCTAssertEqual(fetchedYesterday.tasks.count, 1, "Yesterday's page must remain unchanged.")
        XCTAssertEqual(fetchedYesterday.tasks.first?.title, "Daily Task", "Yesterday's task must not have changed.")
    }

    // MARK: - Test 4: Manual task on today's page survives a refresh

    /// Scenario:
    ///   1. Create today's page with one recurring task.
    ///   2. Add a manual task to today's page.
    ///   3. Call refreshTodayAndFuture().
    ///   4. Assert: the manual task is still present after refresh.
    func testManualTaskSurvivesRefresh() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let tId = UUID().uuidString
        let t1 = makeRecurring(id: tId, title: "Recurring Task", rule: RecurrenceRule.daily())

        // Create today's page.
        _ = try repo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // Fetch today's page and add a manual task.
        let page = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        try repo.addManualTask(title: "My Manual Task", to: page)

        // Verify both tasks are present before refresh.
        XCTAssertEqual(page.tasks.count, 2)

        // Refresh today and future with the same template.
        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // The manual task must survive.
        let refreshed = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        let titles = refreshed.tasks.map { $0.title }
        XCTAssertTrue(titles.contains("My Manual Task"), "Manual task must survive refreshTodayAndFuture.")
        XCTAssertTrue(titles.contains("Recurring Task"), "Recurring task must still be present after refresh.")
        XCTAssertEqual(refreshed.tasks.count, 2, "Task count must remain 2 after refresh.")
    }

    // MARK: - Test 5: Completed task on today's page retains its completion state after refresh

    /// Scenario:
    ///   1. Create today's page with one recurring task.
    ///   2. Toggle that task to completed.
    ///   3. Call refreshTodayAndFuture().
    ///   4. Assert: the task is still marked complete (completion state preserved).
    func testCompletedTaskSurvivesRefresh() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let tId = UUID().uuidString
        let t1 = makeRecurring(id: tId, title: "Completable Task", rule: RecurrenceRule.daily())

        // Create today's page.
        let page = try repo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        XCTAssertEqual(page.tasks.count, 1)
        let task = try XCTUnwrap(page.tasks.first, "Expected at least one task on today's page.")
        XCTAssertFalse(task.completed, "Task should start as incomplete.")

        // Mark the task as complete.
        try repo.toggleTask(task, on: page)
        XCTAssertTrue(task.completed, "Task should be marked complete after toggle.")

        // Refresh today and future.
        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        // The task with the same sourceId must still be marked complete.
        let refreshed = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        let refreshedTask = try XCTUnwrap(
            refreshed.tasks.first { $0.sourceId == tId },
            "The recurring task must still exist after refresh."
        )
        XCTAssertTrue(refreshedTask.completed, "Completion state must be preserved after refreshTodayAndFuture.")
        XCTAssertNotNil(refreshedTask.completedAt, "completedAt timestamp must be preserved after refresh.")
    }

    func testDeletedRecurringTaskStaysHiddenAfterRefresh() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let tId = UUID().uuidString
        let t1 = makeRecurring(id: tId, title: "Whitening strips", rule: RecurrenceRule.daily())

        let page = try repo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        let task = try XCTUnwrap(page.tasks.first { $0.sourceId == tId })
        try repo.deleteTask(task, from: page)

        XCTAssertTrue((page.hiddenRecurringTaskIds ?? []).contains(tId), "Deleting a recurring page task should hide that template for this day.")
        XCTAssertFalse(page.tasks.contains { $0.sourceId == tId })

        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        let refreshed = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        XCTAssertFalse(refreshed.tasks.contains { $0.sourceId == tId }, "A manually deleted recurring task must not be regenerated on refresh.")
        XCTAssertTrue((refreshed.hiddenRecurringTaskIds ?? []).contains(tId), "The per-day recurring hide marker must survive refresh.")
    }

    /// The backlog counterpart of the recurring test: deleting an assigned backlog task on
    /// today/future must STICK across a refresh (the old bug re-added it every load). [today-diffs]
    func testDeletedBacklogTaskStaysHiddenAfterRefresh() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let bId = UUID().uuidString
        let backlog = BacklogTaskInput(id: bId, title: "Pay rent", assignedDate: today, status: .backlog)

        let page = try repo.getOrCreate(
            date: today, today: today,
            recurringTemplates: [], backlogItems: [backlog], scheduleTemplates: [],
            calendar: localCalendar
        )

        let task = try XCTUnwrap(page.tasks.first { $0.sourceId == bId })
        try repo.deleteTask(task, from: page)

        XCTAssertTrue((page.hiddenBacklogTaskIds ?? []).contains(bId), "Deleting an assigned backlog task should hide it for this day.")
        XCTAssertFalse(page.tasks.contains { $0.sourceId == bId })

        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [], backlogItems: [backlog], scheduleTemplates: [],
            calendar: localCalendar
        )

        let refreshed = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        XCTAssertFalse(refreshed.tasks.contains { $0.sourceId == bId }, "A deleted backlog task must not be regenerated on refresh.")
        XCTAssertTrue((refreshed.hiddenBacklogTaskIds ?? []).contains(bId), "The per-day backlog hide marker must survive refresh.")
    }

    // MARK: - Test 6: A FUTURE page gets new template tasks and stays unlocked [#178]

    /// Directly pins that a future page (a) is created unlocked and (b) gains a
    /// new template's task on refresh — the positive half of the snapshot rule.
    func testFuturePageRefreshesFromTemplatesAndStaysUnlocked() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        // Tomorrow is Thursday 2025-05-22 (weekday 5) — a future, unlocked page.
        let tomorrow = makeDate(year: 2025, month: 5, day: 22)

        let t1 = makeRecurring(id: UUID().uuidString, title: "Daily Task", rule: RecurrenceRule.daily())

        // Create tomorrow's page with only T1.
        let futurePage = try repo.getOrCreate(
            date: tomorrow,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )
        XCTAssertFalse(futurePage.isPastLocked, "A future page must NOT be past-locked on creation.")
        XCTAssertEqual(futurePage.tasks.count, 1)

        // Add T2, which matches Thursday (weekday 5 = tomorrow).
        let t2 = makeRecurring(id: UUID().uuidString, title: "New Thursday Task", rule: RecurrenceRule.on([5]))

        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1, t2],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        let refreshed = try XCTUnwrap(try repo.fetch(date: tomorrow, calendar: localCalendar))
        XCTAssertFalse(refreshed.isPastLocked, "A future page must stay unlocked after a refresh.")
        let titles = Set(refreshed.tasks.map { $0.title })
        XCTAssertTrue(titles.contains("Daily Task"), "Future page must retain its original task.")
        XCTAssertTrue(titles.contains("New Thursday Task"), "Future page must gain the new template task after refresh.")
        XCTAssertEqual(refreshed.tasks.count, 2, "Future page must have exactly 2 tasks after refresh.")
    }

    // MARK: - Test 7: A locked (isPastLocked) page is skipped by refresh [#178]

    /// Directly pins the lock flag itself: a page marked isPastLocked is left
    /// untouched by refreshTodayAndFuture even when its date is today/future —
    /// the lock, not just the date, is what protects it.
    func testLockedPageIsSkippedByRefreshEvenWhenDated() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let repo = DailyPageRepository(context: context)

        let t1 = makeRecurring(id: UUID().uuidString, title: "Daily Task", rule: RecurrenceRule.daily())

        // Create today's page (unlocked) with T1.
        let page = try repo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )
        XCTAssertEqual(page.tasks.count, 1)
        XCTAssertFalse(page.isPastLocked)

        // Force the lock flag on while leaving the date as today.
        page.isPastLocked = true
        try context.save()

        // A new template that would otherwise match today (Wednesday, weekday 4).
        let t2 = makeRecurring(id: UUID().uuidString, title: "Should Not Appear", rule: RecurrenceRule.on([4]))

        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1, t2],
            backlogItems: [],
            scheduleTemplates: [],
            calendar: localCalendar
        )

        let refreshed = try XCTUnwrap(try repo.fetch(date: today, calendar: localCalendar))
        XCTAssertTrue(refreshed.isPastLocked, "The locked flag must remain set.")
        XCTAssertEqual(refreshed.tasks.count, 1, "A locked page must not gain the new template's task.")
        XCTAssertEqual(refreshed.tasks.first?.title, "Daily Task", "A locked page's existing task must be untouched.")
    }
}
