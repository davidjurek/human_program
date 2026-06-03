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

// MARK: - Shared repository helpers

extension ModelContext {
    /// Fetch every model of type `T`, sorted by the given descriptors. The one place
    /// the build-a-descriptor-and-fetch pattern lives — every repo's `fetchAll`
    /// delegates here so a change to it is made once. [#70]
    func fetchSorted<T: PersistentModel>(
        _ type: T.Type = T.self,
        by sortBy: [SortDescriptor<T>]
    ) throws -> [T] {
        try fetch(FetchDescriptor<T>(sortBy: sortBy))
    }
}

/// The append-at-end ordering value: one past the current maximum `sortOrder`, or 0
/// for an empty list. Centralized so the off-by-one fallback can't drift. [#71]
func nextSortOrder<T>(in items: [T], _ sortOrder: (T) -> Int) -> Int {
    (items.map(sortOrder).max() ?? -1) + 1
}

extension Calendar {
    /// Midnight of `date` in this calendar. One named entry point for the
    /// date-to-start-of-day normalization repeated across the repositories. [#74]
    func dayStart(_ date: Date) -> Date { startOfDay(for: date) }
}

/// Stamp each element's `sortOrder` with its index in `ordered`, writing only when the
/// value actually changes (skip-if-unchanged avoids spurious saves). The one reorder
/// idiom shared by every list repository. [#72]
func applyReorder<T>(_ ordered: [T], set: (T, Int) -> Void, get: (T) -> Int) {
    for (index, item) in ordered.enumerated() where get(item) != index {
        set(item, index)
    }
}
