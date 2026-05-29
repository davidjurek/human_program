import Foundation
import SwiftData

@MainActor
public final class RecurringTaskRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - fetchAll

    /// Fetch all recurring task templates, both active and inactive, sorted by title.
    public func fetchAll() throws -> [RecurringTaskTemplate] {
        let descriptor = FetchDescriptor<RecurringTaskTemplate>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - create

    /// Create and persist a new recurring task template.
    @discardableResult
    public func create(
        title: String,
        rule: RecurrenceRule,
        notes: String = "",
        active: Bool = true
    ) throws -> RecurringTaskTemplate {
        let template = RecurringTaskTemplate(title: title, rule: rule)
        template.notes = notes
        template.active = active
        context.insert(template)
        try context.save()
        return template
    }

    // MARK: - update

    /// Update mutable fields on an existing template.
    /// Only non-nil parameters are applied; pass nil to leave a field unchanged.
    public func update(
        _ template: RecurringTaskTemplate,
        title: String? = nil,
        notes: String? = nil,
        rule: RecurrenceRule? = nil,
        active: Bool? = nil
    ) throws {
        if let title = title { template.title = title }
        if let notes = notes { template.notes = notes }
        if let rule = rule { template.recurrenceRule = rule }
        if let active = active { template.active = active }
        template.updatedAt = Date()
        try context.save()
    }

    // MARK: - delete

    /// Delete a recurring task template from the store.
    public func delete(_ template: RecurringTaskTemplate) throws {
        context.delete(template)
        try context.save()
    }
}
