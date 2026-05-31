import Foundation
import SwiftData

@MainActor
public final class ExerciseRepository {
    private let context: ModelContext
    private let engine = RecurrenceEngine()

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - ensureSevenWeekdayRoutines

    /// Guarantee that exactly one routine exists per weekday (1=Sun through 7=Sat).
    /// Creates missing routines using the weekday name as the default name.
    /// Existing routines are left untouched.
    public func ensureSevenWeekdayRoutines() throws {
        let all = try fetchAll()

        // Collect which weekdays already have a routine (by first weekday in rule).
        let existingWeekdays = Set(all.compactMap { $0.recurrenceRule.weekdays.first })

        let weekdayNames: [Int: String] = [
            1: "Sunday",
            2: "Monday",
            3: "Tuesday",
            4: "Wednesday",
            5: "Thursday",
            6: "Friday",
            7: "Saturday"
        ]

        for weekday in 1...7 {
            guard !existingWeekdays.contains(weekday) else { continue }
            // Seed with a BLANK name — the weekday header comes from the rule, and
            // the routine name is an optional custom label the user fills in.
            _ = weekdayNames   // (kept for reference; names are no longer seeded)
            let rule = RecurrenceRule.on([weekday])
            let routine = ExerciseRoutine(name: "", rule: rule)
            context.insert(routine)
        }

        try context.save()
    }

    // MARK: - fetchAll

    /// Fetch all routines sorted by their primary weekday (lowest weekday number first).
    public func fetchAll() throws -> [ExerciseRoutine] {
        let descriptor = FetchDescriptor<ExerciseRoutine>()
        let all = try context.fetch(descriptor)
        return all.sorted { lhs, rhs in
            let lhsDay = lhs.recurrenceRule.weekdays.first ?? 0
            let rhsDay = rhs.recurrenceRule.weekdays.first ?? 0
            return lhsDay < rhsDay
        }
    }

    // MARK: - fetchRoutine(for:calendar:)

    /// Return the first active routine whose recurrence rule matches the given date.
    /// Returns nil if no routine matches.
    public func fetchRoutine(for date: Date, calendar: Calendar = .current) throws -> ExerciseRoutine? {
        let all = try fetchAll()
        return all.first { routine in
            routine.active && engine.matches(routine.recurrenceRule, on: date, calendar: calendar)
        }
    }

    // MARK: - update

    /// Update mutable fields on a routine. Pass nil to leave a field unchanged.
    public func update(
        _ routine: ExerciseRoutine,
        name: String? = nil,
        notes: String? = nil,
        active: Bool? = nil
    ) throws {
        if let name = name { routine.name = name }
        if let notes = notes { routine.notes = notes }
        if let active = active { routine.active = active }
        routine.updatedAt = Date()
        try context.save()
    }

    // MARK: - addItem

    /// Append a new exercise item to a routine.
    /// The item's sortOrder is set to one past the current maximum.
    @discardableResult
    public func addItem(
        to routine: ExerciseRoutine,
        text: String,
        sets: Int? = nil,
        reps: Int? = nil,
        notes: String = ""
    ) throws -> ExerciseRoutineItem {
        let nextSortOrder = (routine.items.map { $0.sortOrder }.max() ?? -1) + 1
        let item = ExerciseRoutineItem(text: text, sortOrder: nextSortOrder)
        item.sets = sets
        item.reps = reps
        item.notes = notes
        item.routine = routine
        routine.items.append(item)
        routine.updatedAt = Date()
        context.insert(item)
        try context.save()
        return item
    }

    // MARK: - deleteItem

    /// Remove an item from a routine and delete it from the store.
    public func deleteItem(_ item: ExerciseRoutineItem, from routine: ExerciseRoutine) throws {
        routine.items.removeAll { $0.id == item.id }
        context.delete(item)
        routine.updatedAt = Date()
        try context.save()
    }

    // MARK: - reorderItems

    /// Reorder the items in a routine.
    /// Accepts the new desired order; assigns sortOrder 0, 1, 2, … matching that order.
    public func reorderItems(_ items: [ExerciseRoutineItem], in routine: ExerciseRoutine) throws {
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        routine.updatedAt = Date()
        try context.save()
    }

    // MARK: - updateItem

    /// Update a single item's text, sets, reps, or notes. Pass nil to leave a field unchanged.
    public func updateItem(
        _ item: ExerciseRoutineItem,
        text: String? = nil,
        sets: Int? = nil,
        reps: Int? = nil,
        notes: String? = nil
    ) throws {
        if let text = text { item.text = text }
        if let sets = sets { item.sets = sets }
        if let reps = reps { item.reps = reps }
        if let notes = notes { item.notes = notes }
        try context.save()
    }

    // MARK: - setItemCounts

    /// Set an item's sets/reps EXPLICITLY, where `nil` clears the value (means
    /// "not specified"). Unlike `updateItem` — where `nil` means "leave unchanged"
    /// — this is how the editor turns a count off.
    public func setItemCounts(_ item: ExerciseRoutineItem, sets: Int?, reps: Int?) throws {
        item.sets = sets
        item.reps = reps
        item.routine?.updatedAt = Date()
        try context.save()
    }
}
