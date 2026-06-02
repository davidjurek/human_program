import SwiftUI
import UIKit

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
        // Auto-engage Face ID when the lock appears AND every time the app becomes
        // active while locked — so a warm return (or cold launch) prompts Face ID
        // without the user tapping the button. The VM disarms after one prompt per
        // lock so a Face ID cancel can't loop.
        .task { vm.autoPromptBiometricIfArmed() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            vm.autoPromptBiometricIfArmed()
        }
    }
}
