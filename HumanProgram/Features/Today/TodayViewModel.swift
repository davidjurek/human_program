import Foundation
import Observation
import SwiftData

@Observable
@MainActor
public final class TodayViewModel {
    public private(set) var page: DailyPage?
    public private(set) var exerciseRoutine: ExerciseRoutine? = nil
    public private(set) var isLoading: Bool = false
    public var showDatePicker: Bool = false
    public var showAddTask: Bool = false
    public var newTaskTitle: String = ""

    private var _viewingDate: Date
    public var viewingDate: Date {
        get { _viewingDate }
        set {
            relockCurrentIfPast()   // leaving this day re-locks it
            _viewingDate = Calendar.current.startOfDay(for: newValue)
            Task { await loadPage() }
        }
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
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        self._viewingDate = Calendar.current.startOfDay(for: Date())
        self.pageRepo = DailyPageRepository(context: context)
        self.backlogRepo = BacklogRepository(context: context)
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

    public var sortedTasks: [DailyPageTask] {
        (page?.tasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    public func loadPage() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let today = Calendar.current.startOfDay(for: Date())
            let recurringInputs = try fetchRecurringInputs()
            let backlogInputs = try fetchBacklogInputs()
            let scheduleInputs = try fetchScheduleInputs()
            page = try pageRepo.getOrCreate(
                date: viewingDate,
                today: today,
                recurringTemplates: recurringInputs,
                backlogItems: backlogInputs,
                scheduleTemplates: scheduleInputs
            )
            let exerciseRepo = ExerciseRepository(context: context)
            exerciseRoutine = try exerciseRepo.fetchRoutine(for: viewingDate)
        } catch {
            print("[TodayViewModel] loadPage error: \(error)")
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
            print("[TodayViewModel] toggleTask error: \(error)")
        }
    }

    public func addManualTask() async {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty,
              let p = page else { return }
        do {
            try pageRepo.addManualTask(title: newTaskTitle, to: p)
            newTaskTitle = ""
            showAddTask = false
        } catch {
            print("[TodayViewModel] addManualTask error: \(error)")
        }
    }

    public func deleteTask(_ task: DailyPageTask) async {
        guard let p = page else { return }
        do {
            try pageRepo.deleteTask(task, from: p)
        } catch {
            print("[TodayViewModel] deleteTask error: \(error)")
        }
    }

    public func unlockPastDay() async {
        guard let p = page else { return }
        do {
            try pageRepo.unlockPastPage(p)
        } catch {
            print("[TodayViewModel] unlockPastDay error: \(error)")
        }
    }

    public func relockPastDay() async {
        guard let p = page else { return }
        do {
            try pageRepo.lockPastPage(p)
        } catch {
            print("[TodayViewModel] relockPastDay error: \(error)")
        }
    }

    public func updateTask(_ task: DailyPageTask, title: String?, notes: String?) async {
        guard let p = page else { return }
        do {
            try pageRepo.updateTask(task, title: title, notes: notes, on: p)
            await loadPage()
        } catch {
            print("[TodayViewModel] updateTask error: \(error)")
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
        let items = (try? context.fetch(FetchDescriptor<BacklogItem>())) ?? []
        return items.first(where: { $0.id == sid })?.project?.name ?? "None"
    }

    // MARK: - Private template fetching

    private func fetchRecurringInputs() throws -> [RecurringTaskInput] {
        let templates = try context.fetch(FetchDescriptor<RecurringTaskTemplate>())
        return templates.map { RecurringTaskInput(id: $0.id, title: $0.title, notes: $0.notes, rule: $0.recurrenceRule, active: $0.active) }
    }

    private func fetchBacklogInputs() throws -> [BacklogTaskInput] {
        let items = try context.fetch(FetchDescriptor<BacklogItem>())
        return items.map { BacklogTaskInput(id: $0.id, title: $0.title, assignedDate: $0.assignedDate, status: $0.status) }
    }

    private func fetchScheduleInputs() throws -> [ScheduleBlockInput] {
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        return templates.flatMap { t in
            t.blocks.map { b in
                ScheduleBlockInput(id: b.id, title: b.title, startMinuteOfDay: b.startMinuteOfDay, endMinuteOfDay: b.endMinuteOfDay, sortOrder: b.sortOrder, templateIsEnabled: t.isEnabled, templateAssignedWeekdays: t.assignedWeekdays, templateCustomDateStart: t.customDateStart, templateCustomDateEnd: t.customDateEnd)
            }
        }
    }
}
