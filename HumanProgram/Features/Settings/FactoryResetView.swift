import SwiftUI
import SwiftData
import DSKit
import UserNotifications
import UIKit

/// Reports a view's bottom edge (global Y) so a screen can lift it above the keyboard.
struct ButtonMaxYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// ── FactoryResetView ───────────────────────────────────────────────────────────
// Pushed screen (reached from Settings → Danger Zone, and Settings → Security).
// Wipes all SwiftData records and the app's UserDefaults. The user must type
// RESET to enable the destructive action, so it can't fire by accident.
// ── FactoryResetGate ───────────────────────────────────────────────────────────
// Reached from Settings → Danger Zone. If a PIN is set, the user must enter it
// (on the shared numpad) before the reset screen appears; with no PIN, it goes
// straight to the reset screen.
struct FactoryResetGate: View {
    private let repo = AppLockRepository()
    @State private var hasPIN = false
    @State private var unlocked = false
    @State private var error: String?
    @State private var shake = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if hasPIN && !unlocked {
                PINEntryView(
                    title: "Enter PIN",
                    subtitle: nil,
                    showsBack: true,
                    onBack: { dismiss() },
                    errorMessage: error,
                    shakeToken: shake,
                    onSubmit: { pin in
                        if repo.verifyPIN(pin) {
                            unlocked = true
                        } else {
                            error = "Incorrect PIN."
                            shake += 1
                        }
                    }
                )
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
            } else {
                FactoryResetView()
            }
        }
        .onAppear { hasPIN = repo.hasPIN() }
    }
}

struct FactoryResetView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var confirmationInput: String = ""
    @State private var isResetting: Bool = false
    // Keyboard-avoidance: lift the whole block by exactly the amount the red
    // button would be covered when the keyboard appears.
    @State private var buttonMaxY: CGFloat = 0
    @State private var lift: CGFloat = 0

    private var isConfirmationValid: Bool {
        confirmationInput.uppercased() == "RESET"
    }

    private let warningBody: String =
        "This will permanently delete all your tasks, backlog items, schedules, " +
        "routines, daily pages, history, and reminders. " +
        "This cannot be undone."

    var body: some View {
        // Our own keyboard avoidance is off (so SwiftUI doesn't fight us); we lift
        // the block manually so the red button always clears the keyboard.
        SettingsScreen(centered: true, manualKeyboardAvoidance: true) {
            VStack(spacing: 14) {
                DSImageView(systemName: "exclamationmark.triangle.fill",
                            size: 56, tint: .color(.red))
                    .padding(.top, 8)

                DSText("Reset App").dsTextStyle(.title2)

                DSText(warningBody)
                    .dsTextStyle(.body)
                    .multilineTextAlignment(.center)

                DSText("Type reset to confirm")
                    .dsTextStyle(.subheadline)
                    .padding(.top, 12)

                TextField("", text: $confirmationInput,
                          prompt: Text("reset").foregroundStyle(.tertiary))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(appFont(18))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                resetButton
                    .padding(.top, 8)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ButtonMaxYKey.self, value: g.frame(in: .global).maxY)
                    })
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .offset(y: -lift)
            .onPreferenceChange(ButtonMaxYKey.self) { buttonMaxY = $0 }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                // buttonMaxY is measured from the already-lifted view, so add the
                // current lift back to recover the button's RESTING bottom. Without
                // this, a second keyboardWillShow (the iOS 26 predictive bar toggling
                // height) computes against the lifted position and the lift collapses.
                let restingMaxY = buttonMaxY + lift
                // Overlap between the button's bottom (+24pt breathing room) and the keyboard top.
                let needed = restingMaxY + 24 - frame.minY
                withAnimation(.easeOut(duration: 0.25)) { lift = max(0, needed) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { lift = 0 }
            }
        }
    }

    private var resetButton: some View {
        Button {
            performReset()
        } label: {
            Group {
                if isResetting {
                    ProgressView().tint(.white)
                } else {
                    Text("Factory Reset").font(appFont(18)).foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isConfirmationValid ? Color.red : Color.red.opacity(0.35),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(Capsule())
        .disabled(!isConfirmationValid || isResetting)
    }

    // MARK: - Reset logic

    private func performReset() {
        guard isConfirmationValid else { return }
        isResetting = true

        do {
            try deleteAllModels()
            try context.save()

            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            clearUserDefaults()

            try? AppLockRepository().removePIN()

            // Show the full-screen "reset to factory state" interstitial; clearing
            // hp.onboarded means the onboarding sequence (Welcome → Terms → Tutorial)
            // runs again after it.
            appState.pendingInterstitial = .reset
        } catch {
            // If save fails, still leave the screen — the deletes may be partial
            // but we don't want to strand the user here.
            dismiss()
        }
    }

    private func deleteAllModels() throws {
        try deleteAll(BacklogItem.self)
        try deleteAll(ProjectBucket.self)
        try deleteAll(RecurringTaskTemplate.self)
        try deleteAll(ExerciseRoutineItem.self)
        try deleteAll(ExerciseRoutine.self)
        try deleteAll(ScheduleTemplate.self)
        try deleteAll(DailyPageTask.self)
        try deleteAll(DailyPage.self)
        try deleteAll(NotificationReminder.self)
        try deleteAll(GameAccessState.self)
        try deleteAll(GameSaveMetadata.self)
        try deleteAll(RoutineItem.self)
        try deleteAll(Routine.self)
        try deleteAll(CalendarEventLocalState.self)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items {
            context.delete(item)
        }
    }

    private func clearUserDefaults() {
        let keys = [
            "hp.lock.enabled",
            "hp.lock.biometric",
            "hp.lock.timeout",
            "selectedCalendarIds",
            "hp.onboarded"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
