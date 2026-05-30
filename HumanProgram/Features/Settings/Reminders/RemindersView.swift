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
            NavigationLink {
                ReminderEditorView(reminder: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
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
            try NotificationReminderRepository(context: context).toggleEnabled(reminder)
            rescheduleAll()
        } catch { print("[Reminders] toggle error: \(error)") }
    }

    private func delete(_ reminder: NotificationReminder) {
        let id = reminder.id
        do {
            try NotificationReminderRepository(context: context).delete(reminder)
            scheduler.cancel(reminderId: id)
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
                        .lineLimit(3)
                    DSText(recurrenceSummary(for: reminder)).dsTextStyle(.subheadline)
                    WeekdayStrip(days: Set(reminder.weekdays))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { reminder.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(appToggleTint)
        }
        .frame(minHeight: 52)
    }
}

// MARK: - Recurrence summary helpers

func recurrenceSummary(for reminder: NotificationReminder) -> String {
    func hhmm(_ minutesOfDay: Int) -> String {
        String(format: "%02d:%02d", minutesOfDay / 60, minutesOfDay % 60)
    }
    let fireTime = String(format: "%02d:%02d", reminder.fireHour, reminder.fireMinute)
    switch reminder.recurrenceMode {
    case .everyNMinutes:
        let every = reminder.intervalMinutes % 60 == 0 && reminder.intervalMinutes >= 60
            ? "\(reminder.intervalMinutes / 60) hr"
            : "\(reminder.intervalMinutes) min"
        return "Every \(every), \(hhmm(reminder.windowStartMinute))-\(hhmm(reminder.windowEndMinute))"
    case .hourlyWindow:
        return "Hourly \(hhmm(reminder.windowStartMinute))-\(hhmm(reminder.windowEndMinute))"
    case .daily, .weekdays, .selectedWeekdays:
        return "Once a day \(fireTime)"
    }
}
