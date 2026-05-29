import Foundation
import SwiftData

// MARK: - Codable Mirror Structs

struct BacklogItemJSON: Codable {
    let id: String
    let title: String
    let notes: String
    let projectBucketId: String?
    let assignedDate: Date?
    let status: BacklogStatus
    let createdAt: Date
    let updatedAt: Date
}

struct ProjectBucketJSON: Codable {
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
}

struct RecurringTaskTemplateJSON: Codable {
    let id: String
    let title: String
    let notes: String
    let recurrenceRule: RecurrenceRule
    let active: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct ExerciseRoutineItemJSON: Codable {
    let id: String
    let text: String
    let sets: Int?
    let reps: Int?
    let notes: String
    let sortOrder: Int
}

struct ExerciseRoutineJSON: Codable {
    let id: String
    let name: String
    let notes: String
    let recurrenceRule: RecurrenceRule
    let active: Bool
    let createdAt: Date
    let updatedAt: Date
    let items: [ExerciseRoutineItemJSON]
}

struct ScheduleTemplateJSON: Codable {
    let id: String
    let name: String
    let isEnabled: Bool
    let assignedWeekdays: [Int]
    let customDateStart: Date?
    let customDateEnd: Date?
    let blocks: [ScheduleBlock]
    let createdAt: Date
    let updatedAt: Date
}

struct DailyPageTaskJSON: Codable {
    let id: String
    let sourceType: DailyTaskSourceType
    let sourceId: String?
    let title: String
    let notes: String
    let completed: Bool
    let completedAt: Date?
    let sortOrder: Int
}

struct DailyPageJSON: Codable {
    let id: String
    let date: Date
    let createdAutomatically: Bool
    let dayComplete: Bool
    let isPastLocked: Bool
    let scheduleBlocks: [DailyPageScheduleBlock]
    let createdAt: Date
    let updatedAt: Date
    let tasks: [DailyPageTaskJSON]
}

struct NotificationReminderJSON: Codable {
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
}

// MARK: - HprgmBundle

struct HprgmBundle: Codable {
    let formatName: String      // "Human Program Export"
    let formatVersion: Int      // 1
    let exportedAt: Date
    let appVersion: String
    let backlogItems: [BacklogItemJSON]
    let projectBuckets: [ProjectBucketJSON]
    let recurringTaskTemplates: [RecurringTaskTemplateJSON]
    let exerciseRoutines: [ExerciseRoutineJSON]
    let scheduleTemplates: [ScheduleTemplateJSON]
    let dailyPages: [DailyPageJSON]
    let notifications: [NotificationReminderJSON]
}

// MARK: - HprgmExportService

@MainActor
struct HprgmExportService {

    /// Fetches all planner data from the context, encodes it to JSON, writes to a temp
    /// .hprgm file, and returns the file URL for sharing.
    func export(context: ModelContext) throws -> URL {
        let bundle = try buildBundle(context: context)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: Date())

        let filename = "HumanProgramBackup-\(dateString).hprgm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Private

    private func buildBundle(context: ModelContext) throws -> HprgmBundle {
        let backlogItems         = try fetchBacklogItems(context: context)
        let projectBuckets       = try fetchProjectBuckets(context: context)
        let recurringTemplates   = try fetchRecurringTaskTemplates(context: context)
        let exerciseRoutines     = try fetchExerciseRoutines(context: context)
        let scheduleTemplates    = try fetchScheduleTemplates(context: context)
        let dailyPages           = try fetchDailyPages(context: context)
        let notifications        = try fetchNotifications(context: context)

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

        return HprgmBundle(
            formatName: "Human Program Export",
            formatVersion: 1,
            exportedAt: Date(),
            appVersion: appVersion,
            backlogItems: backlogItems,
            projectBuckets: projectBuckets,
            recurringTaskTemplates: recurringTemplates,
            exerciseRoutines: exerciseRoutines,
            scheduleTemplates: scheduleTemplates,
            dailyPages: dailyPages,
            notifications: notifications
        )
    }

    private func fetchBacklogItems(context: ModelContext) throws -> [BacklogItemJSON] {
        let descriptor = FetchDescriptor<BacklogItem>(sortBy: [SortDescriptor(\.createdAt)])
        let items = try context.fetch(descriptor)
        return items.map { item in
            BacklogItemJSON(
                id: item.id,
                title: item.title,
                notes: item.notes,
                projectBucketId: item.project?.id,
                assignedDate: item.assignedDate,
                status: item.status,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
        }
    }

    private func fetchProjectBuckets(context: ModelContext) throws -> [ProjectBucketJSON] {
        let descriptor = FetchDescriptor<ProjectBucket>(sortBy: [SortDescriptor(\.createdAt)])
        let buckets = try context.fetch(descriptor)
        return buckets.map { bucket in
            ProjectBucketJSON(
                id: bucket.id,
                name: bucket.name,
                createdAt: bucket.createdAt,
                updatedAt: bucket.updatedAt
            )
        }
    }

    private func fetchRecurringTaskTemplates(context: ModelContext) throws -> [RecurringTaskTemplateJSON] {
        let descriptor = FetchDescriptor<RecurringTaskTemplate>(sortBy: [SortDescriptor(\.createdAt)])
        let templates = try context.fetch(descriptor)
        return templates.map { t in
            RecurringTaskTemplateJSON(
                id: t.id,
                title: t.title,
                notes: t.notes,
                recurrenceRule: t.recurrenceRule,
                active: t.active,
                createdAt: t.createdAt,
                updatedAt: t.updatedAt
            )
        }
    }

    private func fetchExerciseRoutines(context: ModelContext) throws -> [ExerciseRoutineJSON] {
        let descriptor = FetchDescriptor<ExerciseRoutine>(sortBy: [SortDescriptor(\.createdAt)])
        let routines = try context.fetch(descriptor)
        return routines.map { routine in
            let items = routine.items
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { item in
                    ExerciseRoutineItemJSON(
                        id: item.id,
                        text: item.text,
                        sets: item.sets,
                        reps: item.reps,
                        notes: item.notes,
                        sortOrder: item.sortOrder
                    )
                }
            return ExerciseRoutineJSON(
                id: routine.id,
                name: routine.name,
                notes: routine.notes,
                recurrenceRule: routine.recurrenceRule,
                active: routine.active,
                createdAt: routine.createdAt,
                updatedAt: routine.updatedAt,
                items: items
            )
        }
    }

    private func fetchScheduleTemplates(context: ModelContext) throws -> [ScheduleTemplateJSON] {
        let descriptor = FetchDescriptor<ScheduleTemplate>(sortBy: [SortDescriptor(\.createdAt)])
        let templates = try context.fetch(descriptor)
        return templates.map { t in
            ScheduleTemplateJSON(
                id: t.id,
                name: t.name,
                isEnabled: t.isEnabled,
                assignedWeekdays: t.assignedWeekdays,
                customDateStart: t.customDateStart,
                customDateEnd: t.customDateEnd,
                blocks: t.blocks,
                createdAt: t.createdAt,
                updatedAt: t.updatedAt
            )
        }
    }

    private func fetchDailyPages(context: ModelContext) throws -> [DailyPageJSON] {
        let descriptor = FetchDescriptor<DailyPage>(sortBy: [SortDescriptor(\.date)])
        let pages = try context.fetch(descriptor)
        return pages.map { page in
            let tasks = page.tasks
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { task in
                    DailyPageTaskJSON(
                        id: task.id,
                        sourceType: task.sourceType,
                        sourceId: task.sourceId,
                        title: task.title,
                        notes: task.notes,
                        completed: task.completed,
                        completedAt: task.completedAt,
                        sortOrder: task.sortOrder
                    )
                }
            return DailyPageJSON(
                id: page.id,
                date: page.date,
                createdAutomatically: page.createdAutomatically,
                dayComplete: page.dayComplete,
                isPastLocked: page.isPastLocked,
                scheduleBlocks: page.scheduleBlocks,
                createdAt: page.createdAt,
                updatedAt: page.updatedAt,
                tasks: tasks
            )
        }
    }

    private func fetchNotifications(context: ModelContext) throws -> [NotificationReminderJSON] {
        let descriptor = FetchDescriptor<NotificationReminder>(sortBy: [SortDescriptor(\.createdAt)])
        let reminders = try context.fetch(descriptor)
        return reminders.map { r in
            NotificationReminderJSON(
                id: r.id,
                title: r.title,
                message: r.message,
                isEnabled: r.isEnabled,
                recurrenceMode: r.recurrenceMode,
                weekdays: r.weekdays,
                fireHour: r.fireHour,
                fireMinute: r.fireMinute,
                intervalMinutes: r.intervalMinutes,
                windowStartMinute: r.windowStartMinute,
                windowEndMinute: r.windowEndMinute,
                soundMode: r.soundMode,
                imageFilename: r.imageFilename,
                attachedTaskId: r.attachedTaskId,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt
            )
        }
    }
}
