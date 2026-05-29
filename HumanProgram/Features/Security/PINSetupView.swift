import SwiftUI

// ── PINSetupView ───────────────────────────────────────────────────────────────
// Presented as a sheet or full-screen cover when the user wants to create a PIN.
// Phase 1 → enter new PIN  (4–20 digits)
// Phase 2 → confirm PIN
// Success  → checkmark animation, then dismiss
// Error    → red message, return to phase 1
struct PINSetupView: View {

    @State var vm: AppLockViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var shakeOffset: CGFloat = 0
    @State private var showSuccess = false
    @State private var successScale: CGFloat = 0.5
    @State private var successOpacity: Double = 0

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if showSuccess {
                successOverlay
            } else {
                setupContent
            }
        }
        .onChange(of: vm.shakeCounter) { _, _ in
            shake()
        }
        .onChange(of: vm.setupPhase) { _, phase in
            if phase == .done {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showSuccess = true
                    successScale = 1.0
                    successOpacity = 1.0
                }
                // Dismiss after the animation completes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    vm.resetSetup()
                    dismiss()
                }
            } else if phase == .error {
                // After showing the error, return to first step automatically.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    vm.beginSetup()
                }
            }
        }
        .onDisappear {
            vm.resetSetup()
        }
    }

    // ── Setup content ──────────────────────────────────────────────────────────

    private var setupContent: some View {
        VStack(spacing: 0) {
            // Close button (top right)
            HStack {
                Spacer()
                Button {
                    vm.resetSetup()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding()
            }

            Spacer()

            // Heading
            VStack(spacing: 8) {
                Text(headingText)
                    .font(AppTypography.pageTitle())
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subheadingText)
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)

            // PIN dots
            PINDotsView(count: vm.pinInput.count, maxVisible: 6)
                .offset(x: shakeOffset)
                .padding(.bottom, 12)

            // Error message
            Group {
                if let msg = vm.errorMessage {
                    Text(msg)
                        .font(AppTypography.caption())
                        .foregroundStyle(AppColors.accentRed)
                } else {
                    Color.clear
                }
            }
            .frame(height: 20)
            .padding(.bottom, 28)

            // Numpad
            NumpadView { key in
                handleKey(key)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // ── Success overlay ────────────────────────────────────────────────────────

    private var successOverlay: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.accentGreen.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppColors.accentGreen)
            }
            .scaleEffect(successScale)
            .opacity(successOpacity)

            Text("PIN set successfully")
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .opacity(successOpacity)
        }
    }

    // ── Labels ─────────────────────────────────────────────────────────────────

    private var headingText: String {
        switch vm.setupPhase {
        case .confirmNew:  return "Confirm your PIN"
        default:           return "Create a PIN"
        }
    }

    private var subheadingText: String {
        switch vm.setupPhase {
        case .confirmNew:  return "Enter the same PIN again to confirm"
        default:           return "Enter 4 to 20 digits"
        }
    }

    // ── Key handling ───────────────────────────────────────────────────────────

    private func handleKey(_ key: NumpadKey) {
        switch key {
        case .digit(let d):
            vm.appendDigit(d)
        case .delete:
            vm.deleteLastDigit()
        case .submit:
            switch vm.setupPhase {
            case .enterNew:
                vm.submitFirstPIN()
            case .confirmNew:
                vm.submitConfirmPIN()
            default:
                break
            }
        }
    }

    // ── Shake ──────────────────────────────────────────────────────────────────

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
