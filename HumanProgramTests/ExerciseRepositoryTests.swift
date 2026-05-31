import XCTest
import SwiftData
@testable import HumanProgram

/// Unit tests for ExerciseRepository, focused on the item operations the
/// rebuilt Exercise editor relies on: add, reorder, and the explicit
/// sets/reps setter (which can CLEAR a count back to nil).
@MainActor
final class ExerciseRepositoryTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ExerciseRoutine.self,
            ExerciseRoutineItem.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func makeRoutine(in context: ModelContext) -> ExerciseRoutine {
        let routine = ExerciseRoutine(name: "Monday", rule: RecurrenceRule.on([2]))
        context.insert(routine)
        return routine
    }

    func testAddItemAssignsIncreasingSortOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repo = ExerciseRepository(context: context)
        let routine = makeRoutine(in: context)

        let a = try repo.addItem(to: routine, text: "Push-ups")
        let b = try repo.addItem(to: routine, text: "Squats")

        XCTAssertEqual(a.sortOrder, 0)
        XCTAssertEqual(b.sortOrder, 1)
        XCTAssertEqual(routine.items.count, 2)
    }

    func testSetItemCountsSetsAndClears() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repo = ExerciseRepository(context: context)
        let routine = makeRoutine(in: context)
        let item = try repo.addItem(to: routine, text: "Bench press")

        // Set both.
        try repo.setItemCounts(item, sets: 3, reps: 12)
        XCTAssertEqual(item.sets, 3)
        XCTAssertEqual(item.reps, 12)

        // Clearing to nil must actually clear (unlike updateItem, where nil = leave).
        try repo.setItemCounts(item, sets: nil, reps: nil)
        XCTAssertNil(item.sets)
        XCTAssertNil(item.reps)
    }

    func testReorderItemsRenumbersSortOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repo = ExerciseRepository(context: context)
        let routine = makeRoutine(in: context)

        let a = try repo.addItem(to: routine, text: "A")
        let b = try repo.addItem(to: routine, text: "B")
        let c = try repo.addItem(to: routine, text: "C")

        // New order: C, A, B
        try repo.reorderItems([c, a, b], in: routine)

        XCTAssertEqual(c.sortOrder, 0)
        XCTAssertEqual(a.sortOrder, 1)
        XCTAssertEqual(b.sortOrder, 2)
    }
}
