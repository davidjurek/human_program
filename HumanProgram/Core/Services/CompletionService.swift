import Foundation

// Pure service — no SwiftData.
public struct CompletionService: Sendable {

    public init() {}

    // A day is complete when:
    //   - The tasks list is non-empty
    //   - Every task is completed
    // Returns false if tasks is empty.
    // Exercise items are not stored as DailyPageTask entries and are not passed here.
    // Calendar tasks ARE included. Hidden calendar tasks are excluded by caller.
    public func isComplete(tasks: [DailyPageTask]) -> Bool {
        guard !tasks.isEmpty else { return false }
        return tasks.allSatisfy { $0.completed }
    }

    // Recalculate and set dayComplete on the page.
    // Returns the new value.
    @discardableResult
    public func recalculate(page: DailyPage) -> Bool {
        let complete = isComplete(tasks: page.tasks)
        page.dayComplete = complete
        return complete
    }
}
