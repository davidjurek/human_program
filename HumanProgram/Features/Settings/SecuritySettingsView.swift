import SwiftUI
import DSKit
import LocalAuthentication

// ── SecuritySettingsView ───────────────────────────────────────────────────────
// Settings → Security. A clean 3-option DSKit menu: PIN, App Lock, Face ID.
// (No Reset App here — Factory Reset lives in the main Settings Danger Zone.)
// App Lock and Face ID require a PIN, so they're disabled until one is set.
struct SecuritySettingsView: View {
    @State private var lockVM = AppLockViewModel()
    @State private var hasPIN = false
    /// When a PIN is set, the Security screen itself is gated: the menu only
    /// appears after the PIN is entered.
    @State private var unlocked = false
    @State private var gateError: String?
    @State private var gateShake = 0
    @Environment(\.dismiss) private var dismiss

    init() {
        let vm = AppLockViewModel()
        _lockVM = State(initialValue: vm)
        _hasPIN = State(initialValue: vm.repo.hasPIN())
    }

    var body: some View {
        Group {
            if hasPIN && !unlocked {
                PINEntryView(
                    title: "Enter PIN",
                    subtitle: nil,
                    minLength: lockVM.minPINLength,
                    maxLength: lockVM.maxPINLength,
                    showsBack: true,
                    onBack: { dismiss() },
                    errorMessage: gateError,
                    shakeToken: gateShake,
                    onSubmit: verifyGate
                )
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
            } else {
                menu
            }
        }
        .onAppear { hasPIN = lockVM.repo.hasPIN() }
    }

    private func verifyGate(_ pin: String) {
        if lockVM.repo.verifyPIN(pin) {
            gateError = nil
            unlocked = true
        } else {
            gateError = "Incorrect PIN."
            gateShake += 1
        }
    }

    private var menu: some View {
        SettingsScreen {
            SettingsGroup {
                SettingsNavRow(label: "PIN", systemImage: "key") {
                    PINMenuView(vm: lockVM)
                }
                if hasPIN {
                    SettingsNavRow(label: "App Lock", systemImage: "lock",
                                   value: AppLockTimingView.currentLabel(lockVM)) {
                        AppLockTimingView(vm: lockVM)
                    }
                    SettingsNavRow(label: biometryLabel, systemImage: biometryIcon) {
                        FaceIDSetupView(vm: lockVM)
                    }
                } else {
                    // Disabled until a PIN exists.
                    SettingsRowContent(label: "App Lock", systemImage: "lock") { EmptyView() }
                        .opacity(0.35)
                    SettingsRowContent(label: biometryLabel, systemImage: biometryIcon) { EmptyView() }
                        .opacity(0.35)
                }
            }
        }
    }

    private var biometryLabel: String { BiometryInfo.label }
    private var biometryIcon: String { BiometryInfo.icon }
}

// ── PIN sub-menu ────────────────────────────────────────────────────────────────
private struct PINMenuView: View {
    let vm: AppLockViewModel
    @State private var hasPIN = false

    var body: some View {
        SettingsScreen {
            SettingsGroup {
                SettingsNavRow(label: hasPIN ? "Change your PIN" : "Create a PIN",
                               systemImage: "key") {
                    CreateOrChangePINView(vm: vm, isChange: hasPIN)
                }
                if hasPIN {
                    SettingsNavRow(label: "Delete your PIN", systemImage: "key.slash",
                                   destructive: true) {
                        DeletePINView(vm: vm)
                    }
                }
            }
        }
        .onAppear { hasPIN = vm.repo.hasPIN() }
    }
}

// ── Create / Change PIN (enter → confirm) ───────────────────────────────────────
private struct CreateOrChangePINView: View {
    let vm: AppLockViewModel
    let isChange: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step
    @State private var firstEntry = ""
    @State private var error: String?
    @State private var shake = 0

    init(vm: AppLockViewModel, isChange: Bool) {
        self.vm = vm
        self.isChange = isChange
        // Changing an existing PIN starts by verifying the current one.
        _step = State(initialValue: isChange ? .verifyOld : .enter)
    }

    private enum Step: Hashable { case verifyOld, enter, confirm }

    private var title: String {
        switch step {
        case .verifyOld: return "Enter current PIN"
        case .enter:     return isChange ? "Enter new PIN" : "Create a PIN"
        case .confirm:   return "Confirm PIN"
        }
    }

    var body: some View {
        PINEntryView(
            title: title,
            subtitle: step == .enter ? "Digits only · 4–20 digits" : nil,
            minLength: vm.minPINLength,
            maxLength: vm.maxPINLength,
            showsBack: true,
            onBack: { dismiss() },
            errorMessage: error,
            shakeToken: shake,
            onSubmit: handle
        )
        .id(step)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func handle(_ pin: String) {
        switch step {
        case .verifyOld:
            if vm.repo.verifyPIN(pin) {
                error = nil
                step = .enter
            } else {
                error = "Incorrect PIN."
                shake += 1
            }
        case .enter:
            firstEntry = pin
            error = nil
            step = .confirm
        case .confirm:
            if pin == firstEntry {
                do {
                    try vm.repo.setupPIN(pin)
                    if !isChange { vm.repo.isLockEnabled = true }
                    dismiss()
                } catch {
                    self.error = "Could not save PIN. Try again."
                    shake += 1
                }
            } else {
                error = "PINs did not match."
                firstEntry = ""
                shake += 1
                step = .enter
            }
        }
    }
}

// ── Delete PIN (verify twice → remove) ──────────────────────────────────────────
private struct DeletePINView: View {
    let vm: AppLockViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .first
    @State private var error: String?
    @State private var shake = 0

    private enum Step: Hashable { case first, second }

    var body: some View {
        PINEntryView(
            title: "Delete PIN",
            subtitle: step == .first
                ? "Removing your PIN means the app can't be locked."
                : "Enter your PIN again to confirm.",
            minLength: vm.minPINLength,
            maxLength: vm.maxPINLength,
            showsBack: true,
            onBack: { dismiss() },
            errorMessage: error,
            shakeToken: shake,
            onSubmit: handle
        )
        .id(step)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func handle(_ pin: String) {
        guard vm.repo.verifyPIN(pin) else {
            error = "Incorrect PIN."
            shake += 1
            step = .first
            return
        }
        if step == .first {
            error = nil
            step = .second
        } else {
            try? vm.repo.removePIN()
            dismiss()
        }
    }
}

// ── App Lock timing (single choice) ─────────────────────────────────────────────
private struct AppLockTimingView: View {
    let vm: AppLockViewModel
    @State private var selection: Int   // seconds, or -1 for "Don't lock"

    init(vm: AppLockViewModel) {
        self.vm = vm
        _selection = State(initialValue: vm.repo.isLockEnabled ? vm.repo.lockTimeoutSeconds : -1)
    }

    // value -1 = Don't lock (lock disabled)
    static let options: [(label: String, seconds: Int)] = [
        ("Lock immediately", 0),
        ("After 1 minute", 60),
        ("After 3 minutes", 180),
        ("After 5 minutes", 300),
        ("After 15 minutes", 900),
        ("Don't lock", -1)
    ]

    /// The short value shown on the Security menu row.
    static func currentLabel(_ vm: AppLockViewModel) -> String {
        guard vm.repo.isLockEnabled else { return "Don't lock" }
        switch vm.repo.lockTimeoutSeconds {
        case 0:   return "Immediately"
        case 60:  return "1 min"
        case 180: return "3 min"
        case 300: return "5 min"
        case 900: return "15 min"
        default:  return "On"
        }
    }

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "App Lock") {
                ForEach(Self.options, id: \.seconds) { option in
                    SettingsSelectRow(label: option.label, isSelected: selection == option.seconds) {
                        selection = option.seconds
                        apply(option.seconds)
                    }
                }
            }
        }
    }

    private func apply(_ seconds: Int) {
        if seconds < 0 {
            vm.repo.isLockEnabled = false
        } else {
            vm.repo.isLockEnabled = true
            vm.repo.lockTimeoutSeconds = seconds
        }
    }
}

// ── Face ID setup ───────────────────────────────────────────────────────────────
private struct FaceIDSetupView: View {
    let vm: AppLockViewModel
    @State private var isOn = false

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: BiometryInfo.label) {
                SettingsToggleRow(label: "Use \(BiometryInfo.label)",
                                  systemImage: BiometryInfo.icon,
                                  isOn: binding)
            }
        }
        .onAppear { isOn = vm.repo.isBiometricEnabled }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                if newValue {
                    Task {
                        let ok = await vm.repo.authenticateWithBiometrics(
                            reason: "Enable \(BiometryInfo.label) for Human Program")
                        await MainActor.run {
                            isOn = ok
                            vm.repo.isBiometricEnabled = ok
                        }
                    }
                } else {
                    isOn = false
                    vm.repo.isBiometricEnabled = false
                }
            }
        )
    }
}

// ── Biometry info helper ────────────────────────────────────────────────────────
enum BiometryInfo {
    private static var ctx: (available: Bool, type: LABiometryType) {
        let c = LAContext()
        var err: NSError?
        let ok = c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        return (ok, c.biometryType)
    }
    static var available: Bool { ctx.available }
    static var label: String {
        let info = ctx
        guard info.available else { return "Face ID" }
        return info.type == .faceID ? "Face ID" : (info.type == .touchID ? "Touch ID" : "Face ID")
    }
    static var icon: String {
        let info = ctx
        guard info.available else { return "faceid" }
        return info.type == .faceID ? "faceid" : (info.type == .touchID ? "touchid" : "faceid")
    }
}
