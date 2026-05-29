import Foundation
import SwiftData

/// Manages CalendarEventLocalState records in SwiftData.
/// This layer NEVER touches EKEvent — it only tracks per-day overrides and completion.
@MainActor
public final class CalendarLocalStateRepository {

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Get or Create

    /// Return existing local state for the event+date pair, or create a fresh one.
    public func getOrCreate(eventId: String, date: Date) throws -> CalendarEventLocalState {
        let normalized = Calendar.current.startOfDay(for: date)
        if let existing = try fetchState(eventId: eventId, date: normalized) {
            return existing
        }
        let state = CalendarEventLocalState(date: normalized, eventId: eventId)
        context.insert(state)
        try context.save()
        return state
    }

    // MARK: - Mutations

    /// Toggle completion. Does NOT modify the underlying EKEvent.
    public func toggleCompletion(eventId: String, date: Date) throws {
        let state = try getOrCreate(eventId: eventId, date: date)
        state.completed.toggle()
        state.updatedAt = Date()
        try context.save()
    }

    /// Show or hide an event from the Today page.
    public func setHidden(_ hidden: Bool, eventId: String, date: Date) throws {
        let state = try getOrCreate(eventId: eventId, date: date)
        state.hidden = hidden
        state.updatedAt = Date()
        try context.save()
    }

    /// Override the display title for one event+day. Pass nil to remove the override.
    public func setTitleOverride(_ title: String?, eventId: String, date: Date) throws {
        let state = try getOrCreate(eventId: eventId, date: date)
        state.titleOverride = title
        state.updatedAt = Date()
        try context.save()
    }

    /// Override the display notes for one event+day. Pass nil to remove the override.
    public func setNotesOverride(_ notes: String?, eventId: String, date: Date) throws {
        let state = try getOrCreate(eventId: eventId, date: date)
        state.notesOverride = notes
        state.updatedAt = Date()
        try context.save()
    }

    // MARK: - Queries

    /// All local state rows for the given date.
    public func fetchStates(for date: Date) throws -> [CalendarEventLocalState] {
        let normalized = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<CalendarEventLocalState>(
            predicate: #Predicate { $0.date == normalized }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Private

    private func fetchState(eventId: String, date: Date) throws -> CalendarEventLocalState? {
        let normalized = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<CalendarEventLocalState>(
            predicate: #Predicate { $0.eventId == eventId && $0.date == normalized }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
