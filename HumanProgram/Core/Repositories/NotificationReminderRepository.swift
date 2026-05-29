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

    @discardableResult
    public func create(
        title: String,
        message: String,
        fireHour: Int,
        fireMinute: Int,
        recurrenceMode: NotificationRecurrenceMode,
        weekdays: [Int] = [],
        soundMode: NotificationSoundMode = .defaultSound
    ) throws -> NotificationReminder {
        let reminder = NotificationReminder(title: title, message: message)
        reminder.fireHour = fireHour
        reminder.fireMinute = fireMinute
        reminder.recurrenceMode = recurrenceMode
        reminder.weekdays = weekdays
        reminder.soundMode = soundMode
        context.insert(reminder)
        try context.save()
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
