import SwiftUI
import SwiftData
import DSKit
import UserNotifications
import UIKit

/// The centered warning body shared by the Factory Reset and Restore screens.
/// Both reserve the height of the LONGER (reset) copy via a hidden sizer, so the
/// confirm field and the destructive button land in the SAME spot on both screens;
/// the shorter Restore copy simply leaves a little blank space beneath it. Using a
/// hidden DSText as the sizer keeps the reserved height correct at any font scale.
struct DestructiveWarningText: View {
    /// The longer of the two warnings (Factory Reset) — also the height reference.
    static let resetWarning =
        "Factory reset will restore the app to its factory state and wipe all data. " +
        "Consider creating a backup if you have not done so. " +
        "This action cannot be undone."

    let text: String
    var body: some View {
        ZStack(alignment: .top) {
            DSText(Self.resetWarning).dsTextStyle(.body)
                .multilineTextAlignment(.center).hidden()
            DSText(text).dsTextStyle(.body)
                .multilineTextAlignment(.center)
        }
    }
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
    // The block is parked this far up the page (a fixed physical shift, no keyboard
    // avoidance) so the red button sits a comfortable gap above the keyboard.
    // Nothing moves when the keyboard appears.
    private let contentLift: CGFloat = 32

    private var isConfirmationValid: Bool {
        confirmationInput.uppercased() == "RESET"
    }

    var body: some View {
        // Keyboard avoidance is OFF (manualKeyboardAvoidance) so nothing shifts when
        // the keyboard appears. The block is simply parked high (see contentLift).
        SettingsScreen(centered: true, manualKeyboardAvoidance: true) {
            VStack(spacing: 14) {
                DSImageView(systemName: "exclamationmark.triangle.fill",
                            size: 56, tint: .color(.red))
                    .padding(.top, 8)

                DSText("Reset App").dsTextStyle(.title2)

                DestructiveWarningText(text: DestructiveWarningText.resetWarning)

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
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .offset(y: -contentLift)
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
        // A reset re-runs onboarding (Welcome → Terms → Tutorial) but is NOT a fresh
        // install, so the permissions step should not appear. Mark it asked so the
        // re-run skips it.
        UserDefaults.standard.set(true, forKey: "hp.permissionsAsked")
    }
}
