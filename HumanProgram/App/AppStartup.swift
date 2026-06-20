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

        // ── One-time maintenance (owner-requested, 2026-06-20): purge stray pages a
        // restored backup planted — junk old days (a 1996 page) AND bogus far-future
        // days (a 2030 + a year-4000 block). Keep only May 31, 2026 → today; delete
        // everything outside that. Errors are LOGGED (not swallowed) and before/after
        // counts printed so the result is verifiable. Fresh flag so it runs once now.
        // TEMPORARY — remove after it has run on-device. Install date left untouched.
        let trimFlag = "hp.maint.trim2"
        if !defaults.bool(forKey: trimFlag) {
            if let keepFrom = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)) {
                do {
                    let before = try pageRepo.fetchAll().count
                    let removed = try pageRepo.deletePages(keepFrom: keepFrom, keepThrough: today)
                    let after = try pageRepo.fetchAll().count
                    print("[AppStartup] trim2: \(before) → \(after) pages (removed \(removed); kept 2026-05-31…today)")
                } catch {
                    print("[AppStartup] trim2 FAILED: \(error)")
                }
            }
            defaults.set(true, forKey: trimFlag)
        }

        // 1. Clear overdue backlog assignments
        try backlogRepo.clearOverdueAssignments(today: today)

        // 1b. Sever past page-tasks from the backlog/calendar (day-rollover snapshot).
        try pageRepo.severPastTasks(today: today)

        // 2. Ensure every weekday has an exercise routine (creates missing ones)
        try exerciseRepo.ensureSevenWeekdayRoutines()

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
