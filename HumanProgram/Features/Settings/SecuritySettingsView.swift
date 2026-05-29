import SwiftUI
import SwiftData
import LocalAuthentication

// ── SecuritySettingsView ───────────────────────────────────────────────────────
// Shown when the user navigates to Settings → Security.
struct SecuritySettingsView: View {

    @State private var lockVM = AppLockViewModel()
    @State private var showPINSetup = false
    @State private var showChangePIN = false
    @State private var showResetConfirmation = false
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            List {

                // ── Section 1: App Lock toggle ─────────────────────────────────
                Section {
                    Toggle(isOn: Binding(
                        get: { lockVM.repo.isLockEnabled },
                        set: { newValue in
                            handleLockToggle(newValue)
                        }
                    )) {
                        Label("App Lock", systemImage: "lock")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.accent)
                } header: {
                    Text("App Lock")
                } footer: {
                    Text("When enabled, Human Program requires your PIN (and optionally Face ID) when you open it.")
                        .foregroundStyle(AppColors.textSecondary)
                }

                // ── Section 2: Lock options (only when lock is enabled) ────────
                if lockVM.repo.isLockEnabled {

                    Section("Options") {

                        // Change PIN
                        Button {
                            showChangePIN = true
                        } label: {
                            Label("Change PIN", systemImage: "key")
                                .foregroundStyle(AppColors.textPrimary)
                        }

                        // Biometric toggle — only if hardware is present
                        if biometryAvailable {
                            Toggle(isOn: Binding(
                                get: { lockVM.repo.isBiometricEnabled },
                                set: { lockVM.repo.isBiometricEnabled = $0 }
                            )) {
                                Label(biometryLabel, systemImage: biometryIcon)
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            .tint(AppColors.accent)
                        }

                        // Lock timing picker
                        Picker(selection: Binding(
                            get: { lockVM.repo.lockTimeoutSeconds },
                            set: { lockVM.repo.lockTimeoutSeconds = $0 }
                        )) {
                            Text("Immediately").tag(0)
                            Text("After 30 seconds").tag(30)
                            Text("After 1 minute").tag(60)
                            Text("After 5 minutes").tag(300)
                            Text("After 15 minutes").tag(900)
                        } label: {
                            Label("Lock Timing", systemImage: "timer")
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }

                    // Lock Now
                    Section {
                        Button(role: .destructive) {
                            lockVM.lockNow()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Lock Now", systemImage: "lock.fill")
                                    .foregroundStyle(AppColors.accentRed)
                                Spacer()
                            }
                        }
                    }
                }

                // ── Section 3: Danger Zone ─────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Reset App", systemImage: "trash")
                                .foregroundStyle(AppColors.accentRed)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Reset App permanently deletes all your data. This cannot be undone.")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPINSetup) {
            PINSetupView(vm: lockVM)
        }
        .sheet(isPresented: $showChangePIN) {
            ChangePINView(vm: lockVM)
        }
        .sheet(isPresented: $showResetConfirmation) {
            ResetConfirmationView(context: context)
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private func handleLockToggle(_ newValue: Bool) {
        if newValue {
            if lockVM.repo.hasPIN() {
                lockVM.repo.isLockEnabled = true
            } else {
                // Must set a PIN before enabling.
                showPINSetup = true
            }
        } else {
            lockVM.repo.isLockEnabled = false
            lockVM.repo.isBiometricEnabled = false
        }
    }

    private var biometryAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    private var biometryLabel: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return "Face ID"
        }
        return ctx.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    private var biometryIcon: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return "faceid"
        }
        return ctx.biometryType == .faceID ? "faceid" : "touchid"
    }
}

// ── ChangePINView ──────────────────────────────────────────────────────────────
// Sheet for changing the PIN. Uses standard SecureField inputs (not the numpad)
// so the user can type quickly.
private struct ChangePINView: View {

    @State var vm: AppLockViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var oldPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String? = nil
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                Form {
                    Section("Current PIN") {
                        SecureField("Current PIN", text: $oldPIN)
                            .keyboardType(.numberPad)
                    }

                    Section("New PIN") {
                        SecureField("New PIN (4–20 digits)", text: $newPIN)
                            .keyboardType(.numberPad)
                        SecureField("Confirm new PIN", text: $confirmPIN)
                            .keyboardType(.numberPad)
                    }

                    if let msg = errorMessage {
                        Section {
                            Text(msg)
                                .foregroundStyle(AppColors.accentRed)
                                .font(AppTypography.bodySmallText())
                        }
                    }

                    if showSuccess {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColors.accentGreen)
                                Text("PIN changed successfully")
                                    .foregroundStyle(AppColors.accentGreen)
                                    .font(AppTypography.bodySmallText())
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(AppColors.accent)
                        .disabled(oldPIN.isEmpty || newPIN.isEmpty || confirmPIN.isEmpty)
                }
            }
        }
    }

    private func save() {
        errorMessage = nil

        guard newPIN == confirmPIN else {
            errorMessage = "New PINs do not match."
            return
        }
        guard newPIN.count >= vm.minPINLength else {
            errorMessage = "New PIN must be at least \(vm.minPINLength) digits."
            return
        }

        if let err = vm.changePIN(old: oldPIN, new: newPIN) {
            errorMessage = err
        } else {
            showSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
        }
    }
}

// ── ResetConfirmationView ──────────────────────────────────────────────────────
// Wipes all SwiftData records and UserDefaults. Requires the user to type RESET.
struct ResetConfirmationView: View {

    let context: ModelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""
    @State private var isResetting = false

    private let requiredConfirmation = "RESET"

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(AppColors.accentRed)
                        .padding(.top, 24)

                    Text("Reset App")
                        .font(AppTypography.pageTitle())
                        .foregroundStyle(AppColors.textPrimary)

                    Text("This will permanently delete all tasks, pages, routines, schedule blocks, exercise data, and settings. There is no undo.\n\nType RESET to confirm.")
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    TextField("Type RESET to confirm", text: $confirmText)
                        .font(AppTypography.bodyText())
                        .foregroundStyle(AppColors.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding()
                        .background(AppColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(AppColors.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 24)

                    Button(role: .destructive) {
                        performReset()
                    } label: {
                        HStack {
                            if isResetting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isResetting ? "Resetting…" : "Reset Everything")
                                .font(AppTypography.buttonLabel())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            confirmText == requiredConfirmation
                                ? AppColors.accentRed
                                : AppColors.accentRed.opacity(0.3)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    }
                    .disabled(confirmText != requiredConfirmation || isResetting)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
    }

    private func performReset() {
        isResetting = true

        do {
            try context.delete(model: DailyPage.self)
            try context.delete(model: DailyPageTask.self)
            try context.delete(model: RecurringTaskTemplate.self)
            try context.delete(model: ScheduleTemplate.self)
            try context.delete(model: ExerciseRoutine.self)
            try context.delete(model: ExerciseRoutineItem.self)
            try context.delete(model: BacklogItem.self)
            try context.delete(model: ProjectBucket.self)
            try context.delete(model: CalendarEventLocalState.self)
            try context.delete(model: NotificationReminder.self)
            try context.delete(model: Routine.self)
            try context.delete(model: RoutineItem.self)
            try context.delete(model: GameAccessState.self)
            try context.delete(model: GameSaveMetadata.self)
            try context.save()
        } catch {
            // Partial failures are acceptable — continue with UserDefaults wipe.
        }

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        try? AppLockRepository().removePIN()

        isResetting = false
        dismiss()
    }
}
