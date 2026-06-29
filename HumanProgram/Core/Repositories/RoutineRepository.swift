import Foundation
import SwiftData

@MainActor
public final class RoutineRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func create(title: String, emoji: String = "") throws -> Routine {
        let routine = Routine(title: title)
        routine.emoji = emoji
        context.insert(routine)
        try context.save()
        return routine
    }

    public func update(_ routine: Routine, title: String? = nil, emoji: String? = nil, body: String? = nil) throws {
        if let title { routine.title = title }
        if let emoji { routine.emoji = emoji }
        if let body { routine.body = body }
        routine.updatedAt = Date()
        try context.save()
    }

    public func delete(_ routine: Routine) throws {
        context.delete(routine)
        try context.save()
    }

    /// One-time migration from the old itemized model: fold each routine's
    /// RoutineItem rows into its markdown `body` (one "- step" per line, in sort
    /// order), then delete the items. Idempotent and self-limiting — a routine
    /// whose body is already set (or that has no items) is skipped, so after the
    /// first launch this is a no-op. [option B]
    public func migrateItemsToBodyIfNeeded() throws {
        let routines = try context.fetch(FetchDescriptor<Routine>())
        var changed = false
        for r in routines where r.body.isEmpty && !r.items.isEmpty {
            r.body = r.items.sorted { $0.sortOrder < $1.sortOrder }
                .map { "- \($0.text)" }.joined(separator: "\n")
            for item in r.items { context.delete(item) }
            r.items.removeAll()
            r.updatedAt = Date()
            changed = true
        }
        if changed { try context.save() }
    }
}
