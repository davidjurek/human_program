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

        let inputs = try TemplateInputs.fetchAll(context: context)

        try pageRepo.refreshTodayAndFuture(
            today: today,
            recurringTemplates: inputs.recurring,
            backlogItems: inputs.backlog,
            scheduleTemplates: inputs.schedule
        )
    }
}
