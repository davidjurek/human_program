import Foundation
import SwiftData

/// Call this after any template change (recurring tasks, schedule, exercise)
/// to update today and all future DailyPages. Past pages are never touched.
@MainActor
public struct PageRefreshService {

    // MARK: - refresh

    /// Fetch all template inputs from the store, then forward them to DailyPageRepository
    /// to refresh today and future pages.
    public static func refresh(context: ModelContext) throws {
        let today = Calendar.current.startOfDay(for: Date())
        let pageRepo = DailyPageRepository(context: context)

        let recurringInputs  = try fetchRecurringInputs(context: context)
        let backlogInputs    = try fetchBacklogInputs(context: context)
        let scheduleInputs   = try fetchScheduleInputs(context: context)

        try pageRepo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: recurringInputs,
            backlogItems: backlogInputs,
            scheduleTemplates: scheduleInputs
        )
    }

    // MARK: - Private fetch helpers

    /// Convert every RecurringTaskTemplate in the store to a RecurringTaskInput.
    private static func fetchRecurringInputs(context: ModelContext) throws -> [RecurringTaskInput] {
        let descriptor = FetchDescriptor<RecurringTaskTemplate>()
        let templates = try context.fetch(descriptor)
        return templates.map { t in
            RecurringTaskInput(
                id: t.id,
                title: t.title,
                notes: t.notes,
                rule: t.recurrenceRule,
                active: t.active
            )
        }
    }

    /// Convert every BacklogItem in the store to a BacklogTaskInput.
    private static func fetchBacklogInputs(context: ModelContext) throws -> [BacklogTaskInput] {
        let descriptor = FetchDescriptor<BacklogItem>()
        let items = try context.fetch(descriptor)
        return items.map { item in
            BacklogTaskInput(
                id: item.id,
                title: item.title,
                assignedDate: item.assignedDate,
                status: item.status
            )
        }
    }

    /// Convert every ScheduleTemplate's blocks to a flat array of ScheduleBlockInput values.
    /// Each block from the same template shares the same template-level metadata.
    private static func fetchScheduleInputs(context: ModelContext) throws -> [ScheduleBlockInput] {
        let descriptor = FetchDescriptor<ScheduleTemplate>()
        let templates = try context.fetch(descriptor)
        var inputs: [ScheduleBlockInput] = []
        for template in templates {
            for block in template.blocks {
                inputs.append(
                    ScheduleBlockInput(
                        id: block.id,
                        title: block.title,
                        startMinuteOfDay: block.startMinuteOfDay,
                        endMinuteOfDay: block.endMinuteOfDay,
                        sortOrder: block.sortOrder,
                        templateIsEnabled: template.isEnabled,
                        templateAssignedWeekdays: template.assignedWeekdays,
                        templateCustomDateStart: template.customDateStart,
                        templateCustomDateEnd: template.customDateEnd
                    )
                )
            }
        }
        return inputs
    }
}
