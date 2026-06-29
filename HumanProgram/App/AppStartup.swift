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

        // Record the install date once (start-of-day). The Today screen floors backward
        // navigation at this date so you can't scroll into days before the app existed.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.installDate) == nil {
            defaults.set(today, forKey: DefaultsKey.installDate)
        }

        let backlogRepo = BacklogRepository(context: context)
        let exerciseRepo = ExerciseRepository(context: context)
        let pageRepo = DailyPageRepository(context: context)
        let streakCalc = StreakCalculator()

        // 1. Day-rollover reconciliation of overdue backlog assignments. Read which
        //    backlog tasks were completed on a past page FIRST (before severPastTasks
        //    clears the source links): items completed on their assigned day are deleted
        //    from the backlog; the rest just lose their past date and stay.
        let completedBacklogIds = pageRepo.completedBacklogTaskIds(before: today)
        try backlogRepo.reconcileOverdueAssignments(today: today, completedBacklogIds: completedBacklogIds)

        // 1b. Sever past page-tasks from the backlog/calendar (day-rollover snapshot).
        try pageRepo.severPastTasks(today: today)

        // 2. Ensure every weekday has an exercise routine (creates missing ones)
        try exerciseRepo.ensureSevenWeekdayRoutines()

        // 2b. Fold any old itemized routines into their markdown body (one-time).
        try RoutineRepository(context: context).migrateItemsToBodyIfNeeded()

        // 3. Fetch template inputs
        let inputs = try TemplateInputs.fetchAll(context: context)

        // 4. Ensure today's page exists (created for its side effect)
        _ = try pageRepo.getOrCreate(
            date: today,
            today: today,
            recurringTemplates: inputs.recurring,
            backlogItems: inputs.backlog,
            scheduleTemplates: inputs.schedule
        )
        appState.viewingDate = today

        // 5. Refresh today and future pages
        try pageRepo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: inputs.recurring,
            backlogItems: inputs.backlog,
            scheduleTemplates: inputs.schedule
        )

        // 6. Recalculate streaks
        let allPages = try pageRepo.fetchAll()
        let snapshots = allPages.map {
            DailyCompletionSnapshot(date: $0.date, dayComplete: $0.dayComplete)
        }
        appState.streakStats = streakCalc.calculate(snapshots: snapshots, today: today)

        // 7. Publish today's summary for the home-screen widgets.
        WidgetSync.refresh(context: context)
    }
}
