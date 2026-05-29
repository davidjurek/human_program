import XCTest
import SwiftData
import Foundation
@testable import HumanProgram

/// Integration tests for the past-page protection invariant:
/// "Template changes update today and future pages only. Past pages are NEVER rewritten."
@MainActor
final class PastPageSnapshotTests: XCTestCase {

    // MARK: - Helpers

    var gregorianUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year   = year
        comps.month  = month
        comps.day    = day
        comps.hour   = 0
        comps.minute = 0
        comps.second = 0
        return gregorianUTC.date(from: comps)!
    }

    /// A fixed "today" for all tests: Wednesday 2025-05-21 (weekday 4).
    var today: Date { makeDate(year: 2025, month: 5, day: 21) }

    /// The day before today: Tuesday 2025-05-20 (weekday 3).
    var yesterday: Date { makeDate(year: 2025, month: 5, day: 20) }

    func makeRecurring(
        id: String = UUID().uuidString,
        title: String,
        rule: RecurrenceRule,
        active: Bool = true
    ) -> RecurringTaskInput {
        RecurringTaskInput(id: id, title: title, notes: "", rule: rule, active: active)
    }

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
            scheduleTemplates: []
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
            scheduleTemplates: []
        )

        // Re-fetch yesterday's page and assert it is untouched.
        let fetchedYesterday = try repo.fetch(date: yesterday)
        XCTAssertNotNil(fetchedYesterday, "Yesterday's page should still exist.")
        let tasks = fetchedYesterday!.tasks
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
            scheduleTemplates: []
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
            scheduleTemplates: []
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
            scheduleTemplates: []
        )

        XCTAssertEqual(yesterdayPage.tasks.count, 1)
        XCTAssertEqual(yesterdayPage.tasks.first?.title, "Daily Task")

        // Create today's page with T1 only.
        let todayPage = try repo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: []
        )

        XCTAssertEqual(todayPage.tasks.count, 1)

        // Now add T2 which matches Wednesday (weekday 4 = today).
        let t2 = makeRecurring(id: t2Id, title: "New Wednesday Task", rule: RecurrenceRule.on([4]))

        // Refresh today and future with both T1 and T2.
        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1, t2],
            backlogItems: [],
            scheduleTemplates: []
        )

        // Today's page should now have both tasks.
        let refreshedToday = try repo.fetch(date: today)!
        let todayTitles = Set(refreshedToday.tasks.map { $0.title })
        XCTAssertTrue(todayTitles.contains("Daily Task"), "Today's page must retain the original task.")
        XCTAssertTrue(todayTitles.contains("New Wednesday Task"), "Today's page must gain the new template task after refresh.")
        XCTAssertEqual(refreshedToday.tasks.count, 2, "Today's page must have exactly 2 tasks.")

        // Yesterday's page must not have gained the new task.
        let fetchedYesterday = try repo.fetch(date: yesterday)!
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
            scheduleTemplates: []
        )

        // Fetch today's page and add a manual task.
        let page = try repo.fetch(date: today)!
        try repo.addManualTask(title: "My Manual Task", to: page)

        // Verify both tasks are present before refresh.
        XCTAssertEqual(page.tasks.count, 2)

        // Refresh today and future with the same template.
        try repo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: [t1],
            backlogItems: [],
            scheduleTemplates: []
        )

        // The manual task must survive.
        let refreshed = try repo.fetch(date: today)!
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
            scheduleTemplates: []
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
            scheduleTemplates: []
        )

        // The task with the same sourceId must still be marked complete.
        let refreshed = try repo.fetch(date: today)!
        let refreshedTask = refreshed.tasks.first { $0.sourceId == tId }
        XCTAssertNotNil(refreshedTask, "The recurring task must still exist after refresh.")
        XCTAssertTrue(refreshedTask!.completed, "Completion state must be preserved after refreshTodayAndFuture.")
        XCTAssertNotNil(refreshedTask!.completedAt, "completedAt timestamp must be preserved after refresh.")
    }
}
