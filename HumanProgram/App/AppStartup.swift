import Foundation
import SwiftData

@MainActor
public struct AppStartup {
    public static func run(context: ModelContext, appState: AppState) async throws {
        // 0. Reschedule all notification reminders (rolling 20-occurrence window)
        let notifRepo = NotificationReminderRepository(context: context)
        let allReminders = (try? notifRepo.fetchAll()) ?? []
        let scheduler = RollingReminderScheduler()
        await scheduler.reschedule(reminders: allReminders)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let backlogRepo = BacklogRepository(context: context)
        let exerciseRepo = ExerciseRepository(context: context)
        let pageRepo = DailyPageRepository(context: context)
        let streakCalc = StreakCalculator()

        // 1. Clear overdue backlog assignments
        try backlogRepo.clearOverdueAssignments(today: today)

        // 1b. Sever past page-tasks from the backlog/calendar (day-rollover snapshot).
        try pageRepo.severPastTasks(today: today)

        // 2. Ensure every weekday has an exercise routine (creates missing ones)
        try exerciseRepo.ensureSevenWeekdayRoutines()

        // 3. Fetch template inputs
        let recurringInputs = try fetchRecurringInputs(context: context, calendar: calendar)
        let backlogInputs   = try fetchBacklogInputs(context: context)
        let scheduleInputs  = try fetchScheduleInputs(context: context)

        // 4. Ensure today's page exists
        let todayPage = try pageRepo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: recurringInputs,
            backlogItems: backlogInputs,
            scheduleTemplates: scheduleInputs
        )
        appState.viewingDate = today

        // 5. Refresh today and future pages
        try pageRepo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: recurringInputs,
            backlogItems: backlogInputs,
            scheduleTemplates: scheduleInputs
        )

        // 6. Recalculate streaks
        let allPages = try pageRepo.fetchAll()
        let snapshots = allPages.map {
            DailyCompletionSnapshot(date: $0.date, dayComplete: $0.dayComplete)
        }
        appState.streakStats = streakCalc.calculate(snapshots: snapshots, today: today)

        _ = todayPage // used above
    }

    private static func fetchRecurringInputs(context: ModelContext, calendar: Calendar) throws -> [RecurringTaskInput] {
        let descriptor = FetchDescriptor<RecurringTaskTemplate>()
        let templates = try context.fetch(descriptor)
        return templates.map {
            RecurringTaskInput(id: $0.id, title: $0.title, notes: $0.notes, rule: $0.recurrenceRule, active: $0.active)
        }
    }

    private static func fetchBacklogInputs(context: ModelContext) throws -> [BacklogTaskInput] {
        let descriptor = FetchDescriptor<BacklogItem>()
        let items = try context.fetch(descriptor)
        return items.map {
            BacklogTaskInput(id: $0.id, title: $0.title, assignedDate: $0.assignedDate, status: $0.status)
        }
    }

    private static func fetchScheduleInputs(context: ModelContext) throws -> [ScheduleBlockInput] {
        let descriptor = FetchDescriptor<ScheduleTemplate>()
        let templates = try context.fetch(descriptor)
        return templates.flatMap { template in
            template.blocks.map { block in
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
            }
        }
    }
}
