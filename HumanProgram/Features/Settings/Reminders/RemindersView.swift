import SwiftUI
import SwiftData
import UserNotifications

// MARK: - RemindersView

struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NotificationReminder.createdAt, order: .forward)
    private var reminders: [NotificationReminder]

    @State private var isEditMode = false
    @State private var showAddSheet = false
    @State private var selectedReminder: NotificationReminder?
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private let scheduler = RollingReminderScheduler()

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if authStatus == .denied {
                    permissionDeniedBanner
                }

                if reminders.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(reminders) { reminder in
                                ReminderRow(
                                    reminder: reminder,
                                    isEditMode: isEditMode,
                                    onTap: {
                                        if !isEditMode {
                                            selectedReminder = reminder
                                        }
                                    },
                                    onDelete: {
                                        deleteReminder(reminder)
                                    },
                                    onToggle: {
                                        toggleReminder(reminder)
                                    }
                                )
                                Divider()
                                    .padding(.leading, 52)
                                    .foregroundStyle(AppColors.separator)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.accent)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if !reminders.isEmpty {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditMode.toggle()
                        }
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ReminderEditorView(reminder: nil)
        }
        .sheet(item: $selectedReminder) { reminder in
            ReminderEditorView(reminder: reminder)
        }
        .task {
            await checkAuthStatus()
        }
    }

    // MARK: - Permission denied banner

    private var permissionDeniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(AppColors.accentOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are turned off")
                    .font(AppTypography.bodySmallMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Reminders won't fire until you grant permission.")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Button("Settings") {
                openAppSettings()
            }
            .font(AppTypography.buttonLabel())
            .foregroundStyle(AppColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.warningTint)
        .overlay(alignment: .bottom) {
            Divider().foregroundStyle(AppColors.separator)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(AppColors.textTertiary)
            Text("No reminders yet.")
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
            Text("Tap + to add one.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleReminder(_ reminder: NotificationReminder) {
        do {
            let repo = NotificationReminderRepository(context: context)
            try repo.toggleEnabled(reminder)
            rescheduleAll()
        } catch {
            print("[RemindersView] toggleEnabled error: \(error)")
        }
    }

    private func deleteReminder(_ reminder: NotificationReminder) {
        let reminderId = reminder.id
        do {
            let repo = NotificationReminderRepository(context: context)
            try repo.delete(reminder)
            scheduler.cancel(reminderId: reminderId)
        } catch {
            print("[RemindersView] delete error: \(error)")
        }
    }

    private func rescheduleAll() {
        let all = (try? NotificationReminderRepository(context: context).fetchAll()) ?? []
        Task {
            await scheduler.reschedule(reminders: all)
        }
    }

    private func checkAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - ReminderRow

private struct ReminderRow: View {
    let reminder: NotificationReminder
    let isEditMode: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.destructive)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Image(systemName: reminder.isEnabled ? "bell.fill" : "bell")
                .font(.system(size: 18))
                .foregroundStyle(reminder.isEnabled ? AppColors.accent : AppColors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(recurrenceSummary(for: reminder))
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            if !isEditMode {
                Toggle("", isOn: Binding(
                    get: { reminder.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: AppColors.accentGreen))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.2), value: isEditMode)
    }
}

// MARK: - Recurrence summary

func recurrenceSummary(for reminder: NotificationReminder) -> String {
    let timeString = formatTime(hour: reminder.fireHour, minute: reminder.fireMinute)
    switch reminder.recurrenceMode {
    case .daily:
        return "Daily at \(timeString)"
    case .weekdays:
        return "Weekdays at \(timeString)"
    case .selectedWeekdays:
        if reminder.weekdays.isEmpty {
            return "No days selected"
        }
        let dayNames = reminder.weekdays.sorted().map { notifWeekdayAbbrev($0) }.joined(separator: ", ")
        return "\(dayNames) at \(timeString)"
    case .everyNMinutes:
        let windowStart = formatMinuteOfDay(reminder.windowStartMinute)
        let windowEnd = formatMinuteOfDay(reminder.windowEndMinute)
        return "Every \(reminder.intervalMinutes) min, \(windowStart) – \(windowEnd)"
    case .hourlyWindow:
        let windowStart = formatMinuteOfDay(reminder.windowStartMinute)
        let windowEnd = formatMinuteOfDay(reminder.windowEndMinute)
        let dayNames: String
        if reminder.weekdays.isEmpty {
            dayNames = "Weekdays"
        } else {
            dayNames = reminder.weekdays.sorted().map { notifWeekdayAbbrev($0) }.joined(separator: ", ")
        }
        return "Hourly \(windowStart)–\(windowEnd) on \(dayNames)"
    }
}

// Format hour/minute to "8:00 AM" style
func formatTime(hour: Int, minute: Int) -> String {
    var components = DateComponents()
    components.hour = hour
    components.minute = minute
    guard let date = Calendar.current.date(from: components) else {
        return "\(hour):\(String(format: "%02d", minute))"
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

// Format minutes-from-midnight to "8:00 AM" style
func formatMinuteOfDay(_ minuteOfDay: Int) -> String {
    let hour = minuteOfDay / 60
    let minute = minuteOfDay % 60
    return formatTime(hour: hour, minute: minute)
}

// Weekday abbreviation (1=Sun … 7=Sat)
func notifWeekdayAbbrev(_ weekday: Int) -> String {
    let abbrevs = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let index = weekday - 1
    guard index >= 0, index < abbrevs.count else { return "?" }
    return abbrevs[index]
}
