import SwiftUI
import DSKit

// Format area. STRUCTURE + SCREENS first — selections persist (@AppStorage)
// but are not yet applied to date/time rendering across the app. Wiring them
// into the live formatters is a follow-up.

struct FormatView: View {
    var body: some View {
        SettingsScreen {
            SettingsGroup {
                SettingsNavRow(label: "Date Format", systemImage: "calendar") { DateFormatView() }
                SettingsNavRow(label: "Time Format", systemImage: "clock") { TimeFormatView() }
            }
        }
    }
}

// MARK: - Date format

struct DateFormatView: View {
    @AppStorage("settings.dateFormat") private var format: String = "MMM d, yyyy"

    // (sample label, format string)
    private let options: [(String, String)] = [
        ("Sep 7, 2026", "MMM d, yyyy"),
        ("September 7, 2026", "MMMM d, yyyy"),
        ("09/07/2026", "MM/dd/yyyy"),
        ("07/09/2026", "dd/MM/yyyy"),
        ("2026-09-07", "yyyy-MM-dd")
    ]

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Date Format") {
                ForEach(options, id: \.1) { option in
                    SettingsSelectRow(label: option.0, isSelected: format == option.1) {
                        format = option.1
                    }
                }
            }
        }
    }
}

// MARK: - Time format

struct TimeFormatView: View {
    @AppStorage("settings.timeFormat") private var format: String = "12h"

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Time Format") {
                SettingsSelectRow(label: "12-hour (3:30 PM)", isSelected: format == "12h") {
                    format = "12h"
                }
                SettingsSelectRow(label: "24-hour (15:30)", isSelected: format == "24h") {
                    format = "24h"
                }
            }
        }
    }
}
