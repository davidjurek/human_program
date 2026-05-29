import SwiftData

/// Call this once at app startup to create the production ModelContainer.
public func makeModelContainer() throws -> ModelContainer {
    let schema = Schema([
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
        GameAccessState.self,
        GameSaveMetadata.self,
        Routine.self,
        RoutineItem.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try ModelContainer(for: schema, configurations: [config])
}

/// In-memory container for tests.
public func makeTestModelContainer() throws -> ModelContainer {
    let schema = Schema([
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
        GameAccessState.self,
        GameSaveMetadata.self,
        Routine.self,
        RoutineItem.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
