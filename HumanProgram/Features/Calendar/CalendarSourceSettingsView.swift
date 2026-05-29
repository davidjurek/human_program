import SwiftUI
import EventKit

/// Settings screen for choosing which device calendars feed Today.
/// Selected calendar IDs are persisted in UserDefaults under "selectedCalendarIds".
struct CalendarSourceSettingsView: View {

    @State private var calendarService = CalendarAdapterService()
    @State private var allCalendars: [EKCalendar] = []
    @State private var selectedIds: Set<String> = []
    @State private var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let selectedIdsKey = "selectedCalendarIds"

    var body: some View {
        Group {
            switch authStatus {
            case .notDetermined:
                permissionRequestView
            case .denied, .restricted:
                permissionDeniedView
            default:
                if allCalendars.isEmpty {
                    emptyCalendarsView
                } else {
                    calendarListView
                }
            }
        }
        .navigationTitle("Calendar Sources")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.background)
        .task { await loadCalendars() }
    }

    // MARK: - States

    private var permissionRequestView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            Text("Calendar Access Needed")
                .font(AppTypography.bodyMediumText())
                .foregroundStyle(AppColors.textPrimary)
            Text("Grant access so Human Program can show your calendar events in Today.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Grant Calendar Access") {
                Task { await requestAccess() }
            }
            .font(AppTypography.buttonLabel())
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.accent, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            Text("Calendar Access Denied")
                .font(AppTypography.bodyMediumText())
                .foregroundStyle(AppColors.textPrimary)
            Text("To show calendar events in Today, open Settings and allow calendar access for Human Program.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(AppTypography.buttonLabel())
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.accent, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var emptyCalendarsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            Text("No calendars found on device.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var calendarListView: some View {
        VStack(spacing: 0) {
            // Toolbar buttons
            HStack {
                Button("Select All") { selectedIds = Set(allCalendars.map { $0.calendarIdentifier }) }
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accent)
                Spacer()
                Button("Deselect All") { selectedIds = [] }
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groupedCalendars, id: \.source) { group in
                        sourceSection(group)
                    }
                }
            }
        }
    }

    // MARK: - Source section

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

    @ViewBuilder
    private func sourceSection(_ group: CalendarGroup) -> some View {
        // Section header
        HStack {
            Text(group.source.uppercased())
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)

        VStack(spacing: 0) {
            ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                CalendarRowView(
                    calendar: cal,
                    isSelected: selectedIds.contains(cal.calendarIdentifier)
                ) {
                    toggleCalendar(cal)
                }
                if cal.calendarIdentifier != group.calendars.last?.calendarIdentifier {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
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
}

// MARK: - Calendar row

private struct CalendarRowView: View {
    let calendar: EKCalendar
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Colored circle matching calendar color
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 14, height: 14)

                Text(calendar.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                // Checkbox
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.checkboxBorder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
