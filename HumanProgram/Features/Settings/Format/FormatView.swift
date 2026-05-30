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

    // (sample label using 01/23/2045, format string)
    private let options: [(String, String)] = [
        ("Jan 23, 2045", "MMM d, yyyy"),
        ("January 23, 2045", "MMMM d, yyyy"),
        ("01/23/2045", "MM/dd/yyyy"),
        ("23/01/2045", "dd/MM/yyyy"),
        ("2045-01-23", "yyyy-MM-dd")
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
                SettingsSelectRow(label: "12-hour (12:34 PM)", isSelected: format == "12h") {
                    format = "12h"
                }
                SettingsSelectRow(label: "24-hour (12:34)", isSelected: format == "24h") {
                    format = "24h"
                }
            }
        }
    }
}
