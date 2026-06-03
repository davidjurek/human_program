import SwiftUI
import DSKit

// Format area. Time Format is applied LIVE — `clockString(...)` reads
// `settings.timeFormat` at every displayed clock time. Date Format persists and is
// honored by `AppDateFormat.userPreferred(_:)`, but the main display sites (Today /
// Backlog / Stats) still use the fixed `monthDayYear`/`weekday…` formatters, so the
// Date Format picker has no app-wide effect yet — routing those sites through
// `userPreferred` is a separate, behavior-changing task. [#158]

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
    @AppStorage(DefaultsKey.dateFormat) private var format: String = "MMM d, yyyy"

    // (sample label using 01/23/2045, format string)
    private let options: [(String, String)] = [
        ("Jan 23, 2045", "MMM d, yyyy"),
        ("January 23, 2045", "MMMM d, yyyy"),
        ("01/23/2045", "MM/dd/yyyy"),
        ("23/01/2045", "dd/MM/yyyy"),
        ("2045-01-23", "yyyy-MM-dd")
    ]

    var body: some View {
        SettingsScreen(centered: true) {       // [#55] option screen → 20/20 margins
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
    @AppStorage(DefaultsKey.timeFormat) private var format: String = "12h"

    var body: some View {
        SettingsScreen(centered: true) {       // [#55] option screen → 20/20 margins
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
