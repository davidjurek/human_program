import SwiftUI
import SwiftData
import DSKit
import UserNotifications

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

    @State private var confirmationInput: String = ""
    @State private var isResetting: Bool = false

    private var isConfirmationValid: Bool {
        confirmationInput.uppercased() == "RESET"
    }

    private let warningBody: String =
        "This will permanently delete all your tasks, backlog items, schedules, " +
        "routines, daily pages, history, and reminders. " +
        "This cannot be undone."

    var body: some View {
        SettingsScreen(centered: true) {
            VStack(spacing: 16) {
                DSImageView(systemName: "exclamationmark.triangle.fill",
                            size: 56, tint: .color(.red))
                    .padding(.top, 24)

                DSText("Reset App").dsTextStyle(.title2)

                DSText(warningBody)
                    .dsTextStyle(.body)
                    .multilineTextAlignment(.center)

                DSText("Type RESET to confirm")
                    .dsTextStyle(.subheadline)
                    .padding(.top, 12)

                TextField("", text: $confirmationInput,
                          prompt: Text("RESET").foregroundStyle(.tertiary))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
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
                    Text("Reset Everything").font(appFont(18)).foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isConfirmationValid ? Color.red : Color.red.opacity(0.35),
                        in: Capsule())
        }
        .buttonStyle(.plain)
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

            dismiss()
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
            "selectedCalendarIds"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
