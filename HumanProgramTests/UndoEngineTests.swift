import XCTest
import SwiftData
@testable import HumanProgram

/// Unit tests for the shake-triggered undo/redo engine: snapshot round-trips for
/// the in-scope model types (create / edit / delete reverse and re-apply, preserving
/// id and fields), redo-stack invalidation, burst coalescing, the depth cap, and the
/// container (parent+children) reconcile used by the Routines editor.
@MainActor
final class UndoEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        try makeTestModelContainer().mainContext
    }

    override func setUp() {
        super.setUp()
        UndoStore.shared.clear()
    }

    // MARK: - Backlog item: create / edit / delete

    func testBacklogCreateUndoRedo() throws {
        let c = try makeContext()
        let item = BacklogItem(title: "Buy milk")
        c.insert(item); try c.save()
        let id = item.id
        Undo.created("Add backlog item", BacklogItemSnapshot(item))

        // Undo removes it.
        UndoStore.shared.undo(context: c)
        XCTAssertTrue(fetchBacklog(id, c) == nil)
        // Redo recreates it with the SAME id and title.
        UndoStore.shared.redo(context: c)
        let back = fetchBacklog(id, c)
        XCTAssertEqual(back?.id, id)
        XCTAssertEqual(back?.title, "Buy milk")
    }

    func testBacklogEditUndoRedo() throws {
        let c = try makeContext()
        let item = BacklogItem(title: "Old"); c.insert(item); try c.save()
        let before = BacklogItemSnapshot(item)
        item.title = "New"; try c.save()
        Undo.edited("Edit backlog item", before: before, after: BacklogItemSnapshot(item))

        UndoStore.shared.undo(context: c)
        XCTAssertEqual(fetchBacklog(item.id, c)?.title, "Old")
        UndoStore.shared.redo(context: c)
        XCTAssertEqual(fetchBacklog(item.id, c)?.title, "New")
    }

    func testBacklogDeleteUndoRedo() throws {
        let c = try makeContext()
        let item = BacklogItem(title: "Keep"); c.insert(item); try c.save()
        let id = item.id
        Undo.deleted("Delete backlog item", BacklogItemSnapshot(item))
        c.delete(item); try c.save()
        XCTAssertNil(fetchBacklog(id, c))

        UndoStore.shared.undo(context: c)     // restores it
        XCTAssertEqual(fetchBacklog(id, c)?.title, "Keep")
        UndoStore.shared.redo(context: c)     // deletes again
        XCTAssertNil(fetchBacklog(id, c))
    }

    // MARK: - Backlog item ↔ project relationship survives undo

    func testBacklogItemKeepsProjectLinkThroughUndo() throws {
        let c = try makeContext()
        let project = ProjectBucket(name: "Home"); c.insert(project)
        let item = BacklogItem(title: "Task"); item.project = project
        c.insert(item); try c.save()
        let snap = BacklogItemSnapshot(item)
        Undo.deleted("Delete backlog item", snap)
        c.delete(item); try c.save()

        UndoStore.shared.undo(context: c)
        XCTAssertEqual(fetchBacklog(item.id, c)?.project?.id, project.id)
    }

    // MARK: - Daily task: completion toggle

    func testDailyTaskToggleUndoRedo() throws {
        let c = try makeContext()
        let page = DailyPage(date: Date()); c.insert(page)
        let task = DailyPageTask(title: "Stretch", sourceType: .manual)
        task.page = page; c.insert(task); try c.save()

        let before = TaskSnapshot(task)
        task.completed = true; task.completedAt = Date(); try c.save()
        Undo.edited("Complete task", before: before, after: TaskSnapshot(task))

        UndoStore.shared.undo(context: c)
        XCTAssertEqual(fetchTask(task.id, c)?.completed, false)
        UndoStore.shared.redo(context: c)
        XCTAssertEqual(fetchTask(task.id, c)?.completed, true)
    }

    func testDailyTaskDeleteUndoRestoresOnPage() throws {
        let c = try makeContext()
        let page = DailyPage(date: Date()); c.insert(page)
        let task = DailyPageTask(title: "Walk", sourceType: .manual)
        task.page = page; c.insert(task); try c.save()
        let id = task.id
        Undo.deleted("Delete task", TaskSnapshot(task))
        page.tasks.removeAll { $0.id == id }; c.delete(task); try c.save()
        XCTAssertEqual(page.tasks.count, 0)

        UndoStore.shared.undo(context: c)
        let restored = fetchTask(id, c)
        XCTAssertEqual(restored?.title, "Walk")
        XCTAssertEqual(restored?.page?.id, page.id)
    }

    // MARK: - Redo stack invalidation

    func testNewActionClearsRedo() throws {
        let c = try makeContext()
        let a = BacklogItem(title: "A"); c.insert(a); try c.save()
        Undo.created("Add backlog item", BacklogItemSnapshot(a))
        UndoStore.shared.undo(context: c)
        XCTAssertTrue(UndoStore.shared.canRedo)

        // A brand-new action wipes the redo history.
        let b = BacklogItem(title: "B"); c.insert(b); try c.save()
        Undo.created("Add backlog item", BacklogItemSnapshot(b))
        XCTAssertFalse(UndoStore.shared.canRedo)
    }

    // MARK: - Coalescing (a drag-reorder burst is one action)

    func testCoalescingMergesBurst() throws {
        let c = try makeContext()
        let item = BacklogItem(title: "A"); c.insert(item); try c.save()
        let snapA = BacklogItemSnapshot(item)
        item.title = "B"; try c.save(); let snapB = BacklogItemSnapshot(item)
        item.title = "C"; try c.save(); let snapC = BacklogItemSnapshot(item)

        Undo.record("Reorder", undoOps: [.upsert(snapA)], redoOps: [.upsert(snapB)], coalesceKey: "k")
        Undo.record("Reorder", undoOps: [.upsert(snapB)], redoOps: [.upsert(snapC)], coalesceKey: "k")
        XCTAssertEqual(UndoStore.shared.undoStack.count, 1)   // merged into one

        UndoStore.shared.undo(context: c)   // restores the PRE-burst value
        XCTAssertEqual(fetchBacklog(item.id, c)?.title, "A")
        UndoStore.shared.redo(context: c)   // applies the FINAL value
        XCTAssertEqual(fetchBacklog(item.id, c)?.title, "C")
    }

    // MARK: - Depth cap

    func testDepthCap() {
        for i in 0..<60 { Undo.record("x\(i)", undoOps: [], redoOps: []) }
        XCTAssertEqual(UndoStore.shared.undoStack.count, 50)
    }

    // MARK: - Container reconcile (Routines editor: parent + children)

    func testRoutineContainerCreateUndoRedo() throws {
        let c = try makeContext()
        let routine = Routine(title: "Morning"); c.insert(routine)
        let item = RoutineItem(text: "Water", sortOrder: 0); item.routine = routine
        c.insert(item); try c.save()
        let rid = routine.id

        // Recorded as a create (no before-state).
        Undo.recordContainer("Add routine",
            beforeParent: RoutineSnapshot?.none, beforeChildren: [RoutineItemSnapshot](),
            afterParent: RoutineSnapshot(routine), afterChildren: [RoutineItemSnapshot(item)])

        UndoStore.shared.undo(context: c)     // removes routine (and cascades the item)
        XCTAssertNil(fetchRoutine(rid, c))
        UndoStore.shared.redo(context: c)     // recreates routine + item
        let back = fetchRoutine(rid, c)
        XCTAssertEqual(back?.id, rid)
        XCTAssertEqual(back?.items.count, 1)
        XCTAssertEqual(back?.items.first?.text, "Water")
    }

    func testRoutineContainerEditAddsAndRemovesChildren() throws {
        let c = try makeContext()
        let routine = Routine(title: "R"); c.insert(routine)
        let keep = RoutineItem(text: "Keep", sortOrder: 0); keep.routine = routine
        let drop = RoutineItem(text: "Drop", sortOrder: 1); drop.routine = routine
        c.insert(keep); c.insert(drop); try c.save()

        let beforeParent = RoutineSnapshot(routine)
        let beforeChildren = [RoutineItemSnapshot(keep), RoutineItemSnapshot(drop)]

        // Simulate the session: remove `drop`, add `added`.
        routine.items.removeAll { $0.id == drop.id }; c.delete(drop)
        let added = RoutineItem(text: "Added", sortOrder: 1); added.routine = routine
        c.insert(added); try c.save()

        let afterParent = RoutineSnapshot(routine)
        let afterChildren = [RoutineItemSnapshot(keep), RoutineItemSnapshot(added)]
        Undo.recordContainer("Edit routine",
            beforeParent: beforeParent, beforeChildren: beforeChildren,
            afterParent: afterParent, afterChildren: afterChildren)

        UndoStore.shared.undo(context: c)     // back to {Keep, Drop}
        var texts = Set(fetchRoutine(routine.id, c)?.items.map { $0.text } ?? [])
        XCTAssertEqual(texts, ["Keep", "Drop"])
        UndoStore.shared.redo(context: c)     // forward to {Keep, Added}
        texts = Set(fetchRoutine(routine.id, c)?.items.map { $0.text } ?? [])
        XCTAssertEqual(texts, ["Keep", "Added"])
    }

    // MARK: - Fetch helpers

    private func fetchBacklog(_ id: String, _ c: ModelContext) -> BacklogItem? {
        try? c.fetch(FetchDescriptor<BacklogItem>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchTask(_ id: String, _ c: ModelContext) -> DailyPageTask? {
        try? c.fetch(FetchDescriptor<DailyPageTask>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetchRoutine(_ id: String, _ c: ModelContext) -> Routine? {
        try? c.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id })).first
    }
}
