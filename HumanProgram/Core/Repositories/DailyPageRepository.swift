import Foundation
import SwiftData

@MainActor
public final class DailyPageRepository {
    private let context: ModelContext
    private let generator = DailyPageGenerator()
    private let completionService = CompletionService()

    /// New calendar tasks get sortOrder = this base + event start-minute, placing the
    /// calendar group after recurring/backlog (small indices) and ordering it by
    /// start time on a freshly generated page. Manual tasks append after (max+1).
    static let calendarSortBase = 10_000

    /// The seed `sortOrder` for a freshly materialized calendar task: the calendar
    /// zone base offset by the event's start minute, so calendar tasks land after the
    /// recurring/backlog group and read earliest→latest. One place owns the zone math
    /// so the recurring → calendar → manual layering can't be broken by a stray
    /// offset. [#64]
    static func calendarSortOrder(startMinuteOfDay: Int) -> Int {
        calendarSortBase + startMinuteOfDay
    }

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - getOrCreate

    /// Returns the DailyPage for the given date. Creates it if it doesn't exist.
    /// Past pages (before today): created once and marked isPastLocked=true; never refreshed.
    /// Today and future pages: generated fresh or refreshed from current templates.
    public func getOrCreate(
        date: Date,
        today: Date,
        recurringTemplates: [RecurringTaskInput],
        backlogItems: [BacklogTaskInput],
        scheduleTemplates: [ScheduleBlockInput],
        calendar: Calendar = .current
    ) throws -> DailyPage {
        let normalizedDate = calendar.dayStart(date)
        let normalizedToday = calendar.dayStart(today)
        let isPast = normalizedDate < normalizedToday

        // Attempt to fetch existing page.
        if let existing = try fetch(date: normalizedDate, calendar: calendar) {
            // Past pages: never refresh from templates, just return as-is.
            if isPast {
                return existing
            }
            // Today/future: refresh from current templates (unless past-locked by caller).
            if !existing.isPastLocked {
                try applyRefresh(
                    to: existing,
                    recurringTemplates: recurringTemplates,
                    backlogItems: backlogItems,
                    scheduleTemplates: scheduleTemplates,
                    today: normalizedToday,
                    calendar: calendar
                )
                // applyRefresh mutates tasks/blocks/completion but does NOT save — persist
                // it here so a refresh is never left only in memory (matches every other
                // mutator in this repo). [#3]
                try context.save()
            }
            return existing
        }

        // Create a new page. The lock flag (set above) is the only past/today
        // difference — generation itself is identical, so it runs once. A past page
        // is just the same generated content, locked as a snapshot. [#66]
        let page = DailyPage(date: normalizedDate, createdAutomatically: true)
        page.isPastLocked = isPast
        context.insert(page)

        let generated = generator.generate(
            date: normalizedDate,
            recurringTemplates: recurringTemplates,
            backlogItems: backlogItems,
            scheduleTemplates: scheduleTemplates,
            calendar: calendar
        )
        populatePage(page, from: generated)

        completionService.recalculate(page: page, today: normalizedToday)
        try context.save()
        return page
    }

    // MARK: - refreshTodayAndFuture

    /// Refresh today's and future pages from current templates.
    /// Never touches pages where isPastLocked == true.
    public func refreshTodayAndFuture(
        today: Date,
        recurringTemplates: [RecurringTaskInput],
        backlogItems: [BacklogTaskInput],
        scheduleTemplates: [ScheduleBlockInput],
        calendar: Calendar = .current
    ) throws {
        let normalizedToday = calendar.dayStart(today)

        // Only load today/future pages from the store, not the whole history. [#186]
        let descriptor = FetchDescriptor<DailyPage>(
            predicate: #Predicate { $0.date >= normalizedToday }
        )
        let pages = try context.fetch(descriptor)

        for page in pages {
            // Skip past-locked pages (a future page should never be, but guard anyway).
            guard !page.isPastLocked else { continue }

            try applyRefresh(
                to: page,
                recurringTemplates: recurringTemplates,
                backlogItems: backlogItems,
                scheduleTemplates: scheduleTemplates,
                today: normalizedToday,
                calendar: calendar
            )
        }

        try context.save()
    }

    // MARK: - toggleTask

    /// Toggle task completion. Recalculates dayComplete. Returns the updated page.
    @discardableResult
    public func toggleTask(_ task: DailyPageTask, on page: DailyPage) throws -> DailyPage {
        task.completed.toggle()
        task.completedAt = task.completed ? Date() : nil
        page.updatedAt = Date()
        completionService.recalculate(page: page)
        try context.save()
        return page
    }

    // MARK: - addManualTask

    /// Add a manual task to a page.
    public func addManualTask(title: String, to page: DailyPage) throws {
        let task = DailyPageTask(
            title: title,
            sourceType: .manual,
            sourceId: nil,
            sortOrder: nextSortOrder(in: page.tasks) { $0.sortOrder }
        )
        task.page = page
        page.tasks.append(task)
        page.updatedAt = Date()
        context.insert(task)
        completionService.recalculate(page: page)
        try context.save()
    }

    // MARK: - reorderTasks

    /// Persist a user-defined top-to-bottom order: each task's sortOrder becomes its
    /// index in `ordered`. The flat sort in the view then reproduces this order.
    @discardableResult
    public func reorderTasks(_ ordered: [DailyPageTask], on page: DailyPage) throws -> DailyPage {
        applyReorder(ordered, set: { $0.sortOrder = $1 }, get: { $0.sortOrder })
        page.updatedAt = Date()
        try context.save()
        return page
    }

    // MARK: - deleteTask

    /// Delete a task from a page.
    public func deleteTask(_ task: DailyPageTask, from page: DailyPage) throws {
        page.tasks.removeAll { $0.id == task.id }
        context.delete(task)
        page.updatedAt = Date()
        completionService.recalculate(page: page)
        try context.save()
    }

    // MARK: - syncCalendarTasks

    /// Materialize the selected-calendar events for this page's date as `.calendar`
    /// tasks, so chosen calendar events flow into the Tasks list (and count toward
    /// completion). Idempotent: inserts tasks for new events, removes tasks whose
    /// event is gone (deleted, or its calendar deselected), and updates titles in
    /// place (completion state preserved). Calendar tasks sort within their group by
    /// event start time (sortOrder = start minute-of-day), so the Tasks list reads
    /// recurring → calendar (earliest→latest) → manual. Never touches past pages.
    @discardableResult
    public func syncCalendarTasks(_ events: [CalendarTaskInput], on page: DailyPage) throws -> DailyPage {
        guard !page.isPastLocked else { return page }

        var changed = false
        let incomingById = Dictionary(events.map { ($0.eventId, $0) }, uniquingKeysWith: { first, _ in first })
        let incomingIds = Set(incomingById.keys)

        // Remove calendar tasks whose event is no longer present. Collect first, then
        // delete — never mutate page.tasks while iterating it. [#65]
        let staleCalendarTasks = page.tasks.filter { task in
            task.sourceType == .calendar && !(task.sourceId.map { incomingIds.contains($0) } ?? false)
        }
        if !staleCalendarTasks.isEmpty {
            let staleIds = Set(staleCalendarTasks.map { $0.id })
            page.tasks.removeAll { staleIds.contains($0.id) }
            for task in staleCalendarTasks { context.delete(task) }
            changed = true
        }

        // Update titles of calendar tasks still present. Do NOT touch sortOrder here:
        // start time only SEEDS the order at creation; after that the user may have
        // hold-dragged tasks into a custom order, which must survive re-syncs.
        var existingIds = Set<String>()
        for task in page.tasks where task.sourceType == .calendar {
            guard let sid = task.sourceId, let ev = incomingById[sid] else { continue }
            existingIds.insert(sid)
            if task.title != ev.title { task.title = ev.title; changed = true }
        }

        // Insert tasks for newly-appeared events. Seed sortOrder in the "calendar
        // zone" (after recurring's small indices) ordered by start time, so a fresh
        // page reads recurring → calendar(earliest→latest) → manual.
        for ev in events where !existingIds.contains(ev.eventId) {
            let task = DailyPageTask(
                title: ev.title,
                sourceType: .calendar,
                sourceId: ev.eventId,
                sortOrder: Self.calendarSortOrder(startMinuteOfDay: ev.startMinuteOfDay)
            )
            task.page = page
            page.tasks.append(task)
            context.insert(task)
            changed = true
        }

        if changed {
            page.updatedAt = Date()
            completionService.recalculate(page: page)
            try context.save()
        }
        return page
    }

    // MARK: - severPastTasks

    /// Sever past page-tasks from their backlog/calendar sources. Once a day is in
    /// the past (rolled over at 12:01 AM), its tasks become FROZEN SNAPSHOTS: their
    /// source tags (sourceType/sourceId) are cleared so completing them never
    /// affects the backlog/calendar, and reassigning a backlog item creates an
    /// independent new task while the past snapshot stays put. The backlog items and
    /// calendar events themselves are NOT touched.
    public func severPastTasks(today: Date, calendar: Calendar = .current) throws {
        let normalizedToday = calendar.dayStart(today)
        // Only load past pages from the store, not the whole history. [#186]
        let pages = try context.fetch(
            FetchDescriptor<DailyPage>(predicate: #Predicate { $0.date < normalizedToday })
        )
        var changed = false
        for page in pages {
            for task in page.tasks where task.sourceType != .manual || task.sourceId != nil {
                task.sourceType = .manual
                task.sourceId = nil
                changed = true
            }
        }
        if changed { try context.save() }
    }

    // MARK: - completedBacklogTaskIds

    /// The backlog-item ids that have a COMPLETED backlog-sourced task on a PAST page
    /// (date < today). Used at day-rollover to decide which assigned-and-finished backlog
    /// items to remove from the backlog. MUST be read BEFORE `severPastTasks` clears the
    /// source tags, or the links are already gone.
    public func completedBacklogTaskIds(before today: Date, calendar: Calendar = .current) -> Set<String> {
        let normalizedToday = calendar.dayStart(today)
        guard let pages = try? context.fetch(
            FetchDescriptor<DailyPage>(predicate: #Predicate { $0.date < normalizedToday })
        ) else { return [] }
        var ids = Set<String>()
        for page in pages {
            for task in page.tasks where task.completed && task.sourceType == .backlog {
                if let sourceId = task.sourceId { ids.insert(sourceId) }
            }
        }
        return ids
    }

    // MARK: - updateTask

    /// Update a task's title/notes (pass nil to leave unchanged). Used by the
    /// task-detail editor.
    public func updateTask(_ task: DailyPageTask, title: String? = nil, notes: String? = nil, on page: DailyPage) throws {
        if let title { task.title = title }
        if let notes {
            task.notes = notes
            // Two-way note sync: a backlog-linked page-task keeps its source backlog
            // item's note in step. Past page-tasks are severed to .manual at rollover,
            // so they never match here — the link (and the sync) ends when the day
            // becomes a frozen snapshot, exactly as intended. [owner]
            if task.sourceType == .backlog, let sid = task.sourceId,
               let item = fetchBacklogItem(sid), item.notes != notes {
                item.notes = notes
                item.updatedAt = Date()
            }
        }
        page.updatedAt = Date()
        try context.save()
    }

    /// Propagate a backlog item's edited note to its linked page-tasks (the backlog →
    /// page-task half of the two-way note sync). Past page-tasks are severed to
    /// `.manual` at rollover, so a frozen snapshot's note is never matched or changed
    /// here. [owner]
    public func syncBacklogNoteToTasks(itemId: String, notes: String) throws {
        let tasks = try context.fetch(
            FetchDescriptor<DailyPageTask>(predicate: #Predicate { $0.sourceId == itemId })
        )
        var changed = false
        for task in tasks where task.sourceType == .backlog && task.notes != notes {
            task.notes = notes
            task.page?.updatedAt = Date()
            changed = true
        }
        if changed { try context.save() }
    }

    /// Fetch a backlog item by id (for the note-sync hop).
    private func fetchBacklogItem(_ id: String) -> BacklogItem? {
        var d = FetchDescriptor<BacklogItem>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    // MARK: - unlockPastPage

    /// Unlock a past page for editing. Sets isPastLocked=false.
    public func unlockPastPage(_ page: DailyPage) throws {
        page.isPastLocked = false
        page.updatedAt = Date()
        try context.save()
    }

    // MARK: - lockPastPage

    /// Lock a past page again.
    public func lockPastPage(_ page: DailyPage) throws {
        page.isPastLocked = true
        page.updatedAt = Date()
        try context.save()
    }

    // MARK: - fetch

    /// Fetch a page by date (nil if not found yet).
    public func fetch(date: Date, calendar: Calendar = .current) throws -> DailyPage? {
        let normalizedDate = calendar.dayStart(date)
        var descriptor = FetchDescriptor<DailyPage>(
            predicate: #Predicate { $0.date == normalizedDate }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        return results.first
    }

    // MARK: - fetchAll

    /// Fetch all pages (for streak calculation etc.)
    public func fetchAll() throws -> [DailyPage] {
        try context.fetchSorted(by: [SortDescriptor(\.date, order: .forward)])
    }

    /// The earliest stored page date (nil if none). Used to floor Today navigation: a
    /// .hprgm restore can insert pages older than the install date, and those must stay
    /// reachable.
    public func earliestPageDate() throws -> Date? {
        var d = FetchDescriptor<DailyPage>(sortBy: [SortDescriptor(\.date, order: .forward)])
        d.fetchLimit = 1
        return try context.fetch(d).first?.date
    }

    // MARK: - Private Helpers

    /// Populate a freshly created DailyPage from a GeneratedPage (no save).
    private func populatePage(_ page: DailyPage, from generated: GeneratedPage) {
        for genTask in generated.tasks {
            let task = DailyPageTask(
                title: genTask.title,
                sourceType: genTask.sourceType,
                sourceId: genTask.sourceId,
                sortOrder: genTask.sortOrder
            )
            task.notes = genTask.notes
            task.page = page
            page.tasks.append(task)
            context.insert(task)
        }
        page.scheduleBlocks = generated.scheduleBlocks
        page.updatedAt = Date()
    }

    /// Apply a refresh diff to an existing page (no save).
    private func applyRefresh(
        to page: DailyPage,
        recurringTemplates: [RecurringTaskInput],
        backlogItems: [BacklogTaskInput],
        scheduleTemplates: [ScheduleBlockInput],
        today: Date,
        calendar: Calendar
    ) throws {
        let diff = generator.refresh(
            existing: page,
            recurringTemplates: recurringTemplates,
            backlogItems: backlogItems,
            scheduleTemplates: scheduleTemplates,
            calendar: calendar
        )

        // Remove stale tasks in a single pass (not one removeAll scan per task). [#189]
        let removeSet = Set(diff.taskIdsToRemove)
        let tasksToDelete = page.tasks.filter { removeSet.contains($0.id) }
        page.tasks.removeAll { removeSet.contains($0.id) }
        for task in tasksToDelete {
            context.delete(task)
        }

        // Add new tasks.
        for genTask in diff.tasksToAdd {
            let task = DailyPageTask(
                title: genTask.title,
                sourceType: genTask.sourceType,
                sourceId: genTask.sourceId,
                sortOrder: genTask.sortOrder
            )
            task.notes = genTask.notes
            task.page = page
            page.tasks.append(task)
            context.insert(task)
        }

        // Refresh schedule blocks.
        page.scheduleBlocks = diff.newScheduleBlocks
        page.updatedAt = Date()

        completionService.recalculate(page: page, today: today)
    }
}
