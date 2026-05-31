import SwiftUI
import DSKit

struct SettingsView: View {
    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "General") {
                SettingsNavRow(label: "Customization", systemImage: "paintbrush") { CustomizationView() }
                SettingsNavRow(label: "Format", systemImage: "textformat.123") { FormatView() }
                SettingsNavRow(label: "Reminders", systemImage: "bell") { RemindersView() }
                SettingsNavRow(label: "Security", systemImage: "lock") { SecuritySettingsView() }
            }

            SettingsGroup(title: "Planning") {
                SettingsNavRow(label: "Recurring Tasks", systemImage: "repeat") { RecurringTasksView() }
                SettingsNavRow(label: "Schedule", systemImage: "clock") { ScheduleListView() }
                SettingsNavRow(label: "Exercise", systemImage: "figure.run") { ExerciseSettingsView() }
                SettingsNavRow(label: "Calendar", systemImage: "calendar") { CalendarSourceSettingsView() }
            }

            SettingsGroup(title: "Data") {
                SettingsNavRow(label: "Import", systemImage: "square.and.arrow.down") { ImportView() }
                SettingsNavRow(label: "Export", systemImage: "square.and.arrow.up") { ExportView() }
            }

            SettingsGroup(title: "Info") {
                SettingsNavRow(label: "About Human Program", systemImage: "info.circle") { AboutView() }
            }

            SettingsGroup(title: "Danger Zone") {
                SettingsNavRow(label: "Factory Reset", systemImage: "trash", destructive: true) {
                    FactoryResetGate()
                }
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
