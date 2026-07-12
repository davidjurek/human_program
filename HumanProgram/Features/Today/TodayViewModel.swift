import Foundation
import Observation
import SwiftData

@Observable
@MainActor
public final class TodayViewModel {
    public private(set) var page: DailyPage?
    public private(set) var exerciseRoutine: ExerciseRoutine? = nil
    public var newTaskTitle: String = ""

    private var _viewingDate: Date
    /// Serializes page loads: a fast prev/next/jump cancels the previous in-flight load
    /// so two loads can't land out of order and briefly show a stale page. [#30]
    private var loadTask: Task<Void, Never>?
    public var viewingDate: Date {
        get { _viewingDate }
        set {
            relockCurrentIfPast()   // leaving this day re-locks it
            _viewingDate = Calendar.current.startOfDay(for: newValue)
            loadTask?.cancel()
            loadTask = Task { await loadPage() }
        }
    }

    /// One place to log a swallowed mutation error. The catch sites stay
    /// non-throwing (the UI keeps working); failures surface in the console with a
    /// consistent tag instead of a scattered `print` per method. [#106]
    private func logError(_ op: String, _ error: Error) {
        print("[TodayViewModel] \(op) error: \(error)")
    }

    /// Re-lock the currently-loaded page if it's an unlocked past day. Used when
    /// navigating to another day or leaving the Today screen.
    private func relockCurrentIfPast() {
        guard let p = page, !p.isPastLocked else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if p.date < today { try? pageRepo.lockPastPage(p) }
    }

    public func relockOnLeave() { relockCurrentIfPast() }

    private let pageRepo: DailyPageRepository
    private let backlogRepo: BacklogRepository
    private let exerciseRepo: ExerciseRepository
    private let calendarStateRepo: CalendarLocalStateRepository
    private let context: ModelContext

    /// `initialDate` opens the view on a specific day (e.g. the Stats calendar pushing
    /// an archived day within Stats); nil starts on today.
    public init(context: ModelContext, initialDate: Date? = nil) {
        self.context = context
        self._viewingDate = Calendar.current.startOfDay(for: initialDate ?? Date())
        self.pageRepo = DailyPageRepository(context: context)
        self.backlogRepo = BacklogRepository(context: context)
        self.exerciseRepo = ExerciseRepository(context: context)   // held, not rebuilt per load [#113]
        self.calendarStateRepo = CalendarLocalStateRepository(context: context)
    }

    /// Event ids the user has removed/hidden from Today on `date` — excluded from the
    /// schedule timeline and Tasks list, and surfaced in the Calendar reconciliation.
    public func hiddenCalendarIds(for date: Date) -> Set<String> {
        (try? calendarStateRepo.hiddenEventIds(for: date)) ?? []
    }

    /// Per-day calendar title overrides (eventId → overridden title) for `date`. The
    /// view uses these to show the renamed title in the timeline and to flag a renamed
    /// event as a difference in the top-right capsule. [calendar-override]
    public func calendarTitleOverrides(for date: Date) -> [String: String] {
        let states = (try? calendarStateRepo.fetchStates(for: date)) ?? []
        return Dictionary(states.compactMap { s in s.titleOverride.map { (s.eventId, $0) } },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Snapshot an event's per-day local state (hidden / overrides), or a clean default
    /// if no row exists yet — captured before a calendar mutation so undo can restore it.
    private func calendarStateSnapshot(eventId: String, date: Date) -> CalendarStateSnapshot {
        if let s = try? calendarStateRepo.existingState(eventId: eventId, date: date) {
            return CalendarStateSnapshot(s)
        }
        return CalendarStateSnapshot(defaultFor: eventId, date: date)
    }

    public var isToday: Bool {
        Calendar.current.isDateInToday(viewingDate)
    }

    public var isPastLocked: Bool {
        // Only trust the loaded page when it's actually the day being viewed. Page loads
        // are async, so right after a prev/next tap `page` can still be the PREVIOUS
        // day's — coloring the padlock from it caused a green→red flash. Until the
        // matching page lands, fall back to the correct default: past days open locked,
        // today/future unlocked. [today-lock-flash]
        if let p = page, Calendar.current.isDate(p.date, inSameDayAs: viewingDate) {
            return p.isPastLocked
        }
        return viewingDate < Calendar.current.startOfDay(for: Date())
    }

    public var isComplete: Bool {
        page?.dayComplete ?? false
    }

    /// Recurring/backlog items the templates say belong on the viewed day but that were
    /// deleted (hidden) from it — the task half of the Today "differences" report. Empty
    /// for past days (their differences are irrelevant — frozen snapshots). Calendar
    /// differences are added by the view (it already has the day's events). [today-diffs]
    var taskDifferences: [PageTaskDifference] {
        guard let p = page else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        guard p.date >= today else { return [] }
        guard let inputs = try? TemplateInputs.fetchAll(context: context) else { return [] }
        return TodayDifferenceEngine.taskDifferences(
            page: p, recurring: inputs.recurring, backlog: inputs.backlog, schedule: inputs.schedule)
    }

    // Flat display order: purely by sortOrder. Generation SEEDS this order
    // (recurring → calendar by start time → manual via zoned sortOrders assigned at
    // creation), but after that the user can hold-drag to reorder anything and that
    // custom order is authoritative — so nothing re-sorts by source group here. [#11]
    public var sortedTasks: [DailyPageTask] {
        (page?.tasks ?? []).sorted {
            $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder
                                         : $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }

    /// Persist a new top-to-bottom order after a hold-drag reorder. Reindexes every
    /// task's sortOrder to its position in `ordered` (0-based) so the custom order
    /// sticks and the flat sort reproduces it. Synchronous so the list updates in the
    /// same animation transaction as the drag release (no snap-back flash).
    public func reorderTasks(_ ordered: [DailyPageTask]) {
        guard let p = page else { return }
        let before = p.tasks.map { TaskSnapshot($0) }
        do {
            page = try pageRepo.reorderTasks(ordered, on: p)
            let after = (page?.tasks ?? []).map { TaskSnapshot($0) }
            // Only an actual order change is undoable (dropping in the same spot isn't).
            let beforeOrder = before.map { [$0.id: $0.sortOrder] }
            let afterOrder = after.map { [$0.id: $0.sortOrder] }
            if beforeOrder != afterOrder {
                Undo.record("Reorder tasks",
                            undoOps: before.map { .upsert($0) },
                            redoOps: after.map { .upsert($0) },
                            coalesceKey: "reorder-today")
            }
        } catch {
            logError("reorderTasks", error)
        }
    }

    public func loadPage() async {
        do {
            let today = Calendar.current.startOfDay(for: Date())
            let inputs = try TemplateInputs.fetchAll(context: context)
            page = try pageRepo.getOrCreate(
                date: viewingDate,
                today: today,
                recurringTemplates: inputs.recurring,
                backlogItems: inputs.backlog,
                scheduleTemplates: inputs.schedule
            )
            // Always ARRIVE at a past day locked. Unlocking is a transient in-session
            // action that auto-re-locks on leaving; if that re-lock ever misses, a past
            // page could stay unlocked and open editable. Re-locking on load guarantees
            // every past day opens locked (and removes the stale-unlocked case). [today-lock-flash]
            if let p = page, p.date < today, !p.isPastLocked {
                try? pageRepo.lockPastPage(p)
            }
            exerciseRoutine = try exerciseRepo.fetchRoutine(for: viewingDate)
            WidgetSync.refresh(context: context)
        } catch {
            logError("loadPage", error)
        }
    }

    /// Sync the chosen-calendar events for the viewing day into the Tasks list as
    /// `.calendar` tasks. Only today/future — past pages stay frozen snapshots.
    public func syncCalendarTasks(_ events: [CalendarTaskInput]) async {
        guard let p = page else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard p.date >= today else { return }
        do {
            page = try pageRepo.syncCalendarTasks(events, on: p)
        } catch {
            logError("syncCalendarTasks", error)
        }
    }

    /// Earliest day the user may navigate to: the install date, or the earliest stored
    /// page if a restored backup reaches further back. This floors backward navigation
    /// so you can't scroll into days before the app existed — and because navigation is
    /// clamped, back-stepping can never keep creating ever-earlier pages. [owner]
    public var minNavigableDate: Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let install = (UserDefaults.standard.object(forKey: DefaultsKey.installDate) as? Date)
            .map { cal.startOfDay(for: $0) } ?? todayStart
        if let earliest = (try? pageRepo.earliestPageDate()).flatMap({ $0 }) {
            return min(install, cal.startOfDay(for: earliest))
        }
        return install
    }

    /// False when the viewing day is already at the floor (left arrow should disable).
    public var canGoToPreviousDay: Bool {
        Calendar.current.startOfDay(for: viewingDate) > minNavigableDate
    }

    public func goToPreviousDay() {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .day, value: -1, to: viewingDate) else { return }
        // Floor: never navigate before the install date (or the earliest restored page).
        if cal.startOfDay(for: prev) < minNavigableDate { return }
        viewingDate = prev
    }

    public func goToNextDay() {
        viewingDate = Calendar.current.date(byAdding: .day, value: 1, to: viewingDate) ?? viewingDate
    }

    public func goToToday() {
        viewingDate = Calendar.current.startOfDay(for: Date())
    }

    public func jumpTo(date: Date) {
        // Clamp to the floor so the date picker can't jump before the install date.
        let target = Calendar.current.startOfDay(for: date)
        viewingDate = max(target, minNavigableDate)
    }

    public func toggleTask(_ task: DailyPageTask) async {
        guard let p = page else { return }
        // Completion lives on the page-task for every source (including calendar), and
        // survives calendar re-sync, so a toggle is a plain task edit — no local-state
        // op needed. Calendar completion toggles ARE undoable, but do NOT count as a
        // difference in the capsule. [calendar-undo]
        let before = TaskSnapshot(task)
        do {
            page = try pageRepo.toggleTask(task, on: p)
            let after = TaskSnapshot(task)
            Undo.edited((after.completed ? "Complete task " : "Uncomplete task ") + undoTitle(after.title),
                        before: before, after: after)
            WidgetSync.refresh(context: context)
        } catch {
            logError("toggleTask", error)
        }
    }

    /// Add a manual task and refresh the page itself, so callers don't need a
    /// follow-up loadPage (matches the other mutators). [#114]
    public func addManualTask() async {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty,
              let p = page else { return }
        let beforeIds = Set(p.tasks.map { $0.id })
        do {
            try pageRepo.addManualTask(title: newTaskTitle, to: p)
            newTaskTitle = ""
            await loadPage()
            if let created = page?.tasks.first(where: { !beforeIds.contains($0.id) }) {
                Undo.created("Add task " + undoTitle(created.title), TaskSnapshot(created))
            }
        } catch {
            logError("addManualTask", error)
        }
    }

    public func deleteTask(_ task: DailyPageTask) async {
        guard let p = page else { return }
        let taskBefore = TaskSnapshot(task)
        let today = Calendar.current.startOfDay(for: Date())
        // Deleting a calendar-sourced task on today/future records the event as hidden
        // so the next sync doesn't re-add it. Capture the local state before + after the
        // hide so undo can un-hide it (and re-add the task). (Past pages are frozen
        // snapshots — leave them alone.) [calendar-undo]
        var calStateBefore: CalendarStateSnapshot?
        var calStateAfter: CalendarStateSnapshot?
        if task.sourceType == .calendar, let eventId = task.sourceId, p.date >= today {
            calStateBefore = calendarStateSnapshot(eventId: eventId, date: p.date)
            try? calendarStateRepo.setHidden(true, eventId: eventId, date: p.date)
            calStateAfter = calendarStateSnapshot(eventId: eventId, date: p.date)
        }
        do {
            try pageRepo.deleteTask(task, from: p)
            if let sb = calStateBefore, let sa = calStateAfter {
                // undo: un-hide the event + re-add the task; redo: re-hide + remove it.
                Undo.record("Delete task " + undoTitle(taskBefore.title),
                            undoOps: [.upsert(sb), .upsert(taskBefore)],
                            redoOps: [.upsert(sa), .remove(TaskSnapshot.self, taskBefore.id)])
            } else {
                Undo.deleted("Delete task " + undoTitle(taskBefore.title), taskBefore)
            }
            WidgetSync.refresh(context: context)
        } catch {
            logError("deleteTask", error)
        }
    }

    public func unlockPastDay() async {
        guard let p = page else { return }
        do {
            try pageRepo.unlockPastPage(p)
        } catch {
            logError("unlockPastDay", error)
        }
    }

    public func relockPastDay() async {
        guard let p = page else { return }
        do {
            try pageRepo.lockPastPage(p)
        } catch {
            logError("relockPastDay", error)
        }
    }

    public func updateTask(_ task: DailyPageTask, title: String?, notes: String?) async {
        guard let p = page else { return }
        let isCalendar = task.sourceType == .calendar
        let today = Calendar.current.startOfDay(for: Date())
        let editsCalendarState = isCalendar && task.sourceId != nil && p.date >= today
        let taskBefore = TaskSnapshot(task)
        let calStateBefore = editsCalendarState ? calendarStateSnapshot(eventId: task.sourceId!, date: p.date) : nil
        do {
            // Write the visible copy on the page-task…
            try pageRepo.updateTask(task, title: title, notes: notes, on: p)
            // …and, for a calendar task, persist the edit as a per-day local override so
            // the next calendar re-sync doesn't overwrite it. The real EKEvent is never
            // touched. [calendar-override]
            if editsCalendarState, let eventId = task.sourceId {
                if let title { try? calendarStateRepo.setTitleOverride(title, eventId: eventId, date: p.date) }
                if let notes { try? calendarStateRepo.setNotesOverride(notes, eventId: eventId, date: p.date) }
            }
            let taskAfter = TaskSnapshot(task)
            let description = Self.taskEditDescription(before: taskBefore, after: taskAfter)
            if editsCalendarState, let eventId = task.sourceId, let sb = calStateBefore {
                let sa = calendarStateSnapshot(eventId: eventId, date: p.date)
                Undo.record(description,
                            undoOps: [.upsert(sb), .upsert(taskBefore)],
                            redoOps: [.upsert(sa), .upsert(taskAfter)])
            } else {
                Undo.edited(description, before: taskBefore, after: taskAfter)
            }
            await loadPage()
        } catch {
            logError("updateTask", error)
        }
    }

    /// A specific undo label for a Today task edit: states whether it was a rename
    /// or a note add/edit/remove (or both).
    private static func taskEditDescription(before: TaskSnapshot, after: TaskSnapshot) -> String {
        let name = undoTitle(after.title)
        let titleChanged = before.title != after.title
        let noteChanged = before.notes != after.notes
        if titleChanged && noteChanged { return "Edit task " + name }
        if titleChanged { return "Rename " + undoTitle(before.title) + " to " + name }
        if noteChanged {
            if before.notes.isEmpty { return "Add note to " + name }
            if after.notes.isEmpty { return "Remove note from " + name }
            return "Edit note of " + name
        }
        return "Edit task " + name
    }

    /// Human-readable source label for a task.
    public func sourceLabel(for task: DailyPageTask) -> String {
        switch task.sourceType {
        case .recurring: return "Recurring"
        case .backlog:   return "Backlog"
        case .manual:    return "Manual"
        case .calendar:  return "Calendar"
        }
    }

    /// Project name for a backlog-sourced task ("None" otherwise / if unassigned).
    public func projectName(for task: DailyPageTask) -> String {
        guard task.sourceType == .backlog, let sid = task.sourceId else { return "None" }
        // Fetch just the one matching item instead of loading the whole table. [#112/#187]
        var descriptor = FetchDescriptor<BacklogItem>(predicate: #Predicate { $0.id == sid })
        descriptor.fetchLimit = 1
        let item = (try? context.fetch(descriptor))?.first
        return item?.project?.name ?? "None"
    }

}
