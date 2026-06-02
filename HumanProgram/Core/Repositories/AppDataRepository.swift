import Foundation
import SwiftData

/// Owns the whole-store data operations that don't belong to a single feature
/// repository — currently the Factory Reset wipe. Keeps `ModelContext` access out
/// of the views (architecture rule #1).
@MainActor
public final class AppDataRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Deletes EVERY persisted model. Used by Factory Reset. Saves once at the end.
    public func deleteEverything() throws {
        try deleteAll(BacklogItem.self)
        try deleteAll(ProjectBucket.self)
        try deleteAll(RecurringTaskTemplate.self)
        try deleteAll(ExerciseRoutineItem.self)
        try deleteAll(ExerciseRoutine.self)
        try deleteAll(ScheduleTemplate.self)
        try deleteAll(DailyPageTask.self)
        try deleteAll(DailyPage.self)
        try deleteAll(NotificationReminder.self)
        try deleteAll(RoutineItem.self)
        try deleteAll(Routine.self)
        try deleteAll(CalendarEventLocalState.self)
        try context.save()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for item in try context.fetch(FetchDescriptor<T>()) {
            context.delete(item)
        }
    }
}
