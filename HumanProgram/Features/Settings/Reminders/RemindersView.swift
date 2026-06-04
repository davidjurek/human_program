import SwiftUI
import SwiftData
import DSKit

struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NotificationReminder.createdAt, order: .forward)
    private var reminders: [NotificationReminder]

    private let scheduler = RollingReminderScheduler()

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            AddNavButton { ReminderEditorView(reminder: nil) }
        }) {
            if reminders.isEmpty {
                DSText("No reminders yet")
                    .dsTextStyle(.title3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                ForEach(reminders) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        onToggle: { toggle(reminder) },
                        onDelete: { delete(reminder) }
                    )
                }
            }
        }
        .task {
            _ = await scheduler.requestPermission()
        }
    }

    private func toggle(_ reminder: NotificationReminder) {
        do {
            let before = ReminderSnapshotModel(reminder)
            try NotificationReminderRepository(context: context).toggleEnabled(reminder)
            Undo.edited((reminder.isEnabled ? "Enable reminder " : "Disable reminder ") + undoTitle(reminder.title),
                        before: before, after: ReminderSnapshotModel(reminder), post: .rescheduleReminders)
            rescheduleAll()
        } catch { print("[Reminders] toggle error: \(error)") }
    }

    private func delete(_ reminder: NotificationReminder) {
        let id = reminder.id
        do {
            let before = ReminderSnapshotModel(reminder)
            try NotificationReminderRepository(context: context).delete(reminder)
            scheduler.cancel(reminderId: id)
            Undo.deleted("Delete reminder " + undoTitle(before.title), before, post: .rescheduleReminders)
        } catch { print("[Reminders] delete error: \(error)") }
    }

    private func rescheduleAll() {
        let all = (try? NotificationReminderRepository(context: context).fetchAll()) ?? []
        Task { await scheduler.reschedule(reminders: all) }
    }
}

private struct ReminderRow: View {
    let reminder: NotificationReminder
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ReminderEditorView(reminder: reminder)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    DSText(reminder.title).dsTextStyle(.title3)
                        .longTitle()
                    DSText(recurrenceSummary(for: reminder)).dsTextStyle(.subheadline)
                    WeekdayStrip(days: Set(reminder.weekdays))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Rectangle())

            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(appToggleTint)
                .a11yTapBorder(Capsule())
        }
        .frame(minHeight: 52)
    }
}

// MARK: - Recurrence summary helpers

func recurrenceSummary(for reminder: NotificationReminder) -> String {
    // Clock times honor the app's 12h/24h setting (shared helper).
    let fireTime = clockString(minutesOfDay: reminder.fireHour * 60 + reminder.fireMinute)
    switch reminder.recurrenceMode {
    case .everyNMinutes:
        let every = reminder.intervalMinutes % 60 == 0 && reminder.intervalMinutes >= 60
            ? "\(reminder.intervalMinutes / 60) hr"
            : "\(reminder.intervalMinutes) min"
        return "Every \(every), \(clockString(minutesOfDay: reminder.windowStartMinute))-\(clockString(minutesOfDay: reminder.windowEndMinute))"
    case .hourlyWindow:
        return "Hourly \(clockString(minutesOfDay: reminder.windowStartMinute))-\(clockString(minutesOfDay: reminder.windowEndMinute))"
    case .daily, .weekdays, .selectedWeekdays:
        return "Once a day \(fireTime)"
    }
}
