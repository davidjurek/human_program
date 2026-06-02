import XCTest
import SwiftData
@testable import HumanProgram

/// Verifies that once a day is past, its tasks are severed from the backlog/
/// calendar (source tags cleared), while today's tasks keep their source.
@MainActor
final class PastPageDecouplingTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestModelContainer()
    }

    private func addTask(_ page: DailyPage, source: DailyTaskSourceType, sourceId: String?, in ctx: ModelContext) {
        let t = DailyPageTask(title: "t", sourceType: source, sourceId: sourceId)
        t.page = page
        page.tasks.append(t)
        ctx.insert(t)
    }

    func testSeverClearsPastButNotToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let repo = DailyPageRepository(context: ctx)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let pastPage = DailyPage(date: yesterday)
        ctx.insert(pastPage)
        addTask(pastPage, source: .backlog, sourceId: "b1", in: ctx)

        let todayPage = DailyPage(date: today)
        ctx.insert(todayPage)
        addTask(todayPage, source: .backlog, sourceId: "b2", in: ctx)

        try repo.severPastTasks(today: today)

        XCTAssertEqual(pastPage.tasks.first?.sourceType, .manual, "Past task should be severed to manual")
        XCTAssertNil(pastPage.tasks.first?.sourceId, "Past task sourceId should be cleared")
        XCTAssertEqual(todayPage.tasks.first?.sourceType, .backlog, "Today's task keeps its source")
        XCTAssertEqual(todayPage.tasks.first?.sourceId, "b2")
    }

    /// A calendar-sourced past task is also detached, and an already-standalone
    /// (manual, no sourceId) task is left untouched (the no-op branch). [#54]
    func testSeverDetachesCalendar_andLeavesAlreadyManualUntouched() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let repo = DailyPageRepository(context: ctx)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let past = DailyPage(date: yesterday)
        ctx.insert(past)
        let calTask = DailyPageTask(title: "calendar", sourceType: .calendar, sourceId: "evt-1")
        calTask.page = past; past.tasks.append(calTask); ctx.insert(calTask)
        let manualTask = DailyPageTask(title: "manual", sourceType: .manual, sourceId: nil)
        manualTask.page = past; past.tasks.append(manualTask); ctx.insert(manualTask)

        try repo.severPastTasks(today: today)

        let cal2 = try XCTUnwrap(past.tasks.first { $0.title == "calendar" })
        let man2 = try XCTUnwrap(past.tasks.first { $0.title == "manual" })
        XCTAssertEqual(cal2.sourceType, .manual, "Calendar-sourced past task is detached to manual")
        XCTAssertNil(cal2.sourceId)
        XCTAssertEqual(man2.sourceType, .manual, "Already-manual task stays manual (no-op)")
        XCTAssertNil(man2.sourceId)
    }
}
