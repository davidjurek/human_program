import Foundation
import SwiftData

@MainActor
struct HprgmImportService {

    // MARK: - Preview (decode without writing)

    /// Reads and decodes the bundle from a file URL without modifying any data.
    func preview(fileURL: URL) throws -> HprgmBundle {
        // Security-scoped resource access for files from the document picker
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { fileURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HprgmBundle.self, from: data)
    }

    // MARK: - Import (replace planner data)

    /// Replaces all planner data (except past-locked DailyPages and their tasks)
    /// with the contents of the provided bundle.
    ///
    /// Steps:
    ///   1. Delete all non-locked DailyPages and their tasks (cascade)
    ///   2. Delete all BacklogItems, ProjectBuckets, RecurringTaskTemplates
    ///   3. Delete all ExerciseRoutines (cascade deletes items), ScheduleTemplates, NotificationReminders
    ///   4. Insert new records from the bundle
    ///   5. Save the context
    func importData(_ bundle: HprgmBundle, context: ModelContext) throws {
        // ── 1. Delete ALL daily pages (tasks cascade-deleted automatically) ──
        // A restore is an explicit "REPLACES all current data" action, so it is a
        // faithful full restore: even past-locked snapshots are replaced by the
        // backup's pages (this is NOT the automatic refresh the snapshot rule guards).
        let pageDescriptor = FetchDescriptor<DailyPage>()
        let existingPages = try context.fetch(pageDescriptor)
        for page in existingPages {
            context.delete(page)
        }

        // ── 2. Delete backlog items, project buckets, recurring task templates ──
        let backlogDescriptor = FetchDescriptor<BacklogItem>()
        for item in try context.fetch(backlogDescriptor) {
            context.delete(item)
        }

        let bucketDescriptor = FetchDescriptor<ProjectBucket>()
        for bucket in try context.fetch(bucketDescriptor) {
            context.delete(bucket)
        }

        let recurringDescriptor = FetchDescriptor<RecurringTaskTemplate>()
        for template in try context.fetch(recurringDescriptor) {
            context.delete(template)
        }

        // ── 3. Delete exercise routines (cascade), schedule templates, notifications ──
        let exerciseDescriptor = FetchDescriptor<ExerciseRoutine>()
        for routine in try context.fetch(exerciseDescriptor) {
            context.delete(routine)
        }

        let scheduleDescriptor = FetchDescriptor<ScheduleTemplate>()
        for template in try context.fetch(scheduleDescriptor) {
            context.delete(template)
        }

        let notificationDescriptor = FetchDescriptor<NotificationReminder>()
        for reminder in try context.fetch(notificationDescriptor) {
            context.delete(reminder)
        }

        // Routines (cascade deletes their items) + calendar local state.
        for routine in try context.fetch(FetchDescriptor<Routine>()) {
            context.delete(routine)
        }
        for state in try context.fetch(FetchDescriptor<CalendarEventLocalState>()) {
            context.delete(state)
        }

        // ── 4. Insert records from the bundle ──

        // Project buckets first (backlog items reference them by id)
        var bucketLookup: [String: ProjectBucket] = [:]
        for json in bundle.projectBuckets {
            let bucket = ProjectBucket(name: json.name)
            bucket.id = json.id
            bucket.createdAt = json.createdAt
            bucket.updatedAt = json.updatedAt
            context.insert(bucket)
            bucketLookup[bucket.id] = bucket
        }

        // Backlog items
        for json in bundle.backlogItems {
            let item = BacklogItem(title: json.title)
            item.id = json.id
            item.notes = json.notes
            item.assignedDate = json.assignedDate
            item.status = json.status
            item.createdAt = json.createdAt
            item.updatedAt = json.updatedAt
            if let bucketId = json.projectBucketId {
                item.project = bucketLookup[bucketId]
            }
            context.insert(item)
        }

        // Recurring task templates
        for json in bundle.recurringTaskTemplates {
            let template = RecurringTaskTemplate(title: json.title, rule: json.recurrenceRule)
            template.id = json.id
            template.notes = json.notes
            template.active = json.active
            template.createdAt = json.createdAt
            template.updatedAt = json.updatedAt
            context.insert(template)
        }

        // Exercise routines and their items
        for json in bundle.exerciseRoutines {
            let routine = ExerciseRoutine(name: json.name, rule: json.recurrenceRule)
            routine.id = json.id
            routine.notes = json.notes
            routine.active = json.active
            routine.createdAt = json.createdAt
            routine.updatedAt = json.updatedAt
            context.insert(routine)

            for itemJSON in json.items {
                let item = ExerciseRoutineItem(text: itemJSON.text, sortOrder: itemJSON.sortOrder)
                item.id = itemJSON.id
                item.sets = itemJSON.sets
                item.reps = itemJSON.reps
                item.notes = itemJSON.notes
                item.routine = routine
                context.insert(item)
            }
        }

        // Schedule templates
        for json in bundle.scheduleTemplates {
            let template = ScheduleTemplate(name: json.name)
            template.id = json.id
            template.isEnabled = json.isEnabled
            template.assignedWeekdays = json.assignedWeekdays
            template.customDateStart = json.customDateStart
            template.customDateEnd = json.customDateEnd
            template.blocks = json.blocks
            template.createdAt = json.createdAt
            template.updatedAt = json.updatedAt
            context.insert(template)
        }

        // Daily pages — ALL of them, locked snapshots included, exactly as backed up.
        for json in bundle.dailyPages {
            let page = DailyPage(date: json.date, createdAutomatically: json.createdAutomatically)
            page.id = json.id
            page.dayComplete = json.dayComplete
            page.isPastLocked = json.isPastLocked
            page.scheduleBlocks = json.scheduleBlocks
            page.createdAt = json.createdAt
            page.updatedAt = json.updatedAt
            context.insert(page)

            for taskJSON in json.tasks {
                let task = DailyPageTask(
                    title: taskJSON.title,
                    sourceType: taskJSON.sourceType,
                    sourceId: taskJSON.sourceId,
                    sortOrder: taskJSON.sortOrder
                )
                task.id = taskJSON.id
                task.notes = taskJSON.notes
                task.completed = taskJSON.completed
                task.completedAt = taskJSON.completedAt
                task.page = page
                context.insert(task)
            }
        }

        // Notification reminders
        for json in bundle.notifications {
            let reminder = NotificationReminder(title: json.title, message: json.message)
            reminder.id = json.id
            reminder.isEnabled = json.isEnabled
            reminder.recurrenceMode = json.recurrenceMode
            reminder.weekdays = json.weekdays
            reminder.fireHour = json.fireHour
            reminder.fireMinute = json.fireMinute
            reminder.intervalMinutes = json.intervalMinutes
            reminder.windowStartMinute = json.windowStartMinute
            reminder.windowEndMinute = json.windowEndMinute
            reminder.soundMode = json.soundMode
            reminder.imageFilename = json.imageFilename
            reminder.attachedTaskId = json.attachedTaskId
            reminder.createdAt = json.createdAt
            reminder.updatedAt = json.updatedAt
            context.insert(reminder)
        }

        // Routines + their steps (format v2; absent in v1 backups).
        for json in bundle.routines ?? [] {
            let routine = Routine(title: json.title)
            routine.id = json.id
            routine.emoji = json.emoji
            routine.notes = json.notes
            routine.createdAt = json.createdAt
            routine.updatedAt = json.updatedAt
            context.insert(routine)
            for itemJSON in json.items {
                let item = RoutineItem(text: itemJSON.text, sortOrder: itemJSON.sortOrder)
                item.id = itemJSON.id
                item.notes = itemJSON.notes
                item.routine = routine
                context.insert(item)
            }
        }

        // Calendar local state (completion / hidden / overrides per event+date).
        for json in bundle.calendarEventStates ?? [] {
            let state = CalendarEventLocalState(date: json.date, eventId: json.eventId)
            state.completed = json.completed
            state.hidden = json.hidden
            state.titleOverride = json.titleOverride
            state.notesOverride = json.notesOverride
            state.sortOrder = json.sortOrder
            state.updatedAt = json.updatedAt
            context.insert(state)
        }

        // ── 5. Save ──
        try context.save()

        // ── 6. Restore user preferences (UserDefaults) — excludes PIN / Face ID. ──
        if let s = bundle.settings { applySettings(s) }
    }

    private func applySettings(_ s: AppSettingsJSON) {
        let d = UserDefaults.standard
        if let v = s.fontChoice { d.set(v, forKey: "settings.fontChoice") }
        if let v = s.fontSizeStep { d.set(v, forKey: "settings.fontSizeStep") }
        if let v = s.appearanceMode { d.set(v, forKey: "settings.appearanceMode") }
        if let v = s.appIcon { d.set(v, forKey: "settings.appIcon") }
        if let v = s.bgLight { d.set(v, forKey: "settings.bgLight") }
        if let v = s.bgDark { d.set(v, forKey: "settings.bgDark") }
        if let v = s.dateFormat { d.set(v, forKey: "settings.dateFormat") }
        if let v = s.timeFormat { d.set(v, forKey: "settings.timeFormat") }
        if let v = s.selectedCalendarIds { d.set(v, forKey: "selectedCalendarIds") }
    }
}
