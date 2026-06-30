import Foundation
import SwiftData

// Value snapshots of every @Model type that participates in undo/redo. A snapshot
// captures ALL stored fields (and relationships as stable String ids), so an
// action can be reversed by RE-CREATING or RE-SETTING the object by id — surviving
// delete→recreate cycles where the live object reference would be stale.
//
// Two primitives express every reversible change:
//   • upsert(snapshot) — find the object by id and set its fields, or insert a fresh
//     one with that id if it's gone (undo of a delete / redo of a create).
//   • remove(type, id) — delete the object by id if present (undo of a create /
//     redo of a delete).
//
// An edit is `upsert(before)` to undo, `upsert(after)` to redo. A create is
// `remove` to undo, `upsert(after)` to redo. A delete is `upsert(before)` to undo,
// `remove` to redo. Parent+children deletes (a routine and its items, a project and
// its tasks) are just an ORDERED LIST of these ops (see the call sites).
//
// Calendar is deliberately out of scope: CalendarEventLocalState and calendar-sourced
// DailyPageTasks are never snapshotted here.

// MARK: - UndoSnapshot protocol

@MainActor
protocol UndoSnapshot {
    var id: String { get }
    func upsert(in context: ModelContext) throws
    static func remove(id: String, in context: ModelContext) throws
}

// MARK: - Reversible op (upsert / remove), type-erased for the stacks

struct UndoOp {
    let run: @MainActor (ModelContext) throws -> Void

    static func upsert<S: UndoSnapshot>(_ snapshot: S) -> UndoOp {
        UndoOp { try snapshot.upsert(in: $0) }
    }
    static func remove<S: UndoSnapshot>(_ type: S.Type, _ id: String) -> UndoOp {
        UndoOp { try S.remove(id: id, in: $0) }
    }
}

// MARK: - Fetch-by-id helpers (one per @Model; #Predicate needs a concrete keypath)

@MainActor private func fetchOne<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, _ c: ModelContext) -> T? {
    var d = descriptor; d.fetchLimit = 1
    return (try? c.fetch(d))?.first
}
@MainActor private func fetchTask(_ id: String, _ c: ModelContext) -> DailyPageTask? {
    fetchOne(FetchDescriptor<DailyPageTask>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchPage(_ id: String, _ c: ModelContext) -> DailyPage? {
    fetchOne(FetchDescriptor<DailyPage>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchBacklogItem(_ id: String, _ c: ModelContext) -> BacklogItem? {
    fetchOne(FetchDescriptor<BacklogItem>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchProject(_ id: String, _ c: ModelContext) -> ProjectBucket? {
    fetchOne(FetchDescriptor<ProjectBucket>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchRecurring(_ id: String, _ c: ModelContext) -> RecurringTaskTemplate? {
    fetchOne(FetchDescriptor<RecurringTaskTemplate>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchReminder(_ id: String, _ c: ModelContext) -> NotificationReminder? {
    fetchOne(FetchDescriptor<NotificationReminder>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchScheduleTemplate(_ id: String, _ c: ModelContext) -> ScheduleTemplate? {
    fetchOne(FetchDescriptor<ScheduleTemplate>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchExerciseRoutine(_ id: String, _ c: ModelContext) -> ExerciseRoutine? {
    fetchOne(FetchDescriptor<ExerciseRoutine>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchExerciseItem(_ id: String, _ c: ModelContext) -> ExerciseRoutineItem? {
    fetchOne(FetchDescriptor<ExerciseRoutineItem>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchRoutine(_ id: String, _ c: ModelContext) -> Routine? {
    fetchOne(FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id }), c)
}
@MainActor private func fetchRoutineItem(_ id: String, _ c: ModelContext) -> RoutineItem? {
    fetchOne(FetchDescriptor<RoutineItem>(predicate: #Predicate { $0.id == id }), c)
}

// MARK: - DailyPageTask

struct TaskSnapshot: UndoSnapshot {
    let id: String
    let pageId: String?
    let sourceType: DailyTaskSourceType
    let sourceId: String?
    let title: String
    let notes: String
    let completed: Bool
    let completedAt: Date?
    let sortOrder: Int

    @MainActor init(_ t: DailyPageTask) {
        id = t.id; pageId = t.page?.id
        sourceType = t.sourceType; sourceId = t.sourceId
        title = t.title; notes = t.notes
        completed = t.completed; completedAt = t.completedAt; sortOrder = t.sortOrder
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let task: DailyPageTask
        if let existing = fetchTask(id, c) {
            task = existing
        } else {
            task = DailyPageTask(title: title, sourceType: sourceType, sourceId: sourceId, sortOrder: sortOrder)
            task.id = id
            c.insert(task)
        }
        task.sourceType = sourceType; task.sourceId = sourceId
        task.title = title; task.notes = notes
        task.completed = completed; task.completedAt = completedAt; task.sortOrder = sortOrder
        if let pid = pageId, let page = fetchPage(pid, c) {
            if task.page?.id != page.id { task.page = page }   // inverse keeps page.tasks in sync
            if sourceType == .recurring, let sourceId {
                page.unhideRecurringTask(id: sourceId)
            }
            _ = CompletionService().recalculate(page: page)
            page.updatedAt = Date()
        }
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let task = fetchTask(id, c) else { return }
        let page = task.page
        if task.sourceType == .recurring,
           let sourceId = task.sourceId,
           let page {
            page.hideRecurringTask(id: sourceId)
        }
        page?.tasks.removeAll { $0.id == id }
        c.delete(task)
        if let page { _ = CompletionService().recalculate(page: page); page.updatedAt = Date() }
        try c.save()
    }
}

// MARK: - BacklogItem

struct BacklogItemSnapshot: UndoSnapshot {
    let id: String
    let title: String
    let notes: String
    let assignedDate: Date?
    let status: BacklogStatus
    let projectId: String?
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ i: BacklogItem) {
        id = i.id; title = i.title; notes = i.notes; assignedDate = i.assignedDate
        status = i.status; projectId = i.project?.id; createdAt = i.createdAt; updatedAt = i.updatedAt
    }

    init(id: String, title: String, notes: String, assignedDate: Date?, status: BacklogStatus,
         projectId: String?, createdAt: Date, updatedAt: Date) {
        self.id = id; self.title = title; self.notes = notes; self.assignedDate = assignedDate
        self.status = status; self.projectId = projectId; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// A copy reassigned to a different project — models a project delete, which
    /// nullifies its items' `project` to Unorganized (projectId = nil).
    func reassigned(toProjectId pid: String?) -> BacklogItemSnapshot {
        BacklogItemSnapshot(id: id, title: title, notes: notes, assignedDate: assignedDate,
                            status: status, projectId: pid, createdAt: createdAt, updatedAt: updatedAt)
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let item: BacklogItem
        if let existing = fetchBacklogItem(id, c) { item = existing }
        else { item = BacklogItem(title: title); item.id = id; c.insert(item) }
        item.title = title; item.notes = notes; item.assignedDate = assignedDate
        item.status = status; item.createdAt = createdAt; item.updatedAt = updatedAt
        item.project = projectId.flatMap { fetchProject($0, c) }
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let item = fetchBacklogItem(id, c) else { return }
        c.delete(item); try c.save()
    }
}

// MARK: - ProjectBucket

struct ProjectSnapshot: UndoSnapshot {
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ p: ProjectBucket) {
        id = p.id; name = p.name; createdAt = p.createdAt; updatedAt = p.updatedAt
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let project: ProjectBucket
        if let existing = fetchProject(id, c) { project = existing }
        else { project = ProjectBucket(name: name); project.id = id; c.insert(project) }
        project.name = name; project.createdAt = createdAt; project.updatedAt = updatedAt
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let project = fetchProject(id, c) else { return }
        c.delete(project); try c.save()
    }
}

// MARK: - RecurringTaskTemplate

struct RecurringSnapshot: UndoSnapshot {
    let id: String
    let title: String
    let notes: String
    let rule: RecurrenceRule
    let active: Bool
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ t: RecurringTaskTemplate) {
        id = t.id; title = t.title; notes = t.notes; rule = t.recurrenceRule
        active = t.active; createdAt = t.createdAt; updatedAt = t.updatedAt
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let t: RecurringTaskTemplate
        if let existing = fetchRecurring(id, c) { t = existing }
        else { t = RecurringTaskTemplate(title: title, rule: rule); t.id = id; c.insert(t) }
        t.title = title; t.notes = notes; t.recurrenceRule = rule
        t.active = active; t.createdAt = createdAt; t.updatedAt = updatedAt
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let t = fetchRecurring(id, c) else { return }
        c.delete(t); try c.save()
    }
}

// MARK: - NotificationReminder

struct ReminderSnapshotModel: UndoSnapshot {
    let id: String
    let title: String
    let message: String
    let isEnabled: Bool
    let recurrenceMode: NotificationRecurrenceMode
    let weekdays: [Int]
    let fireHour: Int
    let fireMinute: Int
    let intervalMinutes: Int
    let windowStartMinute: Int
    let windowEndMinute: Int
    let soundMode: NotificationSoundMode
    let imageFilename: String?
    let attachedTaskId: String?
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ r: NotificationReminder) {
        id = r.id; title = r.title; message = r.message; isEnabled = r.isEnabled
        recurrenceMode = r.recurrenceMode; weekdays = r.weekdays
        fireHour = r.fireHour; fireMinute = r.fireMinute; intervalMinutes = r.intervalMinutes
        windowStartMinute = r.windowStartMinute; windowEndMinute = r.windowEndMinute
        soundMode = r.soundMode; imageFilename = r.imageFilename; attachedTaskId = r.attachedTaskId
        createdAt = r.createdAt; updatedAt = r.updatedAt
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let r: NotificationReminder
        if let existing = fetchReminder(id, c) { r = existing }
        else { r = NotificationReminder(title: title, message: message); r.id = id; c.insert(r) }
        r.title = title; r.message = message; r.isEnabled = isEnabled
        r.recurrenceMode = recurrenceMode; r.weekdays = weekdays
        r.fireHour = fireHour; r.fireMinute = fireMinute; r.intervalMinutes = intervalMinutes
        r.windowStartMinute = windowStartMinute; r.windowEndMinute = windowEndMinute
        r.soundMode = soundMode; r.imageFilename = imageFilename; r.attachedTaskId = attachedTaskId
        r.createdAt = createdAt; r.updatedAt = updatedAt
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let r = fetchReminder(id, c) else { return }
        c.delete(r); try c.save()
    }
}

// MARK: - ScheduleTemplate

struct ScheduleSnapshotModel: UndoSnapshot {
    let id: String
    let name: String
    let isEnabled: Bool
    let assignedWeekdays: [Int]
    let customDateStart: Date?
    let customDateEnd: Date?
    let blocks: [ScheduleBlock]
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ t: ScheduleTemplate) {
        id = t.id; name = t.name; isEnabled = t.isEnabled; assignedWeekdays = t.assignedWeekdays
        customDateStart = t.customDateStart; customDateEnd = t.customDateEnd; blocks = t.blocks
        createdAt = t.createdAt; updatedAt = t.updatedAt
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let t: ScheduleTemplate
        if let existing = fetchScheduleTemplate(id, c) { t = existing }
        else { t = ScheduleTemplate(name: name); t.id = id; c.insert(t) }
        t.name = name; t.isEnabled = isEnabled; t.assignedWeekdays = assignedWeekdays
        t.customDateStart = customDateStart; t.customDateEnd = customDateEnd; t.blocks = blocks
        t.createdAt = createdAt; t.updatedAt = updatedAt
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let t = fetchScheduleTemplate(id, c) else { return }
        c.delete(t); try c.save()
    }
}

// MARK: - ExerciseRoutine

struct ExerciseRoutineSnapshot: UndoSnapshot {
    let id: String
    let name: String
    let notes: String
    let rule: RecurrenceRule
    let active: Bool
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ r: ExerciseRoutine) {
        id = r.id; name = r.name; notes = r.notes; rule = r.recurrenceRule
        active = r.active; createdAt = r.createdAt; updatedAt = r.updatedAt
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let r: ExerciseRoutine
        if let existing = fetchExerciseRoutine(id, c) { r = existing }
        else { r = ExerciseRoutine(name: name, rule: rule); r.id = id; c.insert(r) }
        r.name = name; r.notes = notes; r.recurrenceRule = rule
        r.active = active; r.createdAt = createdAt; r.updatedAt = updatedAt
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let r = fetchExerciseRoutine(id, c) else { return }
        c.delete(r); try c.save()
    }
}

// MARK: - ExerciseRoutineItem

struct ExerciseItemSnapshot: UndoSnapshot {
    let id: String
    let routineId: String?
    let text: String
    let notes: String
    let sets: Int?
    let reps: Int?
    let sortOrder: Int

    @MainActor init(_ i: ExerciseRoutineItem) {
        id = i.id; routineId = i.routine?.id; text = i.text; notes = i.notes
        sets = i.sets; reps = i.reps; sortOrder = i.sortOrder
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let item: ExerciseRoutineItem
        if let existing = fetchExerciseItem(id, c) { item = existing }
        else { item = ExerciseRoutineItem(text: text, sortOrder: sortOrder); item.id = id; c.insert(item) }
        item.text = text; item.notes = notes; item.sets = sets; item.reps = reps; item.sortOrder = sortOrder
        if let rid = routineId, let routine = fetchExerciseRoutine(rid, c) {
            if item.routine?.id != routine.id { item.routine = routine }
            routine.updatedAt = Date()
        }
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let item = fetchExerciseItem(id, c) else { return }
        let routine = item.routine
        routine?.items.removeAll { $0.id == id }
        c.delete(item)
        routine?.updatedAt = Date()
        try c.save()
    }
}

// MARK: - Routine

struct RoutineSnapshot: UndoSnapshot {
    let id: String
    let title: String
    let emoji: String
    let notes: String
    let body: String
    let createdAt: Date
    let updatedAt: Date

    @MainActor init(_ r: Routine) {
        id = r.id; title = r.title; emoji = r.emoji; notes = r.notes; body = r.body
        createdAt = r.createdAt; updatedAt = r.updatedAt
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let r: Routine
        if let existing = fetchRoutine(id, c) { r = existing }
        else { r = Routine(title: title); r.id = id; c.insert(r) }
        r.title = title; r.emoji = emoji; r.notes = notes; r.body = body
        r.createdAt = createdAt; r.updatedAt = updatedAt
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let r = fetchRoutine(id, c) else { return }
        c.delete(r); try c.save()
    }
}

// MARK: - RoutineItem

struct RoutineItemSnapshot: UndoSnapshot {
    let id: String
    let routineId: String?
    let text: String
    let notes: String
    let sortOrder: Int

    @MainActor init(_ i: RoutineItem) {
        id = i.id; routineId = i.routine?.id; text = i.text; notes = i.notes; sortOrder = i.sortOrder
    }

    @MainActor func upsert(in c: ModelContext) throws {
        let item: RoutineItem
        if let existing = fetchRoutineItem(id, c) { item = existing }
        else { item = RoutineItem(text: text, sortOrder: sortOrder); item.id = id; c.insert(item) }
        item.text = text; item.notes = notes; item.sortOrder = sortOrder
        if let rid = routineId, let routine = fetchRoutine(rid, c) {
            if item.routine?.id != routine.id { item.routine = routine }
            routine.updatedAt = Date()
        }
        try c.save()
    }

    @MainActor static func remove(id: String, in c: ModelContext) throws {
        guard let item = fetchRoutineItem(id, c) else { return }
        let routine = item.routine
        routine?.items.removeAll { $0.id == id }
        c.delete(item)
        routine?.updatedAt = Date()
        try c.save()
    }
}
