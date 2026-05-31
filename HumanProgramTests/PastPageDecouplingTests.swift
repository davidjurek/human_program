import XCTest
import SwiftData
@testable import HumanProgram

/// Verifies that once a day is past, its tasks are severed from the backlog/
/// calendar (source tags cleared), while today's tasks keep their source.
@MainActor
final class PastPageDecouplingTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DailyPage.self, DailyPageTask.self, BacklogItem.self, ProjectBucket.self,
                             RecurringTaskTemplate.self, ScheduleTemplate.self, ExerciseRoutine.self,
                             ExerciseRoutineItem.self, RoutineItem.self, Routine.self,
                             CalendarEventLocalState.self, NotificationReminder.self,
                             GameAccessState.self, GameSaveMetadata.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
}
