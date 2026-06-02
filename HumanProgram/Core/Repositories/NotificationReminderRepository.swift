import Foundation
import SwiftData

// MARK: - NotificationReminderRepository

@MainActor
public final class NotificationReminderRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Fetch

    public func fetchAll() throws -> [NotificationReminder] {
        let descriptor = FetchDescriptor<NotificationReminder>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Create

    /// Inserts a new, blank reminder WITHOUT saving. The caller sets its fields and then
    /// calls `update(_:)` (a single save), so new and edit share one write path.
    public func makeNew() -> NotificationReminder {
        let reminder = NotificationReminder(title: "", message: "")
        context.insert(reminder)
        return reminder
    }

    // MARK: - Update

    /// Persists all current field values on the reminder object.
    /// Callers should mutate the reminder's properties directly, then call this.
    public func update(_ reminder: NotificationReminder) throws {
        reminder.updatedAt = Date()
        try context.save()
    }

    // MARK: - Delete

    public func delete(_ reminder: NotificationReminder) throws {
        context.delete(reminder)
        try context.save()
    }

    // MARK: - Toggle enabled

    public func toggleEnabled(_ reminder: NotificationReminder) throws {
        reminder.isEnabled.toggle()
        reminder.updatedAt = Date()
        try context.save()
    }
}
