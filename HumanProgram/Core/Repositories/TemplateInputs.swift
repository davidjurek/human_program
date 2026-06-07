import Foundation
import SwiftData

/// The plain-data template inputs `DailyPageRepository` needs to (re)generate pages:
/// recurring-task templates, backlog items, and schedule blocks — each fetched from the
/// store and mapped to its `Sendable` Input struct.
///
/// This is the ONE place those fetch-and-map helpers live. They used to be copy-pasted
/// into `AppStartup`, `PageRefreshService`, and `TodayViewModel`; a field added to any
/// Input struct had to be edited in three places or pages would silently diverge between
/// launch, a post-edit refresh, and the Today screen's own refresh.
@MainActor
struct TemplateInputs {
    let recurring: [RecurringTaskInput]
    let backlog: [BacklogTaskInput]
    let schedule: [ScheduleBlockInput]

    /// Fetch and map all three template-input arrays from the store in one call.
    static func fetchAll(context: ModelContext) throws -> TemplateInputs {
        TemplateInputs(
            recurring: try fetchRecurring(context: context),
            backlog: try fetchBacklog(context: context),
            schedule: try fetchSchedule(context: context)
        )
    }

    static func fetchRecurring(context: ModelContext) throws -> [RecurringTaskInput] {
        try context.fetch(FetchDescriptor<RecurringTaskTemplate>()).map {
            RecurringTaskInput(id: $0.id, title: $0.title, notes: $0.notes, rule: $0.recurrenceRule, active: $0.active)
        }
    }

    static func fetchBacklog(context: ModelContext) throws -> [BacklogTaskInput] {
        try context.fetch(FetchDescriptor<BacklogItem>()).map {
            BacklogTaskInput(id: $0.id, title: $0.title, notes: $0.notes, assignedDate: $0.assignedDate, status: $0.status)
        }
    }

    /// Each block from the same template carries that template's enabled/weekday/date metadata.
    static func fetchSchedule(context: ModelContext) throws -> [ScheduleBlockInput] {
        try context.fetch(FetchDescriptor<ScheduleTemplate>()).flatMap { template in
            template.blocks.map { block in
                ScheduleBlockInput(
                    id: block.id,
                    templateId: template.id,
                    title: block.title,
                    startMinuteOfDay: block.startMinuteOfDay,
                    endMinuteOfDay: block.endMinuteOfDay,
                    sortOrder: block.sortOrder,
                    colorHex: block.colorHex,
                    templateIsEnabled: template.isEnabled,
                    templateAssignedWeekdays: template.assignedWeekdays,
                    templateCustomDateStart: template.customDateStart,
                    templateCustomDateEnd: template.customDateEnd
                )
            }
        }
    }
}
