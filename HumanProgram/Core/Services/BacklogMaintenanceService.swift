import Foundation

// Pure service — no SwiftData.
public struct BacklogMaintenanceService: Sendable {

    public init() {}

    // If a BacklogItem has status==.backlog AND assignedDate < today (not same day),
    // clear its assignedDate. The item stays in backlog; it just loses its date.
    // Returns the set of item IDs that were cleared.
    @discardableResult
    public func clearOverdueAssignments(
        items: [BacklogItem],
        today: Date,
        calendar: Calendar = .current
    ) -> [String] {
        let todayStart = calendar.startOfDay(for: today)
        var clearedIds: [String] = []

        for item in items {
            guard item.status == .backlog else { continue }
            guard let assigned = item.assignedDate else { continue }
            let assignedStart = calendar.startOfDay(for: assigned)
            if assignedStart < todayStart {
                item.assignedDate = nil
                clearedIds.append(item.id)
            }
        }

        return clearedIds
    }

    // When a backlog-derived DailyPageTask is checked:
    //   - Find the source BacklogItem by sourceId
    //   - If it exists AND its assignedDate matches the page date AND the page is today or future:
    //     mark it .done
    // Returns (itemId, newStatus) if the backlog item was updated, otherwise nil.
    public func syncCompletion(
        task: DailyPageTask,
        pageDate: Date,
        backlogItems: [BacklogItem],
        today: Date,
        calendar: Calendar = .current
    ) -> (itemId: String, newStatus: BacklogStatus)? {
        guard let item = matchedBacklogItem(task: task, pageDate: pageDate,
                                            backlogItems: backlogItems, today: today,
                                            calendar: calendar) else { return nil }
        item.status = .done
        return (item.id, .done)
    }

    // When a backlog-derived DailyPageTask is UNCHECKED:
    //   - Same conditions as syncCompletion
    //   - Restore item to .backlog
    public func syncUncompletion(
        task: DailyPageTask,
        pageDate: Date,
        backlogItems: [BacklogItem],
        today: Date,
        calendar: Calendar = .current
    ) -> (itemId: String, newStatus: BacklogStatus)? {
        guard let item = matchedBacklogItem(task: task, pageDate: pageDate,
                                            backlogItems: backlogItems, today: today,
                                            calendar: calendar) else { return nil }
        item.status = .backlog
        return (item.id, .backlog)
    }

    // The completion/uncompletion pair share one set of eligibility checks and differ
    // only in the final status they set: the task must be backlog-sourced, the page
    // must be today or future, and the source item's assignedDate must match the page
    // date. Returns the matched item, or nil if any check fails. [#19]
    private func matchedBacklogItem(
        task: DailyPageTask,
        pageDate: Date,
        backlogItems: [BacklogItem],
        today: Date,
        calendar: Calendar
    ) -> BacklogItem? {
        guard task.sourceType == .backlog,
              let sourceId = task.sourceId,
              let item = backlogItems.first(where: { $0.id == sourceId }) else { return nil }

        let pageDayStart = calendar.startOfDay(for: pageDate)
        let todayStart = calendar.startOfDay(for: today)
        guard pageDayStart >= todayStart else { return nil }

        guard let assigned = item.assignedDate,
              calendar.startOfDay(for: assigned) == pageDayStart else { return nil }

        return item
    }
}
