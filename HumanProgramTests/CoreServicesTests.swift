import XCTest
import Foundation
import SwiftData
@testable import HumanProgram

final class CoreServicesTests: XCTestCase {

    // MARK: - Helpers

    let gregorianUTC = TestCalendars.utc

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        makeDate(year: year, month: month, day: day, in: gregorianUTC)
    }

    // MARK: - CompletionService helpers

    @MainActor
    func makeTask(in context: ModelContext,
                  completed: Bool,
                  title: String = "task") -> DailyPageTask {
        let task = DailyPageTask(title: title, sourceType: .manual)
        task.completed = completed
        context.insert(task)
        return task
    }

    @MainActor
    func makeBacklogTask(in context: ModelContext,
                         sourceId: String,
                         completed: Bool = false) -> DailyPageTask {
        let task = DailyPageTask(title: "backlog task", sourceType: .backlog, sourceId: sourceId)
        task.completed = completed
        context.insert(task)
        return task
    }

    @MainActor
    func makeBacklogItem(in context: ModelContext,
                         assignedDate: Date? = nil,
                         status: BacklogStatus = .backlog) -> BacklogItem {
        let item = BacklogItem(title: "test item")
        item.assignedDate = assignedDate
        item.status = status
        context.insert(item)
        return item
    }

    // ──────────────────────────────────────────────────────────────
    // MARK: - CompletionService Tests
    // ──────────────────────────────────────────────────────────────

    // Completion rule (current rule): a day is complete when it is NOT a future day
    // AND all its tasks are done; an empty today/past day counts as complete, and a
    // future day is never complete regardless of its tasks.
    let completionToday = TestCalendars.utc.startOfDay(for: TestCalendars.utc.date(from: DateComponents(year: 2026, month: 6, day: 6))!)

    @MainActor
    func isComplete(_ tasks: [DailyPageTask], date: Date) -> Bool {
        CompletionService().isComplete(tasks: tasks, date: date, today: completionToday, calendar: gregorianUTC)
    }

    // Test 1: Today, all tasks complete + non-empty → isComplete = true
    @MainActor
    func test_allComplete_nonEmpty_isComplete() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let tasks = [
            makeTask(in: context, completed: true, title: "A"),
            makeTask(in: context, completed: true, title: "B")
        ]
        XCTAssertTrue(isComplete(tasks, date: completionToday),
                      "All completed tasks (today) should result in isComplete=true")
    }

    // Test 2: Today, one task incomplete → isComplete = false
    @MainActor
    func test_oneIncomplete_isNotComplete() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let tasks = [
            makeTask(in: context, completed: true,  title: "A"),
            makeTask(in: context, completed: false, title: "B")
        ]
        XCTAssertFalse(isComplete(tasks, date: completionToday),
                       "One incomplete task should result in isComplete=false")
    }

    // Test 3: Empty TODAY page → isComplete = true (nothing to do = done)
    @MainActor
    func test_emptyTasksToday_isComplete() throws {
        XCTAssertTrue(isComplete([], date: completionToday),
                      "An empty today page should be complete")
    }

    // Test 3b: Empty PAST page → isComplete = true
    @MainActor
    func test_emptyTasksPast_isComplete() throws {
        let yesterday = gregorianUTC.date(byAdding: .day, value: -1, to: completionToday)!
        XCTAssertTrue(isComplete([], date: yesterday),
                      "An empty past page should be complete")
    }

    // Test 3c: Empty FUTURE page → isComplete = false (could still add tasks)
    @MainActor
    func test_emptyTasksFuture_isNotComplete() throws {
        let tomorrow = gregorianUTC.date(byAdding: .day, value: 1, to: completionToday)!
        XCTAssertFalse(isComplete([], date: tomorrow),
                       "An empty future page should NOT be complete")
    }

    // Test 3d: FUTURE page with every task checked → STILL not complete
    @MainActor
    func test_allCompleteFuture_isNotComplete() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let tomorrow = gregorianUTC.date(byAdding: .day, value: 1, to: completionToday)!
        let tasks = [
            makeTask(in: context, completed: true, title: "A"),
            makeTask(in: context, completed: true, title: "B")
        ]
        XCTAssertFalse(isComplete(tasks, date: tomorrow),
                       "A future day is never complete, even with all tasks checked off")
    }

    // ──────────────────────────────────────────────────────────────
    // MARK: - BacklogMaintenanceService Tests
    // ──────────────────────────────────────────────────────────────

    // Test 5: Item with assignedDate yesterday + status=.backlog → assignedDate cleared
    @MainActor
    func test_clearOverdue_yesterdayBacklogItem_dateCleared() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today     = makeDate(year: 2025, month: 6, day: 15)
        let yesterday = makeDate(year: 2025, month: 6, day: 14)

        let item = makeBacklogItem(in: context, assignedDate: yesterday, status: .backlog)
        let service = BacklogMaintenanceService()
        let cleared = service.clearOverdueAssignments(items: [item], today: today, calendar: gregorianUTC)

        XCTAssertNil(item.assignedDate, "assignedDate should be cleared for a past-due backlog item")
        XCTAssertEqual(cleared, [item.id], "Cleared IDs should include the overdue item's ID")
    }

    // Test 6: Item with assignedDate today → NOT cleared
    @MainActor
    func test_clearOverdue_todayBacklogItem_notCleared() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today = makeDate(year: 2025, month: 6, day: 15)

        let item = makeBacklogItem(in: context, assignedDate: today, status: .backlog)
        let service = BacklogMaintenanceService()
        let cleared = service.clearOverdueAssignments(items: [item], today: today, calendar: gregorianUTC)

        XCTAssertNotNil(item.assignedDate, "assignedDate should NOT be cleared for today's item")
        XCTAssertTrue(cleared.isEmpty, "No IDs should be in the cleared list")
    }

    // Test 7: Item with assignedDate tomorrow → NOT cleared
    @MainActor
    func test_clearOverdue_tomorrowBacklogItem_notCleared() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today    = makeDate(year: 2025, month: 6, day: 15)
        let tomorrow = makeDate(year: 2025, month: 6, day: 16)

        let item = makeBacklogItem(in: context, assignedDate: tomorrow, status: .backlog)
        let service = BacklogMaintenanceService()
        let cleared = service.clearOverdueAssignments(items: [item], today: today, calendar: gregorianUTC)

        XCTAssertNotNil(item.assignedDate, "assignedDate should NOT be cleared for a future item")
        XCTAssertTrue(cleared.isEmpty, "No IDs should be in the cleared list")
    }

    // Test 8: Item with status=.done and past date → NOT cleared (done items not touched)
    @MainActor
    func test_clearOverdue_doneItemWithPastDate_notCleared() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today     = makeDate(year: 2025, month: 6, day: 15)
        let yesterday = makeDate(year: 2025, month: 6, day: 14)

        let item = makeBacklogItem(in: context, assignedDate: yesterday, status: .done)
        let service = BacklogMaintenanceService()
        let cleared = service.clearOverdueAssignments(items: [item], today: today, calendar: gregorianUTC)

        XCTAssertNotNil(item.assignedDate, "Done items should never have their assignedDate cleared")
        XCTAssertTrue(cleared.isEmpty, "Done items must not appear in the cleared list")
    }

    // Test 9: syncCompletion: backlog item with matching date → returns (.done)
    @MainActor
    func test_syncCompletion_matchingDate_returnsDone() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today     = makeDate(year: 2025, month: 6, day: 15)
        let pageDate  = today

        let item = makeBacklogItem(in: context, assignedDate: pageDate, status: .backlog)
        let task = makeBacklogTask(in: context, sourceId: item.id)

        let service = BacklogMaintenanceService()
        let result = service.syncCompletion(
            task: task,
            pageDate: pageDate,
            backlogItems: [item],
            today: today,
            calendar: gregorianUTC
        )

        XCTAssertNotNil(result, "syncCompletion should return a result when dates match")
        XCTAssertEqual(result?.itemId, item.id)
        XCTAssertEqual(result?.newStatus, .done)
        XCTAssertEqual(item.status, .done, "BacklogItem status should be updated to .done")
    }

    // Test 10: syncCompletion: backlog item with non-matching date → returns nil
    @MainActor
    func test_syncCompletion_nonMatchingDate_returnsNil() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today    = makeDate(year: 2025, month: 6, day: 15)
        let pageDate = today
        // Item is assigned to a different date than the page date
        let differentDate = makeDate(year: 2025, month: 6, day: 16)

        let item = makeBacklogItem(in: context, assignedDate: differentDate, status: .backlog)
        let task = makeBacklogTask(in: context, sourceId: item.id)

        let service = BacklogMaintenanceService()
        let result = service.syncCompletion(
            task: task,
            pageDate: pageDate,
            backlogItems: [item],
            today: today,
            calendar: gregorianUTC
        )

        XCTAssertNil(result, "syncCompletion should return nil when item's assignedDate does not match pageDate")
        XCTAssertEqual(item.status, .backlog, "Item status should remain .backlog when dates don't match")
    }

    // Test 11: syncUncompletion: restores item to .backlog when conditions met
    @MainActor
    func test_syncUncompletion_matchingDate_restoresBacklog() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today    = makeDate(year: 2025, month: 6, day: 15)
        let pageDate = today

        let item = makeBacklogItem(in: context, assignedDate: pageDate, status: .done)
        let task = makeBacklogTask(in: context, sourceId: item.id, completed: true)

        let service = BacklogMaintenanceService()
        let result = service.syncUncompletion(
            task: task,
            pageDate: pageDate,
            backlogItems: [item],
            today: today,
            calendar: gregorianUTC
        )

        XCTAssertNotNil(result, "syncUncompletion should return a result when conditions are met")
        XCTAssertEqual(result?.itemId, item.id)
        XCTAssertEqual(result?.newStatus, .backlog)
        XCTAssertEqual(item.status, .backlog, "BacklogItem status should be restored to .backlog")
    }

    // Test 11b: syncUncompletion: non-matching date → returns nil, item untouched [#180]
    @MainActor
    func test_syncUncompletion_nonMatchingDate_returnsNil() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let today    = makeDate(year: 2025, month: 6, day: 15)
        let pageDate = today
        // Item is assigned to a different date than the page date.
        let differentDate = makeDate(year: 2025, month: 6, day: 16)

        let item = makeBacklogItem(in: context, assignedDate: differentDate, status: .done)
        let task = makeBacklogTask(in: context, sourceId: item.id, completed: true)

        let service = BacklogMaintenanceService()
        let result = service.syncUncompletion(
            task: task,
            pageDate: pageDate,
            backlogItems: [item],
            today: today,
            calendar: gregorianUTC
        )

        XCTAssertNil(result, "syncUncompletion should return nil when item's assignedDate does not match pageDate")
        XCTAssertEqual(item.status, .done, "Item status should remain unchanged when dates don't match")
    }

    // ──────────────────────────────────────────────────────────────
    // MARK: - StreakCalculator Tests
    // ──────────────────────────────────────────────────────────────

    func makeSnapshot(year: Int, month: Int, day: Int, complete: Bool) -> DailyCompletionSnapshot {
        DailyCompletionSnapshot(
            date: makeDate(year: year, month: month, day: day),
            dayComplete: complete
        )
    }

    // Test 12: 3 consecutive complete days ending today → currentStreak=3
    func test_threeConsecutiveComplete_currentStreak3() {
        let today = makeDate(year: 2025, month: 1, day: 8)
        let snapshots = [
            makeSnapshot(year: 2025, month: 1, day: 6, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 7, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 8, complete: true)
        ]
        let stats = StreakCalculator().calculate(
            snapshots: snapshots, today: today, calendar: gregorianUTC
        )
        XCTAssertEqual(stats.currentStreak, 3,
                       "Three consecutive complete days ending today should yield currentStreak=3")
    }

    // Test 13: Gap in streak → currentStreak counts only from most recent run
    func test_gapInStreak_countsFromMostRecent() {
        // Days 6,7 complete | day 8 incomplete (gap) | days 9,10 complete
        // Today = day 10 → currentStreak should be 2
        let today = makeDate(year: 2025, month: 1, day: 10)
        let snapshots = [
            makeSnapshot(year: 2025, month: 1, day: 6,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 7,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 8,  complete: false),
            makeSnapshot(year: 2025, month: 1, day: 9,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 10, complete: true)
        ]
        let stats = StreakCalculator().calculate(
            snapshots: snapshots, today: today, calendar: gregorianUTC
        )
        XCTAssertEqual(stats.currentStreak, 2,
                       "Streak should count only from the most recent consecutive run (2 days after gap)")
    }

    // Test 14: Today incomplete → currentStreak=0
    func test_todayIncomplete_currentStreak0() {
        let today = makeDate(year: 2025, month: 1, day: 8)
        let snapshots = [
            makeSnapshot(year: 2025, month: 1, day: 6, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 7, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 8, complete: false)
        ]
        let stats = StreakCalculator().calculate(
            snapshots: snapshots, today: today, calendar: gregorianUTC
        )
        XCTAssertEqual(stats.currentStreak, 0,
                       "Incomplete today should yield currentStreak=0")
    }

    // Test 15: Future pages are ignored in streak calculation
    func test_futurePagesIgnored_inStreakAndTotals() {
        let today = makeDate(year: 2025, month: 1, day: 8)
        let snapshots = [
            makeSnapshot(year: 2025, month: 1, day: 7, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 8, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 9, complete: true)  // future — must be ignored
        ]
        let stats = StreakCalculator().calculate(
            snapshots: snapshots, today: today, calendar: gregorianUTC
        )
        XCTAssertEqual(stats.currentStreak, 2,
                       "Future page should not contribute to currentStreak")
        XCTAssertEqual(stats.totalTrackedDays, 2,
                       "Future page should not count toward totalTrackedDays")
        XCTAssertEqual(stats.totalCompleteDays, 2,
                       "Future page should not count toward totalCompleteDays")
    }

    // Test 16: longestStreak found correctly in the middle of history
    func test_longestStreak_foundInMiddle() {
        // Jan 6: complete (run=1)
        // Jan 7: incomplete
        // Jan 8-12: complete  (run=5) ← longest
        // Jan 13: incomplete
        // Jan 14-15: complete (run=2) ← current
        let today = makeDate(year: 2025, month: 1, day: 15)
        let snapshots: [DailyCompletionSnapshot] = [
            makeSnapshot(year: 2025, month: 1, day: 6,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 7,  complete: false),
            makeSnapshot(year: 2025, month: 1, day: 8,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 9,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 10, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 11, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 12, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 13, complete: false),
            makeSnapshot(year: 2025, month: 1, day: 14, complete: true),
            makeSnapshot(year: 2025, month: 1, day: 15, complete: true)
        ]
        let stats = StreakCalculator().calculate(
            snapshots: snapshots, today: today, calendar: gregorianUTC
        )
        XCTAssertEqual(stats.longestStreak, 5,
                       "Longest streak should be 5 (Jan 8–12)")
        XCTAssertEqual(stats.currentStreak, 2,
                       "Current streak should be 2 (Jan 14–15)")
    }

    // Test 17: All days complete → currentStreak = longestStreak = totalTrackedDays
    func test_allDaysComplete_streakEqualsTotalTrackedDays() {
        let today = makeDate(year: 2025, month: 1, day: 10)
        let snapshots = [
            makeSnapshot(year: 2025, month: 1, day: 6,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 7,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 8,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 9,  complete: true),
            makeSnapshot(year: 2025, month: 1, day: 10, complete: true)
        ]
        let stats = StreakCalculator().calculate(
            snapshots: snapshots, today: today, calendar: gregorianUTC
        )
        XCTAssertEqual(stats.currentStreak, 5,
                       "All complete days: currentStreak should equal total tracked days (5)")
        XCTAssertEqual(stats.longestStreak, 5,
                       "All complete days: longestStreak should equal total tracked days (5)")
        XCTAssertEqual(stats.totalTrackedDays, 5,
                       "totalTrackedDays should be 5")
        XCTAssertEqual(stats.currentStreak, stats.longestStreak,
                       "currentStreak and longestStreak must be equal when all days are complete")
        XCTAssertEqual(stats.currentStreak, stats.totalTrackedDays,
                       "currentStreak must equal totalTrackedDays when all days are complete")
    }
}
