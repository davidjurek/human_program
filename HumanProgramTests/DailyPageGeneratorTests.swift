import XCTest
import Foundation
@testable import HumanProgram

final class DailyPageGeneratorTests: XCTestCase {

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

    /// Test date: Monday 2025-05-19 (weekday 2 in iOS Calendar)
    var testDate: Date { makeDate(year: 2025, month: 5, day: 19) }

    var tomorrow: Date {
        gregorianUTC.date(byAdding: .day, value: 1, to: testDate)!
    }

    let generator = DailyPageGenerator()

    // Convenience builder for a RecurringTaskInput
    func makeRecurring(id: String = UUID().uuidString,
                       title: String,
                       rule: RecurrenceRule,
                       active: Bool = true) -> RecurringTaskInput {
        RecurringTaskInput(id: id, title: title, notes: "", rule: rule, active: active)
    }

    // Convenience builder for a BacklogTaskInput
    func makeBacklog(id: String = UUID().uuidString,
                     title: String,
                     assignedDate: Date?,
                     status: BacklogStatus = .backlog) -> BacklogTaskInput {
        BacklogTaskInput(id: id, title: title, assignedDate: assignedDate, status: status)
    }

    func generate(recurring: [RecurringTaskInput] = [],
                  backlog: [BacklogTaskInput] = [],
                  scheduleTemplates: [ScheduleBlockInput] = []) -> GeneratedPage {
        generator.generate(
            date: testDate,
            recurringTemplates: recurring,
            backlogItems: backlog,
            scheduleTemplates: scheduleTemplates,
            calendar: gregorianUTC
        )
    }

    // Convenience builder for a ScheduleBlockInput assigned to specific weekdays
    func makeWeekdayScheduleBlock(id: String = UUID().uuidString,
                                  title: String,
                                  startMinute: Int = 480,
                                  endMinute: Int = 540,
                                  sortOrder: Int = 0,
                                  weekdays: [Int],
                                  isEnabled: Bool = true) -> ScheduleBlockInput {
        ScheduleBlockInput(
            id: id,
            title: title,
            startMinuteOfDay: startMinute,
            endMinuteOfDay: endMinute,
            sortOrder: sortOrder,
            templateIsEnabled: isEnabled,
            templateAssignedWeekdays: weekdays,
            templateCustomDateStart: nil,
            templateCustomDateEnd: nil
        )
    }

    // Convenience builder for a ScheduleBlockInput with a custom date range
    func makeCustomDateScheduleBlock(id: String = UUID().uuidString,
                                     title: String,
                                     startMinute: Int = 480,
                                     endMinute: Int = 540,
                                     sortOrder: Int = 0,
                                     customStart: Date,
                                     customEnd: Date,
                                     isEnabled: Bool = true) -> ScheduleBlockInput {
        ScheduleBlockInput(
            id: id,
            title: title,
            startMinuteOfDay: startMinute,
            endMinuteOfDay: endMinute,
            sortOrder: sortOrder,
            templateIsEnabled: isEnabled,
            templateAssignedWeekdays: [],
            templateCustomDateStart: customStart,
            templateCustomDateEnd: customEnd
        )
    }

    // MARK: - 1. Recurring task with matching weekday appears in generated tasks

    func test_recurringTask_matchingWeekday_appearsInPage() {
        // weekdays rule — Monday (weekday 2) is a weekday
        let task = makeRecurring(title: "Morning jog", rule: .weekdays())
        let page = generate(recurring: [task])

        XCTAssertEqual(page.tasks.count, 1)
        XCTAssertEqual(page.tasks[0].title, "Morning jog")
        XCTAssertEqual(page.tasks[0].sourceType, .recurring)
    }

    // MARK: - 2. Recurring task with non-matching weekday does NOT appear

    func test_recurringTask_nonMatchingWeekday_excluded() {
        // weekends rule — Monday is NOT a weekend day
        let task = makeRecurring(title: "Weekend run", rule: .weekends())
        let page = generate(recurring: [task])

        XCTAssertTrue(page.tasks.isEmpty,
                      "Weekend-only task should not appear on a Monday")
    }

    // MARK: - 3. Inactive recurring task does NOT appear

    func test_inactiveRecurringTask_excluded() {
        // Rule matches Monday, but task is inactive
        let task = makeRecurring(title: "Yoga", rule: .weekdays(), active: false)
        let page = generate(recurring: [task])

        XCTAssertTrue(page.tasks.isEmpty,
                      "Inactive task should be excluded regardless of weekday match")
    }

    // MARK: - 4. Backlog item assigned to that date appears

    func test_backlogItem_assignedToDate_appears() {
        let item = makeBacklog(title: "Fix bug", assignedDate: testDate)
        let page = generate(backlog: [item])

        XCTAssertEqual(page.tasks.count, 1)
        XCTAssertEqual(page.tasks[0].title, "Fix bug")
        XCTAssertEqual(page.tasks[0].sourceType, .backlog)
    }

    // MARK: - 5. Backlog item assigned to a different date does NOT appear

    func test_backlogItem_differentDate_excluded() {
        let item = makeBacklog(title: "Tomorrow task", assignedDate: tomorrow)
        let page = generate(backlog: [item])

        XCTAssertTrue(page.tasks.isEmpty,
                      "Backlog item assigned to tomorrow should not appear today")
    }

    // MARK: - 6. Backlog item with status=.done does NOT appear even if date matches

    func test_backlogItem_doneStatus_excluded() {
        let item = makeBacklog(title: "Completed errand", assignedDate: testDate, status: .done)
        let page = generate(backlog: [item])

        XCTAssertTrue(page.tasks.isEmpty,
                      "Done backlog item should be excluded even if assignedDate matches")
    }

    // MARK: - 7. Multiple recurring + multiple backlog items combine correctly

    func test_multipleInputs_combine() {
        let recurring1 = makeRecurring(title: "Task A", rule: .weekdays())
        let recurring2 = makeRecurring(title: "Task B", rule: .weekdays())
        // Inactive and non-matching recurring items should be filtered out
        let recurring3 = makeRecurring(title: "Task E", rule: .weekends())
        let recurring4 = makeRecurring(title: "Task F", rule: .weekdays(), active: false)

        let backlog1 = makeBacklog(title: "Task C", assignedDate: testDate)
        let backlog2 = makeBacklog(title: "Task D", assignedDate: testDate)
        // Done and wrong-date backlog items should be filtered out
        let backlog3 = makeBacklog(title: "Task G", assignedDate: tomorrow)
        let backlog4 = makeBacklog(title: "Task H", assignedDate: testDate, status: .done)

        let page = generate(
            recurring: [recurring1, recurring2, recurring3, recurring4],
            backlog: [backlog1, backlog2, backlog3, backlog4]
        )

        XCTAssertEqual(page.tasks.count, 4,
                       "Expected 2 active/matching recurring + 2 valid backlog = 4 tasks")

        let titles = page.tasks.map { $0.title }
        XCTAssertTrue(titles.contains("Task A"))
        XCTAssertTrue(titles.contains("Task B"))
        XCTAssertTrue(titles.contains("Task C"))
        XCTAssertTrue(titles.contains("Task D"))

        // Recurring tasks come before backlog tasks in sort order
        let recurringTasks = page.tasks.filter { $0.sourceType == .recurring }
        let backlogTasks   = page.tasks.filter { $0.sourceType == .backlog }
        XCTAssertEqual(recurringTasks.count, 2)
        XCTAssertEqual(backlogTasks.count, 2)

        let maxRecurringSortOrder = recurringTasks.map { $0.sortOrder }.max() ?? Int.max
        let minBacklogSortOrder   = backlogTasks.map { $0.sortOrder }.min() ?? Int.min
        XCTAssertLessThan(maxRecurringSortOrder, minBacklogSortOrder,
                          "All recurring tasks should precede all backlog tasks in sort order")
    }

    // MARK: - 8. Empty inputs produce empty task list

    func test_emptyInputs_emptyPage() {
        let page = generate()

        XCTAssertTrue(page.tasks.isEmpty)
        XCTAssertTrue(page.scheduleBlocks.isEmpty)
        XCTAssertEqual(page.date, testDate)
    }

    // MARK: - 9. Schedule blocks from matching template are included in generated page

    func test_scheduleBlocks_matchingWeekday_included() {
        // Monday = weekday 2; testDate is Monday 2025-05-19
        let block1 = makeWeekdayScheduleBlock(
            id: "block-1",
            title: "Morning Focus",
            startMinute: 480,   // 08:00
            endMinute: 600,     // 10:00
            sortOrder: 0,
            weekdays: [2]       // Monday
        )
        let block2 = makeWeekdayScheduleBlock(
            id: "block-2",
            title: "Deep Work",
            startMinute: 600,   // 10:00
            endMinute: 720,     // 12:00
            sortOrder: 1,
            weekdays: [2]       // same template (same metadata), same weekday
        )

        let page = generate(scheduleTemplates: [block1, block2])

        XCTAssertEqual(page.scheduleBlocks.count, 2,
                       "Both blocks from the Monday template should be included")

        let ids = page.scheduleBlocks.map { $0.id }
        XCTAssertTrue(ids.contains("block-1"))
        XCTAssertTrue(ids.contains("block-2"))
    }

    func test_scheduleBlocks_nonMatchingWeekday_excluded() {
        // Saturday = weekday 7; testDate is Monday
        let block = makeWeekdayScheduleBlock(
            id: "sat-block",
            title: "Weekend Schedule",
            startMinute: 600,
            endMinute: 720,
            sortOrder: 0,
            weekdays: [7]   // Saturday only
        )

        let page = generate(scheduleTemplates: [block])

        XCTAssertTrue(page.scheduleBlocks.isEmpty,
                      "Saturday schedule block should not appear on a Monday")
    }

    func test_scheduleBlocks_disabledTemplate_excluded() {
        let block = makeWeekdayScheduleBlock(
            id: "disabled-block",
            title: "Disabled Schedule",
            startMinute: 480,
            endMinute: 540,
            sortOrder: 0,
            weekdays: [2],      // Monday — matches testDate
            isEnabled: false    // but disabled
        )

        let page = generate(scheduleTemplates: [block])

        XCTAssertTrue(page.scheduleBlocks.isEmpty,
                      "Blocks from a disabled template should not appear")
    }

    func test_scheduleBlocks_sortedBySortOrder() {
        // Provide blocks intentionally out of sort order
        let block1 = makeWeekdayScheduleBlock(
            id: "block-a",
            title: "Late Block",
            startMinute: 900,
            endMinute: 960,
            sortOrder: 2,
            weekdays: [2]
        )
        let block2 = makeWeekdayScheduleBlock(
            id: "block-b",
            title: "Early Block",
            startMinute: 480,
            endMinute: 540,
            sortOrder: 0,
            weekdays: [2]
        )
        let block3 = makeWeekdayScheduleBlock(
            id: "block-c",
            title: "Mid Block",
            startMinute: 660,
            endMinute: 720,
            sortOrder: 1,
            weekdays: [2]
        )

        let page = generate(scheduleTemplates: [block1, block2, block3])

        XCTAssertEqual(page.scheduleBlocks.count, 3)
        XCTAssertEqual(page.scheduleBlocks[0].id, "block-b", "sortOrder 0 should come first")
        XCTAssertEqual(page.scheduleBlocks[1].id, "block-c", "sortOrder 1 should come second")
        XCTAssertEqual(page.scheduleBlocks[2].id, "block-a", "sortOrder 2 should come last")
    }

    // MARK: - 10. Custom date range schedule overrides weekday schedule on that date

    func test_customDateRange_overridesWeekdaySchedule_onMatchingDate() {
        // The weekday template would normally fire on Monday (weekday 2)
        let weekdayBlock = makeWeekdayScheduleBlock(
            id: "weekday-block",
            title: "Normal Monday Schedule",
            startMinute: 480,
            endMinute: 540,
            sortOrder: 0,
            weekdays: [2]   // Monday
        )

        // A custom date range that covers testDate (2025-05-19)
        let rangeStart = makeDate(year: 2025, month: 5, day: 19)
        let rangeEnd   = makeDate(year: 2025, month: 5, day: 19)
        let customBlock = makeCustomDateScheduleBlock(
            id: "custom-block",
            title: "Custom Override Schedule",
            startMinute: 600,
            endMinute: 660,
            sortOrder: 0,
            customStart: rangeStart,
            customEnd: rangeEnd
        )

        // Custom date range template is listed first; weekday template is listed second.
        // Per the selection priority: custom date range wins over weekday assignment.
        let page = generate(scheduleTemplates: [customBlock, weekdayBlock])

        XCTAssertEqual(page.scheduleBlocks.count, 1,
                       "Only the custom date range block should be returned, not the weekday block")
        XCTAssertEqual(page.scheduleBlocks[0].id, "custom-block",
                       "The custom date range schedule should override the weekday schedule")
        XCTAssertEqual(page.scheduleBlocks[0].title, "Custom Override Schedule")
    }

    func test_customDateRange_doesNotOverrideOnDifferentDate() {
        // Custom date range that does NOT include testDate (covers the day after)
        let rangeStart = makeDate(year: 2025, month: 5, day: 20)
        let rangeEnd   = makeDate(year: 2025, month: 5, day: 22)
        let customBlock = makeCustomDateScheduleBlock(
            id: "future-custom-block",
            title: "Future Override Schedule",
            startMinute: 600,
            endMinute: 660,
            sortOrder: 0,
            customStart: rangeStart,
            customEnd: rangeEnd
        )

        // Weekday template matches Monday
        let weekdayBlock = makeWeekdayScheduleBlock(
            id: "weekday-block",
            title: "Normal Monday Schedule",
            startMinute: 480,
            endMinute: 540,
            sortOrder: 0,
            weekdays: [2]
        )

        let page = generate(scheduleTemplates: [customBlock, weekdayBlock])

        XCTAssertEqual(page.scheduleBlocks.count, 1,
                       "Custom range does not cover testDate; weekday block should win")
        XCTAssertEqual(page.scheduleBlocks[0].id, "weekday-block",
                       "Normal weekday schedule should apply when custom range does not cover the date")
    }

    // MARK: - Sort order / source ID integrity

    func test_recurringTask_sourceId_preserved() {
        let recurringId = "rec-abc-123"
        let task = makeRecurring(id: recurringId, title: "Daily standup", rule: .weekdays())
        let page = generate(recurring: [task])

        XCTAssertEqual(page.tasks.count, 1)
        XCTAssertEqual(page.tasks[0].sourceId, recurringId)
        XCTAssertEqual(page.tasks[0].sourceType, .recurring)
    }

    func test_backlogTask_sourceId_preserved() {
        let backlogId = "bl-xyz-456"
        let item = makeBacklog(id: backlogId, title: "Read chapter 3", assignedDate: testDate)
        let page = generate(backlog: [item])

        XCTAssertEqual(page.tasks.count, 1)
        XCTAssertEqual(page.tasks[0].sourceId, backlogId)
        XCTAssertEqual(page.tasks[0].sourceType, .backlog)
    }

    func test_recurringTasksSortedAlphabetically_beforeBacklog() {
        // Recurring tasks: deliberately out of alphabetical order
        let taskC = makeRecurring(title: "Charlie task", rule: .weekdays())
        let taskA = makeRecurring(title: "Alpha task",   rule: .weekdays())
        let taskB = makeRecurring(title: "Bravo task",   rule: .weekdays())

        // Backlog tasks: also out of alphabetical order
        let backlogZ = makeBacklog(title: "Zulu item",  assignedDate: testDate)
        let backlogM = makeBacklog(title: "Mike item",  assignedDate: testDate)

        let page = generate(recurring: [taskC, taskA, taskB], backlog: [backlogZ, backlogM])

        XCTAssertEqual(page.tasks.count, 5)

        // First 3 tasks are recurring, sorted alphabetically
        XCTAssertEqual(page.tasks[0].title, "Alpha task")
        XCTAssertEqual(page.tasks[1].title, "Bravo task")
        XCTAssertEqual(page.tasks[2].title, "Charlie task")

        // Last 2 tasks are backlog, sorted alphabetically
        XCTAssertEqual(page.tasks[3].title, "Mike item")
        XCTAssertEqual(page.tasks[4].title, "Zulu item")

        // sortOrder values are 0-based and sequential across all tasks
        XCTAssertEqual(page.tasks[0].sortOrder, 0)
        XCTAssertEqual(page.tasks[1].sortOrder, 1)
        XCTAssertEqual(page.tasks[2].sortOrder, 2)
        XCTAssertEqual(page.tasks[3].sortOrder, 3)
        XCTAssertEqual(page.tasks[4].sortOrder, 4)
    }
}
