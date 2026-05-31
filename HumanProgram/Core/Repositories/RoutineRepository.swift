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

    public func update(_ routine: Routine, title: String? = nil, emoji: String? = nil) throws {
        if let title { routine.title = title }
        if let emoji { routine.emoji = emoji }
        routine.updatedAt = Date()
        try context.save()
    }

    public func delete(_ routine: Routine) throws {
        context.delete(routine)
        try context.save()
    }

    @discardableResult
    public func addItem(to routine: Routine, text: String) throws -> RoutineItem {
        let next = (routine.items.map { $0.sortOrder }.max() ?? -1) + 1
        let item = RoutineItem(text: text, sortOrder: next)
        item.routine = routine
        routine.items.append(item)
        routine.updatedAt = Date()
        context.insert(item)
        try context.save()
        return item
    }

    public func deleteItem(_ item: RoutineItem, from routine: Routine) throws {
        routine.items.removeAll { $0.id == item.id }
        context.delete(item)
        routine.updatedAt = Date()
        try context.save()
    }

    public func reorderItems(_ items: [RoutineItem], in routine: Routine) throws {
        for (i, item) in items.enumerated() { item.sortOrder = i }
        routine.updatedAt = Date()
        try context.save()
    }

    public func updateItem(_ item: RoutineItem, text: String) throws {
        item.text = text
        try context.save()
    }
}
