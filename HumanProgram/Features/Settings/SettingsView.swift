import SwiftUI
import DSKit

struct SettingsView: View {
    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Planning") {
                SettingsNavRow(label: "Recurring Tasks", systemImage: "repeat") { RecurringTasksView() }
                SettingsNavRow(label: "Schedule", systemImage: "clock") { ScheduleListView() }
                SettingsNavRow(label: "Exercise", systemImage: "figure.run") { ExerciseSettingsView() }
            }

            SettingsGroup(title: "Notifications & Calendar") {
                SettingsNavRow(label: "Reminders", systemImage: "bell") { RemindersView() }
                SettingsNavRow(label: "Calendar", systemImage: "calendar") { CalendarSourceSettingsView() }
            }

            SettingsGroup(title: "Data") {
                SettingsNavRow(label: "Import / Export", systemImage: "square.and.arrow.up") { ImportExportView() }
                SettingsNavRow(label: "Security", systemImage: "lock") { SecuritySettingsView() }
            }

            SettingsGroup(title: "Info") {
                SettingsNavRow(label: "About", systemImage: "info.circle") { AboutView() }
            }
        }
    }
}

struct PlaceholderSettingsView: View {
    let title: String
    var body: some View {
        SettingsScreen {
            DSText("\(title) settings coming soon")
                .dsTextStyle(.subheadline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        }
    }
}
