import SwiftUI
import EventKit
import UserNotifications

// Onboarding step shown ONCE on a fresh install, right after the Tutorial: asks for
// Calendar + Notification access. Each "Grant access" button fires the real iOS
// permission prompt and flips to "Done!" once granted. The bottom Enter button stays
// disabled until BOTH are granted; the top-right Skip enters the app regardless.
// Not shown after a factory reset — the reset marks hp.permissionsAsked so the
// re-run of onboarding skips straight past this screen (see ContentView).
struct PermissionsOnboardingView: View {
    /// Called when the user leaves this screen (Enter or Skip) — finishes onboarding.
    var onFinish: () -> Void = {}

    @State private var calendarDone = false
    @State private var notifDone = false

    private let lightBlue = Color(red: 0.42, green: 0.69, blue: 0.99)
    private let calendarService = CalendarAdapterService()

    private var bothGranted: Bool { calendarDone && notifDone }

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 0) {
                // Skip — top-right; enters the app no matter what was granted.
                HStack {
                    Spacer()
                    Button(action: onFinish) {
                        Text("Skip").font(appFont(18)).foregroundStyle(.primary)
                            .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .a11yTapBorder(Rectangle())
                }
                .padding(.trailing, 12)
                .padding(.top, 8)

                Spacer()

                Text("Please give access to notifications and calendar for the app.")
                    .font(appFont(20)).foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 44)

                VStack(spacing: 24) {
                    permissionRow(label: "Calendar access", done: calendarDone) {
                        Task { await requestCalendar() }
                    }
                    permissionRow(label: "Notification access", done: notifDone) {
                        Task { await requestNotifications() }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Enter — disabled (greyed) until both accesses are granted.
                Button(action: onFinish) {
                    Text("Enter").font(appFont(20)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(bothGranted ? lightBlue : lightBlue.opacity(0.35),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .a11yTapBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!bothGranted)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .task { await refreshStatuses() }
    }

    /// One row: label on the left, a fixed-width light-blue action button on the
    /// right. Both rows use the SAME button width so the buttons line up. Tapping a
    /// "Done!" button is a no-op (kept full-color rather than dimmed-disabled).
    private func permissionRow(label: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label).font(appFont(18)).foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: { if !done { action() } }) {
                Text(done ? "Done!" : "Grant access")
                    .font(appFont(16)).foregroundStyle(.white)
                    .frame(width: 140).padding(.vertical, 12)
                    .background(lightBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .a11yTapBorder(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Permission requests

    @MainActor private func requestCalendar() async {
        // Use the request's own result as the source of truth — re-reading
        // EKEventStore.authorizationStatus right after granting can still report the
        // old value, which left the button stuck on "Grant access".
        let granted = await calendarService.requestAccess()
        calendarDone = granted || calendarService.isAuthorized
    }

    @MainActor private func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        // If the prompt didn't grant (e.g. already-decided), fall back to the live status.
        notifDone = granted ? true : await notificationsAuthorized()
    }

    private func notificationsAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// On appear, reflect any access already granted (so its button shows "Done!").
    @MainActor private func refreshStatuses() async {
        calendarDone = calendarService.isAuthorized
        notifDone = await notificationsAuthorized()
    }
}
