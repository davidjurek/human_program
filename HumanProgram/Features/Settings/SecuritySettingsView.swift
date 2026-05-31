import SwiftUI
import SwiftData
import DSKit
import LocalAuthentication

// ── SecuritySettingsView ───────────────────────────────────────────────────────
// Settings → Security. Built on the shared Settings convention (SettingsScreen +
// SettingsGroup + open card-less rows). App Lock on/off, then PIN / biometric /
// lock-timing options when enabled, and the Reset App entry (a pushed screen).
struct SecuritySettingsView: View {

    @State private var lockVM = AppLockViewModel()
    @State private var showPINSetup = false
    @Environment(\.modelContext) private var context

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "App Lock") {
                SettingsToggleRow(label: "App Lock", systemImage: "lock", isOn: lockBinding)
            }

            DSText("When enabled, Human Program asks for your PIN (and optionally \(biometryLabel)) each time you open it.")
                .dsTextStyle(.subheadline)

            if lockVM.repo.isLockEnabled {
                SettingsGroup(title: "Options") {
                    SettingsNavRow(label: "Change PIN", systemImage: "key") {
                        ChangePINView(vm: lockVM)
                    }

                    if biometryAvailable {
                        SettingsToggleRow(label: biometryLabel, systemImage: biometryIcon,
                                          isOn: biometricBinding)
                    }

                    SettingsNavRow(label: "Lock Timing", systemImage: "timer",
                                   value: timingLabel(lockVM.repo.lockTimeoutSeconds)) {
                        LockTimingView(vm: lockVM)
                    }
                }

                SettingsGroup {
                    SettingsButtonRow(label: "Lock Now", systemImage: "lock.fill") {
                        lockVM.lockNow()
                    }
                }
            }

            SettingsGroup(title: "Danger Zone") {
                SettingsNavRow(label: "Reset App", systemImage: "trash", destructive: true) {
                    FactoryResetView()
                }
            }

            DSText("Reset App permanently deletes all your data. This cannot be undone.")
                .dsTextStyle(.subheadline)
        }
        .fullScreenCover(isPresented: $showPINSetup) {
            PINSetupView(vm: lockVM)
        }
    }

    // ── Bindings ─────────────────────────────────────────────────────────────────

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { lockVM.repo.isLockEnabled },
            set: { handleLockToggle($0) }
        )
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { lockVM.repo.isBiometricEnabled },
            set: { lockVM.repo.isBiometricEnabled = $0 }
        )
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

    private func timingLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0:   return "Immediately"
        case 30:  return "30 seconds"
        case 60:  return "1 minute"
        case 300: return "5 minutes"
        case 900: return "15 minutes"
        default:  return "\(seconds)s"
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

// ── Lock timing picker ──────────────────────────────────────────────────────────
// Pushed select-list (same pattern as Date/Time Format), one row per timeout.
private struct LockTimingView: View {
    let vm: AppLockViewModel
    @State private var selection: Int

    init(vm: AppLockViewModel) {
        self.vm = vm
        _selection = State(initialValue: vm.repo.lockTimeoutSeconds)
    }

    private let options: [(label: String, seconds: Int)] = [
        ("Immediately", 0),
        ("After 30 seconds", 30),
        ("After 1 minute", 60),
        ("After 5 minutes", 300),
        ("After 15 minutes", 900)
    ]

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Lock Timing") {
                ForEach(options, id: \.seconds) { option in
                    SettingsSelectRow(label: option.label, isSelected: selection == option.seconds) {
                        selection = option.seconds
                        vm.repo.lockTimeoutSeconds = option.seconds
                    }
                }
            }
        }
    }
}

// ── ChangePINView ──────────────────────────────────────────────────────────────
// Pushed screen for changing the PIN. Native SecureFields (so the user can type
// quickly); Save lives in the top-right, disabled until all three are filled.
private struct ChangePINView: View {

    let vm: AppLockViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var oldPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String? = nil
    @State private var showSuccess = false

    private var canSave: Bool {
        !oldPIN.isEmpty && !newPIN.isEmpty && !confirmPIN.isEmpty
    }

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            Button { save() } label: {
                Text("Save").font(appFont(18))
                    .foregroundStyle(canSave ? .primary : .secondary)
                    .frame(height: 44).padding(.horizontal, 6)
            }
            .disabled(!canSave)
        }) {
            SettingsGroup(title: "Current PIN") {
                PINField(placeholder: "Current PIN", text: $oldPIN)
            }

            SettingsGroup(title: "New PIN") {
                PINField(placeholder: "New PIN (4–20 digits)", text: $newPIN)
                PINField(placeholder: "Confirm new PIN", text: $confirmPIN)
            }

            if let msg = errorMessage {
                DSText(msg).dsTextStyle(.subheadline, Color.red)
            }

            if showSuccess {
                HStack(spacing: 8) {
                    DSImageView(systemName: "checkmark.circle.fill", size: .font(.body),
                                tint: .color(.green))
                    DSText("PIN changed successfully").dsTextStyle(.subheadline, Color.green)
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

/// A themed secure entry field used by Change PIN — numeric keypad, app font,
/// sunken rounded background so it reads as a tappable field on the gradient.
private struct PINField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .font(appFont(18))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
