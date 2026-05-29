import Foundation

// DailyPageGenerator is a pure struct — no SwiftData imports.
// It receives plain data and returns generated task lists.
// The repository layer owns SwiftData; this service owns the logic.

public struct GeneratedTask: Sendable {
    public let title: String
    public let notes: String
    public let sourceType: DailyTaskSourceType
    public let sourceId: String?
    public let sortOrder: Int

    public init(
        title: String,
        notes: String,
        sourceType: DailyTaskSourceType,
        sourceId: String?,
        sortOrder: Int
    ) {
        self.title = title
        self.notes = notes
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.sortOrder = sortOrder
    }
}

public struct GeneratedPage: Sendable {
    public let date: Date
    public let tasks: [GeneratedTask]
    public let scheduleBlocks: [DailyPageScheduleBlock]

    public init(date: Date, tasks: [GeneratedTask], scheduleBlocks: [DailyPageScheduleBlock]) {
        self.date = date
        self.tasks = tasks
        self.scheduleBlocks = scheduleBlocks
    }
}

public struct RecurringTaskInput: Sendable {
    public let id: String
    public let title: String
    public let notes: String
    public let rule: RecurrenceRule
    public let active: Bool

    public init(id: String, title: String, notes: String, rule: RecurrenceRule, active: Bool) {
        self.id = id
        self.title = title
        self.notes = notes
        self.rule = rule
        self.active = active
    }
}

public struct BacklogTaskInput: Sendable {
    public let id: String
    public let title: String
    public let assignedDate: Date?
    public let status: BacklogStatus

    public init(id: String, title: String, assignedDate: Date?, status: BacklogStatus) {
        self.id = id
        self.title = title
        self.assignedDate = assignedDate
        self.status = status
    }
}

public struct ScheduleBlockInput: Sendable {
    public let id: String
    public let title: String
    public let startMinuteOfDay: Int
    public let endMinuteOfDay: Int
    public let sortOrder: Int
    public let templateIsEnabled: Bool
    public let templateAssignedWeekdays: [Int]
    public let templateCustomDateStart: Date?
    public let templateCustomDateEnd: Date?

    public init(
        id: String,
        title: String,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        sortOrder: Int,
        templateIsEnabled: Bool,
        templateAssignedWeekdays: [Int],
        templateCustomDateStart: Date?,
        templateCustomDateEnd: Date?
    ) {
        self.id = id
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.sortOrder = sortOrder
        self.templateIsEnabled = templateIsEnabled
        self.templateAssignedWeekdays = templateAssignedWeekdays
        self.templateCustomDateStart = templateCustomDateStart
        self.templateCustomDateEnd = templateCustomDateEnd
    }
}

public struct DailyPageGenerator: Sendable {
    private let engine = RecurrenceEngine()

    public init() {}

    // MARK: - activeScheduleBlocks(for:from:calendar:)

    /// Determine which schedule template blocks apply to this date.
    /// Custom date range (customDateStart/End) overrides weekday assignment.
    /// Disabled templates (templateIsEnabled == false) produce no blocks.
    ///
    /// Selection priority:
    ///   1. First enabled template whose custom date range contains the date.
    ///   2. First enabled template whose assignedWeekdays contains the date's weekday.
    /// Returns an empty array if no template matches.
    public func activeScheduleBlocks(
        for date: Date,
        from templates: [ScheduleBlockInput],
        calendar: Calendar = .current
    ) -> [DailyPageScheduleBlock] {
        let dayStart = calendar.startOfDay(for: date)

        // Group templates by their source template identity so we can collect
        // all blocks from the winning template.
        // ScheduleBlockInput represents a single block row, not the parent template.
        // We need to pick a winning "template group" then return all its blocks.
        // Templates are identified by matching (templateIsEnabled, templateAssignedWeekdays,
        // templateCustomDateStart, templateCustomDateEnd) — but that can collide.
        // The safest approach: build a stable template key from the shared template metadata
        // and group blocks by that key, then pick the first matching group.

        // Build an ordered list of unique template groups preserving input order.
        struct TemplateKey: Hashable {
            let isEnabled: Bool
            let assignedWeekdays: [Int]
            let customDateStart: Date?
            let customDateEnd: Date?
        }

        var seen = Set<TemplateKey>()
        var orderedKeys: [TemplateKey] = []
        var groupedBlocks: [TemplateKey: [ScheduleBlockInput]] = [:]

        for block in templates {
            let key = TemplateKey(
                isEnabled: block.templateIsEnabled,
                assignedWeekdays: block.templateAssignedWeekdays,
                customDateStart: block.templateCustomDateStart,
                customDateEnd: block.templateCustomDateEnd
            )
            if seen.insert(key).inserted {
                orderedKeys.append(key)
            }
            groupedBlocks[key, default: []].append(block)
        }

        let weekday = calendar.component(.weekday, from: date)

        // Phase 1: look for an enabled template whose custom date range contains date.
        var winningKey: TemplateKey? = nil
        for key in orderedKeys {
            guard key.isEnabled else { continue }
            guard let start = key.customDateStart, let end = key.customDateEnd else { continue }
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            if dayStart >= startDay && dayStart <= endDay {
                winningKey = key
                break
            }
        }

        // Phase 2: fall back to weekday-assigned templates.
        if winningKey == nil {
            for key in orderedKeys {
                guard key.isEnabled else { continue }
                // Skip templates that are custom-date-range templates (they did not match above).
                if key.customDateStart != nil || key.customDateEnd != nil { continue }
                if key.assignedWeekdays.contains(weekday) {
                    winningKey = key
                    break
                }
            }
        }

        guard let winner = winningKey, let blocks = groupedBlocks[winner] else {
            return []
        }

        return blocks
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { block in
                DailyPageScheduleBlock(
                    id: block.id,
                    title: block.title,
                    startMinuteOfDay: block.startMinuteOfDay,
                    endMinuteOfDay: block.endMinuteOfDay,
                    sortOrder: block.sortOrder
                )
            }
    }

    // MARK: - generate(date:recurringTemplates:backlogItems:scheduleTemplates:calendar:)

    /// Generate the full task list for a date.
    /// - recurringTemplates: all RecurringTaskInput records (active or inactive).
    /// - backlogItems: ALL backlog items; filtered here by assignedDate and status.
    /// - sortOrder: recurring tasks first (sorted by title, 0-based), then backlog (sorted by title, continuing index).
    public func generate(
        date: Date,
        recurringTemplates: [RecurringTaskInput],
        backlogItems: [BacklogTaskInput],
        scheduleTemplates: [ScheduleBlockInput],
        calendar: Calendar = .current
    ) -> GeneratedPage {
        // 1. Filter active recurring templates that match this date.
        let matchingRecurring = recurringTemplates
            .filter { $0.active && engine.matches($0.rule, on: date, calendar: calendar) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        // 2. Filter backlog items assigned to this date that are still in backlog status.
        let matchingBacklog = backlogItems
            .filter { item in
                guard item.status == .backlog, let assigned = item.assignedDate else { return false }
                return calendar.isDate(assigned, inSameDayAs: date)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        // 3. Build GeneratedTask arrays.
        var tasks: [GeneratedTask] = []

        for (index, template) in matchingRecurring.enumerated() {
            tasks.append(GeneratedTask(
                title: template.title,
                notes: template.notes,
                sourceType: .recurring,
                sourceId: template.id,
                sortOrder: index
            ))
        }

        let recurringCount = matchingRecurring.count

        for (index, item) in matchingBacklog.enumerated() {
            tasks.append(GeneratedTask(
                title: item.title,
                notes: "",
                sourceType: .backlog,
                sourceId: item.id,
                sortOrder: recurringCount + index
            ))
        }

        // 4. Resolve schedule blocks.
        let scheduleBlocks = activeScheduleBlocks(for: date, from: scheduleTemplates, calendar: calendar)

        return GeneratedPage(date: date, tasks: tasks, scheduleBlocks: scheduleBlocks)
    }

    // MARK: - refresh(existing:recurringTemplates:backlogItems:scheduleTemplates:calendar:)

    /// Refresh an existing page from current templates.
    ///
    /// Rules:
    ///   - Keep manual tasks exactly as-is.
    ///   - Keep existing recurring/backlog tasks that still match (preserve completion state).
    ///   - Add new recurring/backlog tasks that now match but were not on the page.
    ///   - Remove recurring/backlog tasks whose source template no longer matches this date.
    ///   - Refresh schedule blocks from current templates.
    ///   - Never call this on past pages (caller's responsibility).
    public func refresh(
        existing: DailyPage,
        recurringTemplates: [RecurringTaskInput],
        backlogItems: [BacklogTaskInput],
        scheduleTemplates: [ScheduleBlockInput],
        calendar: Calendar = .current
    ) -> (tasksToAdd: [GeneratedTask], taskIdsToRemove: [String], newScheduleBlocks: [DailyPageScheduleBlock]) {
        let date = existing.date

        // Compute the full desired task set for this date.
        let desiredPage = generate(
            date: date,
            recurringTemplates: recurringTemplates,
            backlogItems: backlogItems,
            scheduleTemplates: scheduleTemplates,
            calendar: calendar
        )

        // Build lookup sets for desired recurring and backlog source IDs.
        let desiredRecurringSourceIds = Set(
            desiredPage.tasks
                .filter { $0.sourceType == .recurring }
                .compactMap { $0.sourceId }
        )
        let desiredBacklogSourceIds = Set(
            desiredPage.tasks
                .filter { $0.sourceType == .backlog }
                .compactMap { $0.sourceId }
        )

        // Determine existing tasks on the page (safe to read; no mutations).
        let existingTasks = existing.tasks

        // IDs of existing recurring/backlog tasks whose source no longer applies.
        var taskIdsToRemove: [String] = []

        // Source IDs already covered by existing tasks (to avoid duplicating).
        var existingRecurringSourceIds = Set<String>()
        var existingBacklogSourceIds = Set<String>()

        for task in existingTasks {
            switch task.sourceType {
            case .manual, .calendar:
                // Always kept — never touched.
                break
            case .recurring:
                if let sid = task.sourceId {
                    if desiredRecurringSourceIds.contains(sid) {
                        existingRecurringSourceIds.insert(sid)
                    } else {
                        taskIdsToRemove.append(task.id)
                    }
                } else {
                    // Recurring task with no sourceId — remove it (orphaned).
                    taskIdsToRemove.append(task.id)
                }
            case .backlog:
                if let sid = task.sourceId {
                    if desiredBacklogSourceIds.contains(sid) {
                        existingBacklogSourceIds.insert(sid)
                    } else {
                        taskIdsToRemove.append(task.id)
                    }
                } else {
                    // Backlog task with no sourceId — remove it (orphaned).
                    taskIdsToRemove.append(task.id)
                }
            }
        }

        // Determine the highest existing sortOrder so new tasks are appended after.
        let maxExistingSortOrder = existingTasks.map { $0.sortOrder }.max() ?? -1
        var nextSortOrder = maxExistingSortOrder + 1

        // New tasks to add: desired tasks whose source is not yet on the page.
        var tasksToAdd: [GeneratedTask] = []

        // Add new recurring tasks (sorted by title, consistent with generate()).
        let newRecurring = desiredPage.tasks
            .filter { $0.sourceType == .recurring }
            .filter { task in
                guard let sid = task.sourceId else { return false }
                return !existingRecurringSourceIds.contains(sid)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        for task in newRecurring {
            tasksToAdd.append(GeneratedTask(
                title: task.title,
                notes: task.notes,
                sourceType: .recurring,
                sourceId: task.sourceId,
                sortOrder: nextSortOrder
            ))
            nextSortOrder += 1
        }

        // Add new backlog tasks (sorted by title, consistent with generate()).
        let newBacklog = desiredPage.tasks
            .filter { $0.sourceType == .backlog }
            .filter { task in
                guard let sid = task.sourceId else { return false }
                return !existingBacklogSourceIds.contains(sid)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        for task in newBacklog {
            tasksToAdd.append(GeneratedTask(
                title: task.title,
                notes: task.notes,
                sourceType: .backlog,
                sourceId: task.sourceId,
                sortOrder: nextSortOrder
            ))
            nextSortOrder += 1
        }

        // Refresh schedule blocks.
        let newScheduleBlocks = activeScheduleBlocks(for: date, from: scheduleTemplates, calendar: calendar)

        return (tasksToAdd: tasksToAdd, taskIdsToRemove: taskIdsToRemove, newScheduleBlocks: newScheduleBlocks)
    }
}
