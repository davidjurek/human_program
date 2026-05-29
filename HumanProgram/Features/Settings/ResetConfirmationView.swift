import SwiftUI
import SwiftData
import UserNotifications

// ── ResetConfirmationView ──────────────────────────────────────────────────────
// Two-step factory reset sheet. Present from SecuritySettingsView.
struct ResetConfirmationView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var step: ResetStep = .warning
    @State private var confirmationInput: String = ""
    @State private var isResetting: Bool = false

    private enum ResetStep {
        case warning, confirm
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            switch step {
            case .warning:
                warningScreen
            case .confirm:
                confirmScreen
            }
        }
    }

    // MARK: - Warning screen (step 1)

    private var warningScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            warningIcon

            Spacer().frame(height: 28)

            Text("Reset App")
                .font(AppTypography.title)
                .foregroundStyle(AppColors.textPrimary)

            Spacer().frame(height: 16)

            Text(warningBody)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    step = .confirm
                } label: {
                    Text("Continue")
                        .font(AppTypography.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accentRed, in: Capsule())
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Confirm screen (step 2)

    private var confirmScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            warningIcon

            Spacer().frame(height: 28)

            Text("Type RESET to confirm")
                .font(AppTypography.bodyBold)
                .foregroundStyle(AppColors.textPrimary)

            Spacer().frame(height: 16)

            TextField("", text: $confirmationInput, prompt: Text("RESET").foregroundStyle(AppColors.textTertiary))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(AppColors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    performReset()
                } label: {
                    Group {
                        if isResetting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Reset Everything")
                                .font(AppTypography.bodyBold)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        isConfirmationValid
                            ? AppColors.accentRed
                            : AppColors.accentRed.opacity(0.35),
                        in: Capsule()
                    )
                }
                .disabled(!isConfirmationValid || isResetting)

                Button {
                    confirmationInput = ""
                    step = .warning
                } label: {
                    Text("Cancel")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.vertical, 12)
                }
                .disabled(isResetting)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Shared subviews

    private var warningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 56))
            .foregroundStyle(AppColors.accentRed)
    }

    // MARK: - Helpers

    private var isConfirmationValid: Bool {
        confirmationInput.uppercased() == "RESET"
    }

    private let warningBody: String =
        "This will permanently delete all your tasks, backlog items, schedules, " +
        "routines, daily pages, history, and reminders. " +
        "This cannot be undone."

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
            // If save fails, still dismiss — the deletes may be partial but we
            // don't want to leave the user stuck on this screen.
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

// MARK: - Preview

#Preview {
    ResetConfirmationView()
        .modelContainer(for: [
            BacklogItem.self,
            ProjectBucket.self,
            RecurringTaskTemplate.self,
            ExerciseRoutine.self,
            ExerciseRoutineItem.self,
            ScheduleTemplate.self,
            DailyPage.self,
            DailyPageTask.self,
            NotificationReminder.self,
            GameAccessState.self,
            GameSaveMetadata.self,
            Routine.self,
            RoutineItem.self,
            CalendarEventLocalState.self
        ], inMemory: true)
}
