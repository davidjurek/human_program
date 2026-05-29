import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            List {
                Section("Planning") {
                    SettingsRow(label: "Recurring Tasks", icon: "repeat",      destination: AnyView(RecurringTasksView()))
                    SettingsRow(label: "Schedule",        icon: "clock",        destination: AnyView(ScheduleListView()))
                    SettingsRow(label: "Exercise",        icon: "figure.run",   destination: AnyView(ExerciseSettingsView()))
                }
                Section("Notifications & Calendar") {
                    SettingsRow(label: "Notifications", icon: "bell",           destination: AnyView(PlaceholderSettingsView(title: "Notifications")))
                    SettingsRow(label: "Calendar",      icon: "calendar",       destination: AnyView(PlaceholderSettingsView(title: "Calendar")))
                }
                Section("Data") {
                    SettingsRow(label: "Import / Export", icon: "square.and.arrow.up", destination: AnyView(PlaceholderSettingsView(title: "Import / Export")))
                    SettingsRow(label: "Security",        icon: "lock",          destination: AnyView(PlaceholderSettingsView(title: "Security")))
                }
                Section {
                    SettingsRow(label: "About", icon: "info.circle",            destination: AnyView(AboutView()))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsRow: View {
    let label: String
    let icon: String
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            Label(label, systemImage: icon)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

struct PlaceholderSettingsView: View {
    let title: String
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            Text("\(title) settings coming soon")
                .foregroundStyle(AppColors.textTertiary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
