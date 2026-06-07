import Foundation

// Pure service — no SwiftData.
public struct CompletionService: Sendable {

    public init() {}

    // A day is complete when:
    //   - It is NOT a future day. A future day is NEVER complete, even if every task is
    //     checked off — completion only "counts" once the day is actually the present
    //     day (or in the past). You can tick tasks ahead of time, but it isn't flagged
    //     done and doesn't feed streaks/stats until that day arrives.
    //   - For today or a past day: every task is completed. An EMPTY task list counts as
    //     complete ("nothing to do = done").
    // Exercise items are not stored as DailyPageTask entries and are not passed here.
    // Calendar tasks ARE included. Hidden calendar tasks are excluded by caller.
    public func isComplete(tasks: [DailyPageTask], date: Date, today: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        // Future days are never complete.
        if dayStart > todayStart { return false }
        // Today or past: empty list is complete; otherwise every task must be done.
        return tasks.allSatisfy { $0.completed }
    }

    // Recalculate and set dayComplete on the page.
    // Returns the new value. `today` defaults to the current day; pass it explicitly
    // (e.g. from getOrCreate / refresh) when a specific "today" is in play.
    @discardableResult
    public func recalculate(page: DailyPage, today: Date = Date()) -> Bool {
        let complete = isComplete(tasks: page.tasks, date: page.date, today: today)
        page.dayComplete = complete
        return complete
    }
}
