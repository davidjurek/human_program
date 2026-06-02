import SwiftData

/// The single list of `@Model` types backing the app. Both the production container
/// and the in-memory test container build from this one array, so they can never use
/// different schemas (forget a model in one and tests would silently run against a
/// different setup than the real app). [#92]
public let appModelTypes: [any PersistentModel.Type] = [
    BacklogItem.self,
    ProjectBucket.self,
    RecurringTaskTemplate.self,
    ExerciseRoutine.self,
    ExerciseRoutineItem.self,
    ScheduleTemplate.self,
    DailyPage.self,
    DailyPageTask.self,
    CalendarEventLocalState.self,
    NotificationReminder.self,
    Routine.self,
    RoutineItem.self,
]

/// Call this once at app startup to create the production ModelContainer.
public func makeModelContainer() throws -> ModelContainer {
    let schema = Schema(appModelTypes)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try ModelContainer(for: schema, configurations: [config])
}

/// In-memory container for tests.
public func makeTestModelContainer() throws -> ModelContainer {
    let schema = Schema(appModelTypes)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
