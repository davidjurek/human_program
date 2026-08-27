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
        state.dayKey = DayKey.make(normalized)
        context.insert(state)
        try context.save()
        return state
    }

    // MARK: - Mutations

    /// Get-or-create the row, apply `change`, stamp `updatedAt`, and save — the
    /// shared body of every override setter, in ONE place. [#93]
    private func mutate(eventId: String, date: Date, _ change: (CalendarEventLocalState) -> Void) throws {
        let state = try getOrCreate(eventId: eventId, date: date)
        change(state)
        state.updatedAt = Date()
        try context.save()
    }

    /// Toggle completion. Does NOT modify the underlying EKEvent.
    public func toggleCompletion(eventId: String, date: Date) throws {
        try mutate(eventId: eventId, date: date) { $0.completed.toggle() }
    }

    /// Show or hide an event from the Today page.
    public func setHidden(_ hidden: Bool, eventId: String, date: Date) throws {
        try mutate(eventId: eventId, date: date) { $0.hidden = hidden }
    }

    /// Override the display title for one event+day. Pass nil to remove the override.
    public func setTitleOverride(_ title: String?, eventId: String, date: Date) throws {
        try mutate(eventId: eventId, date: date) { $0.titleOverride = title }
    }

    /// Override the display notes for one event+day. Pass nil to remove the override.
    public func setNotesOverride(_ notes: String?, eventId: String, date: Date) throws {
        try mutate(eventId: eventId, date: date) { $0.notesOverride = notes }
    }

    // MARK: - Queries

    /// The stored local state for an event+day, or nil if none exists yet. Read-only —
    /// used to capture an undo snapshot before an override/hide mutation.
    public func existingState(eventId: String, date: Date) throws -> CalendarEventLocalState? {
        try fetchState(eventId: eventId, date: date)
    }

    /// All local state rows for the given date. Keyed by the timezone-independent
    /// day key — matching the stored `date` instant loses every override the moment
    /// the device changes timezone. [tz-daykey]
    public func fetchStates(for date: Date) throws -> [CalendarEventLocalState] {
        let key: Int? = DayKey.make(date)
        let descriptor = FetchDescriptor<CalendarEventLocalState>(
            predicate: #Predicate { $0.dayKey == key }
        )
        let hits = try context.fetch(descriptor)
        if !hits.isEmpty { return hits }
        return try adoptLegacyStates(key: DayKey.make(date))
    }

    /// Rows written before `dayKey` existed: match them by the day their stored instant
    /// was filed under (so another timezone's rows are still found) and adopt the key.
    /// `DayKeyRepairService` does this store-wide at launch; this is the safety net.
    private func adoptLegacyStates(key: Int) throws -> [CalendarEventLocalState] {
        let anchor = DayKey.startOfDay(key)
        let lower = anchor.addingTimeInterval(-27 * 3600)
        let upper = anchor.addingTimeInterval(27 * 3600)
        let nearby = try context.fetch(FetchDescriptor<CalendarEventLocalState>(
            predicate: #Predicate { $0.date >= lower && $0.date < upper }
        ))
        let matches = nearby.filter { $0.dayKey == nil && DayKey.fromStoredInstant($0.date) == key }
        guard !matches.isEmpty else { return [] }
        for state in matches { state.dayKey = key }
        try context.save()
        return matches
    }

    /// Event ids the user has hidden/removed from Today on the given date — so the
    /// Today screen can exclude them and they won't be re-added on the next sync.
    public func hiddenEventIds(for date: Date) throws -> Set<String> {
        Set(try fetchStates(for: date).filter { $0.hidden }.map { $0.eventId })
    }

    /// Every hidden row across all dates — the reconciliation page reads this to find
    /// calendar events the user removed from Today (the today/future ones are the
    /// recoverable discrepancies).
    public func fetchAllHidden() throws -> [CalendarEventLocalState] {
        let descriptor = FetchDescriptor<CalendarEventLocalState>(
            predicate: #Predicate { $0.hidden == true }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Private

    private func fetchState(eventId: String, date: Date) throws -> CalendarEventLocalState? {
        let key: Int? = DayKey.make(date)
        let descriptor = FetchDescriptor<CalendarEventLocalState>(
            predicate: #Predicate { $0.eventId == eventId && $0.dayKey == key },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        var matches = try context.fetch(descriptor)
        if matches.isEmpty {
            matches = try adoptLegacyStates(key: DayKey.make(date))
                .filter { $0.eventId == eventId }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
        guard let canonical = matches.first else { return nil }
        // The model has no store-level unique constraint on (date, eventId): #Unique is
        // unavailable at the iOS 17.6 deployment target and adding a unique attribute
        // would risk an existing store. getOrCreate is the only creation path, so dupes
        // shouldn't arise — but if any ever do, collapse them here into the most-recently
        // updated row so per-event overrides are never ambiguous. [#2]
        if matches.count > 1 {
            for dup in matches.dropFirst() { context.delete(dup) }
            try context.save()
        }
        return canonical
    }
}
