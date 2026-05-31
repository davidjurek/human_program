import SwiftUI
import EventKit
import DSKit

/// Settings → Calendar. Chooses which device calendars feed Today.
/// Built on the shared Settings convention (SettingsScreen + SettingsGroup +
/// open rows). Shows a permission-request state before access is granted, and a
/// grouped, selectable list of calendars afterward.
/// Selected calendar IDs persist in UserDefaults under "selectedCalendarIds".
struct CalendarSourceSettingsView: View {

    @State private var calendarService = CalendarAdapterService()
    @State private var allCalendars: [EKCalendar] = []
    @State private var selectedIds: Set<String> = []
    @State private var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let selectedIdsKey = "selectedCalendarIds"

    var body: some View {
        SettingsScreen(centered: true) {
            switch authStatus {
            case .notDetermined:
                CalendarMessageState(
                    icon: "calendar.badge.exclamationmark",
                    title: "Calendar Access Needed",
                    message: "Grant access so Human Program can show your calendar events in Today.",
                    actionTitle: "Grant Calendar Access",
                    action: { Task { await requestAccess() } }
                )
            case .denied, .restricted:
                CalendarMessageState(
                    icon: "calendar.badge.exclamationmark",
                    title: "Calendar Access Denied",
                    message: "To show calendar events in Today, open Settings and allow calendar access for Human Program.",
                    actionTitle: "Open Settings",
                    action: openSystemSettings
                )
            default:
                if allCalendars.isEmpty {
                    CalendarMessageState(
                        icon: "calendar",
                        title: "No Calendars Found",
                        message: "There are no calendars on this device to choose from.",
                        actionTitle: nil,
                        action: {}
                    )
                } else {
                    calendarList
                }
            }
        }
        .task { await loadCalendars() }
    }

    // MARK: - Calendar list

    @ViewBuilder
    private var calendarList: some View {
        HStack(spacing: 24) {
            Button("Select All") { selectedIds = Set(allCalendars.map { $0.calendarIdentifier }); saveSelection() }
                .buttonStyle(.plain)
            Button("Deselect All") { selectedIds = []; saveSelection() }
                .buttonStyle(.plain)
            Spacer()
        }
        .font(appFont(16))
        .foregroundStyle(.primary)

        ForEach(groupedCalendars, id: \.source) { group in
            SettingsGroup(title: group.source) {
                ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                    CalendarSelectRow(
                        title: cal.title,
                        color: Color(cgColor: cal.cgColor),
                        isSelected: selectedIds.contains(cal.calendarIdentifier)
                    ) {
                        toggleCalendar(cal)
                    }
                }
            }
        }
    }

    private struct CalendarGroup {
        let source: String
        let calendars: [EKCalendar]
    }

    private var groupedCalendars: [CalendarGroup] {
        var map: [String: [EKCalendar]] = [:]
        for cal in allCalendars {
            let key = cal.source?.title ?? "Other"
            map[key, default: []].append(cal)
        }
        return map.keys.sorted().map { key in
            CalendarGroup(source: key, calendars: map[key]!.sorted { $0.title < $1.title })
        }
    }

    // MARK: - Helpers

    private func toggleCalendar(_ cal: EKCalendar) {
        let id = cal.calendarIdentifier
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        saveSelection()
    }

    private func saveSelection() {
        UserDefaults.standard.set(Array(selectedIds), forKey: selectedIdsKey)
    }

    private func loadSelection() {
        let saved = UserDefaults.standard.stringArray(forKey: selectedIdsKey) ?? []
        selectedIds = Set(saved)
    }

    private func loadCalendars() async {
        authStatus = calendarService.authorizationStatus
        guard calendarService.isAuthorized else { return }
        allCalendars = calendarService.fetchAllCalendars()
        loadSelection()
    }

    private func requestAccess() async {
        let granted = await calendarService.requestAccess()
        authStatus = calendarService.authorizationStatus
        if granted {
            allCalendars = calendarService.fetchAllCalendars()
            loadSelection()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Calendar select row (colored dot + title + checkmark)

/// A multi-select calendar row, matching `SettingsSelectRow` but with a leading
/// dot in the calendar's color.
private struct CalendarSelectRow: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Circle().fill(color).frame(width: 14, height: 14)
                DSText(title).dsTextStyle(.title3)
                Spacer(minLength: 8)
                if isSelected {
                    DSImageView(systemName: "checkmark", size: .font(.body), tint: .color(.primary))
                }
            }
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Centered message state (permission / empty)

/// A centered icon + title + message with an optional capsule action button.
/// Reused for the calendar permission-request, denied, and empty states.
private struct CalendarMessageState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            DSImageView(systemName: icon, size: 48, tint: .color(.secondary))
            DSText(title).dsTextStyle(.title3)
            DSText(message)
                .dsTextStyle(.subheadline)
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(action: action) {
                    DSText(actionTitle).dsTextStyle(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
