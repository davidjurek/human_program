import Foundation
import SwiftData
import WidgetKit

/// Publishes TODAY's summary to the App Group so the widgets can render it, then nudges
/// WidgetKit to reload. The app owns the SwiftData store; the widget never opens it —
/// it reads this snapshot (see WidgetShared). Safe to call after any mutation: it always
/// recomputes from today's page, regardless of which day the user was editing.
@MainActor
enum WidgetSync {
    static func refresh(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        // By day key, not by the stored instant — see DayKey. [tz-daykey]
        let page = (try? DailyPageRepository(context: context).fetch(date: today)) ?? nil
        let tasks = (page?.tasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let completed = tasks.filter { $0.completed }.count
        // Same rule as the app: empty today counts as complete.
        let isComplete = CompletionService().isComplete(tasks: tasks, date: page?.date ?? today, today: today)
        let outstanding = tasks.filter { !$0.completed }.map { $0.title }

        WidgetShared.save(WidgetSnapshot(
            dayStart: today,
            completed: completed,
            total: tasks.count,
            isComplete: isComplete,
            outstandingTitles: outstanding
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
