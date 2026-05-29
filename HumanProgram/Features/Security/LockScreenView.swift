import SwiftUI
import LocalAuthentication

// ── LockScreenView ─────────────────────────────────────────────────────────────
// Full-screen cover shown whenever AppLockViewModel.isLocked == true.
// Shows PIN dots, a custom numpad, and (optionally) a Face ID button.
struct LockScreenView: View {

    @State var vm: AppLockViewModel
    @State private var shakeOffset: CGFloat = 0
    @State private var countdownText: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon / lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.bottom, 32)

                // PIN dots
                PINDotsView(count: vm.pinInput.count, maxVisible: 6)
                    .offset(x: shakeOffset)
                    .padding(.bottom, 12)

                // Error / countdown message
                errorRow
                    .frame(height: 20)
                    .padding(.bottom, 28)

                // Numpad
                NumpadView { key in
                    handleKey(key)
                }
                .padding(.horizontal, 32)

                // Biometrics button
                if vm.repo.isBiometricEnabled {
                    biometricButton
                        .padding(.top, 24)
                }

                Spacer()
            }
        }
        .onChange(of: vm.shakeCounter) { _, _ in
            shake()
        }
        .onReceive(timer) { _ in
            if vm.isInLockout {
                let s = vm.lockoutSecondsRemaining
                countdownText = "Try again in \(s)s"
            } else {
                countdownText = ""
            }
        }
        .task {
            // Auto-trigger biometrics when the screen appears if enabled.
            if vm.repo.isBiometricEnabled && !vm.isAuthenticating {
                await vm.unlockWithBiometrics()
            }
        }
    }

    // ── Error row ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var errorRow: some View {
        if vm.isInLockout {
            Text(countdownText.isEmpty ? vm.errorMessage ?? "" : countdownText)
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.accentRed)
        } else if let msg = vm.errorMessage {
            Text(msg)
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.accentRed)
        } else {
            Color.clear
        }
    }

    // ── Biometrics button ──────────────────────────────────────────────────────

    private var biometricButton: some View {
        Button {
            Task { await vm.unlockWithBiometrics() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: biometricIcon)
                    .font(.system(size: 20, weight: .light))
                Text(biometricLabel)
                    .font(AppTypography.buttonLabel())
            }
            .foregroundStyle(AppColors.accent)
        }
        .disabled(vm.isAuthenticating || vm.isInLockout)
    }

    private var biometricIcon: String {
        let context = LAContext()
        var err: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            return context.biometryType == .faceID ? "faceid" : "touchid"
        }
        return "faceid"
    }

    private var biometricLabel: String {
        let context = LAContext()
        var err: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            return context.biometryType == .faceID ? "Use Face ID" : "Use Touch ID"
        }
        return "Use Face ID"
    }

    // ── Key handling ───────────────────────────────────────────────────────────

    private func handleKey(_ key: NumpadKey) {
        switch key {
        case .digit(let d):
            vm.appendDigit(d)
        case .delete:
            vm.deleteLastDigit()
        case .submit:
            vm.submitUnlockPIN()
        }
    }

    // ── Shake animation ────────────────────────────────────────────────────────

    private func shake() {
        withAnimation(.easeOut(duration: 0.06)) { shakeOffset = -10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.06)) { shakeOffset = 10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.easeOut(duration: 0.06)) { shakeOffset = -6 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeOut(duration: 0.06)) { shakeOffset = 6 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        withAnimation(.easeOut(duration: 0.06)) { shakeOffset = 0 }
                    }
                }
            }
        }
    }
}

// ── PINDotsView ────────────────────────────────────────────────────────────────
// Shows up to maxVisible filled/empty circles, then "+N more" if over.
struct PINDotsView: View {
    let count: Int
    let maxVisible: Int

    var body: some View {
        HStack(spacing: 10) {
            if count <= maxVisible {
                // Show individual dots
                ForEach(0..<maxVisible, id: \.self) { i in
                    Circle()
                        .fill(i < count ? AppColors.textPrimary : Color.clear)
                        .overlay(
                            Circle().strokeBorder(AppColors.border, lineWidth: 1.5)
                        )
                        .frame(width: 14, height: 14)
                }
            } else {
                // Show maxVisible filled dots + "+N more" label
                ForEach(0..<maxVisible, id: \.self) { _ in
                    Circle()
                        .fill(AppColors.textPrimary)
                        .frame(width: 14, height: 14)
                }
                Text("+\(count - maxVisible)")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

// ── NumpadKey ──────────────────────────────────────────────────────────────────
enum NumpadKey {
    case digit(String)
    case delete
    case submit
}

// ── NumpadView ─────────────────────────────────────────────────────────────────
// 3-column grid: 1-9, then [submit] [0] [delete].
struct NumpadView: View {
    let onKey: (NumpadKey) -> Void

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["OK", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { label in
                        NumpadButton(label: label) {
                            onKey(keyFor(label))
                        }
                    }
                }
            }
        }
    }

    private func keyFor(_ label: String) -> NumpadKey {
        switch label {
        case "⌫":  return .delete
        case "OK": return .submit
        default:   return .digit(label)
        }
    }
}

// ── NumpadButton ───────────────────────────────────────────────────────────────
// Large circular tap target. Uses a custom ButtonStyle for press feedback.
private struct NumpadButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppColors.surfaceElevated)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle().strokeBorder(AppColors.border, lineWidth: 0.5)
                    )

                if label == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(AppColors.textPrimary)
                } else if label == "OK" {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                } else {
                    Text(label)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .buttonStyle(NumpadButtonStyle())
    }
}

private struct NumpadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
