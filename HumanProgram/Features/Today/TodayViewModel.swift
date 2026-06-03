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

    public init(context: ModelContext) {
        self.context = context
        self._viewingDate = Calendar.current.startOfDay(for: Date())
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

    public var isToday: Bool {
        Calendar.current.isDateInToday(viewingDate)
    }

    public var isPastLocked: Bool {
        page?.isPastLocked ?? false
    }

    public var isComplete: Bool {
        page?.dayComplete ?? false
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
        do {
            page = try pageRepo.reorderTasks(ordered, on: p)
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
            exerciseRoutine = try exerciseRepo.fetchRoutine(for: viewingDate)
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

    public func goToPreviousDay() {
        viewingDate = Calendar.current.date(byAdding: .day, value: -1, to: viewingDate) ?? viewingDate
    }

    public func goToNextDay() {
        viewingDate = Calendar.current.date(byAdding: .day, value: 1, to: viewingDate) ?? viewingDate
    }

    public func goToToday() {
        viewingDate = Calendar.current.startOfDay(for: Date())
    }

    public func jumpTo(date: Date) {
        viewingDate = Calendar.current.startOfDay(for: date)
    }

    public func toggleTask(_ task: DailyPageTask) async {
        guard let p = page else { return }
        do {
            page = try pageRepo.toggleTask(task, on: p)
        } catch {
            logError("toggleTask", error)
        }
    }

    /// Add a manual task and refresh the page itself, so callers don't need a
    /// follow-up loadPage (matches the other mutators). [#114]
    public func addManualTask() async {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty,
              let p = page else { return }
        do {
            try pageRepo.addManualTask(title: newTaskTitle, to: p)
            newTaskTitle = ""
            await loadPage()
        } catch {
            logError("addManualTask", error)
        }
    }

    public func deleteTask(_ task: DailyPageTask) async {
        guard let p = page else { return }
        // Deleting a calendar-sourced task on today/future records the event as hidden
        // so the next sync doesn't re-add it; the Calendar reconciliation page can
        // restore it later. (Past pages are frozen snapshots — leave them alone.)
        if task.sourceType == .calendar, let eventId = task.sourceId,
           p.date >= Calendar.current.startOfDay(for: Date()) {
            try? calendarStateRepo.setHidden(true, eventId: eventId, date: p.date)
        }
        do {
            try pageRepo.deleteTask(task, from: p)
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
        do {
            try pageRepo.updateTask(task, title: title, notes: notes, on: p)
            await loadPage()
        } catch {
            logError("updateTask", error)
        }
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
