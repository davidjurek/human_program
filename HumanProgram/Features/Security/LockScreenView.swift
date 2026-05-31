import SwiftUI

// ── LockScreenView ─────────────────────────────────────────────────────────────
// The app-unlock gate, shown full-screen whenever AppLockViewModel.isLocked == true.
// Reuses the shared PINEntryView (custom numpad + masked field + Face ID) — and on
// the gate specifically, shows NO text: just the numpad.
struct LockScreenView: View {
    @State var vm: AppLockViewModel

    var body: some View {
        PINEntryView(
            title: nil,
            subtitle: nil,
            minLength: vm.minPINLength,
            maxLength: vm.maxPINLength,
            showsBack: false,
            showsBiometric: vm.repo.isBiometricEnabled,
            onBiometric: { Task { await vm.unlockWithBiometrics() } },
            errorMessage: vm.errorMessage,
            shakeToken: vm.shakeCounter,
            onSubmit: { pin in
                vm.pinInput = pin
                vm.submitUnlockPIN()
            }
        )
        .task {
            if vm.repo.isBiometricEnabled && !vm.isAuthenticating {
                await vm.unlockWithBiometrics()
            }
        }
    }
}
