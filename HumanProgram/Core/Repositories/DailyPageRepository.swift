import Foundation
import SwiftData

@MainActor
public final class DailyPageRepository {
    private let context: ModelContext
    private let generator = DailyPageGenerator()
    private let completionService = CompletionService()

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
        let normalizedDate = calendar.startOfDay(for: date)
        let normalizedToday = calendar.startOfDay(for: today)
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
                    calendar: calendar
                )
            }
            return existing
        }

        // Create a new page.
        let page = DailyPage(date: normalizedDate, createdAutomatically: true)
        page.isPastLocked = isPast
        context.insert(page)

        if isPast {
            // Past page: snapshot what would have been generated and lock it.
            let generated = generator.generate(
                date: normalizedDate,
                recurringTemplates: recurringTemplates,
                backlogItems: backlogItems,
                scheduleTemplates: scheduleTemplates,
                calendar: calendar
            )
            populatePage(page, from: generated)
        } else {
            // Today/future: generate fresh.
            let generated = generator.generate(
                date: normalizedDate,
                recurringTemplates: recurringTemplates,
                backlogItems: backlogItems,
                scheduleTemplates: scheduleTemplates,
                calendar: calendar
            )
            populatePage(page, from: generated)
        }

        completionService.recalculate(page: page)
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
        let normalizedToday = calendar.startOfDay(for: today)

        let descriptor = FetchDescriptor<DailyPage>()
        let allPages = try context.fetch(descriptor)

        for page in allPages {
            // Skip past-locked pages.
            guard !page.isPastLocked else { continue }
            // Skip pages that are before today (should be past-locked, but guard anyway).
            guard page.date >= normalizedToday else { continue }

            try applyRefresh(
                to: page,
                recurringTemplates: recurringTemplates,
                backlogItems: backlogItems,
                scheduleTemplates: scheduleTemplates,
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
        let nextSortOrder = (page.tasks.map { $0.sortOrder }.max() ?? -1) + 1
        let task = DailyPageTask(
            title: title,
            sourceType: .manual,
            sourceId: nil,
            sortOrder: nextSortOrder
        )
        task.page = page
        page.tasks.append(task)
        page.updatedAt = Date()
        context.insert(task)
        completionService.recalculate(page: page)
        try context.save()
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

    // MARK: - severPastTasks

    /// Sever past page-tasks from their backlog/calendar sources. Once a day is in
    /// the past (rolled over at 12:01 AM), its tasks become FROZEN SNAPSHOTS: their
    /// source tags (sourceType/sourceId) are cleared so completing them never
    /// affects the backlog/calendar, and reassigning a backlog item creates an
    /// independent new task while the past snapshot stays put. The backlog items and
    /// calendar events themselves are NOT touched.
    public func severPastTasks(today: Date, calendar: Calendar = .current) throws {
        let normalizedToday = calendar.startOfDay(for: today)
        let pages = try context.fetch(FetchDescriptor<DailyPage>())
        var changed = false
        for page in pages where page.date < normalizedToday {
            for task in page.tasks where task.sourceType != .manual || task.sourceId != nil {
                task.sourceType = .manual
                task.sourceId = nil
                changed = true
            }
        }
        if changed { try context.save() }
    }

    // MARK: - updateTask

    /// Update a task's title/notes (pass nil to leave unchanged). Used by the
    /// task-detail editor.
    public func updateTask(_ task: DailyPageTask, title: String? = nil, notes: String? = nil, on page: DailyPage) throws {
        if let title { task.title = title }
        if let notes { task.notes = notes }
        page.updatedAt = Date()
        try context.save()
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
        let normalizedDate = calendar.startOfDay(for: date)
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
        let descriptor = FetchDescriptor<DailyPage>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try context.fetch(descriptor)
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
        calendar: Calendar
    ) throws {
        let diff = generator.refresh(
            existing: page,
            recurringTemplates: recurringTemplates,
            backlogItems: backlogItems,
            scheduleTemplates: scheduleTemplates,
            calendar: calendar
        )

        // Remove stale tasks.
        let removeSet = Set(diff.taskIdsToRemove)
        let tasksToDelete = page.tasks.filter { removeSet.contains($0.id) }
        for task in tasksToDelete {
            page.tasks.removeAll { $0.id == task.id }
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

        completionService.recalculate(page: page)
    }
}
