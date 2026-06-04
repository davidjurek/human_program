import SwiftUI

// Shared PIN-entry screen used everywhere a PIN is typed: create, change,
// delete-verify, the app-unlock gate, and the Factory-Reset gate. One component
// so the look + behavior stay identical. Uses the custom GlassKeypad numpad and a
// masked field (last digit visible, the rest masked) — no dot indicators.
struct PINEntryView: View {
    /// Small instruction near the field (nil = nothing, e.g. the unlock gate).
    var title: String? = nil
    /// Sub-hint under the title (e.g. "4–40 digits").
    var subtitle: String? = nil
    var minLength: Int = 4
    var maxLength: Int = 40
    /// Shows a back chevron top-left (pushed pages); the gate passes false.
    var showsBack: Bool = false
    var onBack: (() -> Void)? = nil
    var showsBiometric: Bool = false
    var onBiometric: (() -> Void)? = nil
    /// Error text shown in red under the field.
    var errorMessage: String? = nil
    /// Increment to shake the field and clear the current entry (wrong PIN, etc.).
    var shakeToken: Int = 0
    /// Called when ✓ is pressed and the entry meets the minimum length.
    let onSubmit: (String) -> Void

    @State private var entry = ""
    @State private var shakeOffset: CGFloat = 0
    /// Bumped on each shake so a re-triggered shake cancels the previous step
    /// sequence instead of overlapping with it. [#168]
    @State private var shakeRun = 0

    var body: some View {
        ZStack {
            SettingsBackground()

            // One vertical flow: the padlock→field→buttons block is centred in the
            // space ABOVE the keypad, and the keypad is the bottom sibling — so the
            // numpad can never cover the field, error, or Face ID button on any
            // screen size. The layout (padlock/title/field/button positions) is
            // identical across every PIN screen because they all render this view.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                contentBlock
                Spacer(minLength: 0)
                GlassKeypad(onDigit: digit, onBackspace: backspace, onDone: done)
            }

            // Back chevron pinned top-left (over the flow).
            if showsBack {
                VStack {
                    HStack {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .a11yTapBorder(Rectangle())
                            .onTapGesture { onBack?() }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                }
            }
        }
        // Parent-rejected entry (wrong PIN, mismatch, etc.): shake + clear. Same path
        // as a too-short ✓ so every "wrong" outcome behaves identically. [#171]
        .onChange(of: shakeToken) { _, _ in triggerShake() }
    }

    /// Padlock → optional title/subtitle → masked field → error → optional Face ID.
    private var contentBlock: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.bottom, 22)

            if let title {
                PINTitleText(title)
                    .padding(.bottom, 6)
            }
            if let subtitle {
                Text(subtitle)
                    .font(appFont(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }

            maskedField
                .padding(.top, 18)          // [#45] more gap above the field
                .offset(x: shakeOffset)

            Text(errorMessage ?? " ")
                .font(appFont(14))
                .foregroundStyle(.red)
                .frame(height: 20)
                .padding(.top, 10)

            if showsBiometric {
                Button { onBiometric?() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid").font(.system(size: 20, weight: .light))
                        Text("Use Face ID").font(appFont(16))
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(cornerRadius: 6)
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Masked field

    private var maskedField: some View {
        let chars = Array(entry)
        // Marks are CENTERED while they fit; once the row overflows the field,
        // head-truncation drops the leftmost marks so the LAST typed digit always
        // lands near the right edge (the cluster is pushed off the left). Wider
        // tracking gives a clear gap between marks. [owner]
        let masked = chars.enumerated()
            .map { i, c in i == chars.count - 1 ? String(c) : "•" }
            .joined(separator: " ")
        return Text(masked.isEmpty ? " " : masked)
            .font(appFont(30))
            .tracking(6)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 40)
    }

    // MARK: - Keypad

    private func digit(_ d: String) {
        Haptics.impact(.light)   // tactile feedback on every keypad press [owner]
        guard entry.count < maxLength else { return }
        entry += d
    }

    private func backspace() {
        guard !entry.isEmpty else { return }   // nothing to delete → no haptic [owner]
        Haptics.impact(.light)
        entry.removeLast()
    }

    private func done() {
        Haptics.impact(.light)
        // Too-short ✓ is a "wrong" entry too: shake + clear, same as a parent
        // rejection, so every wrong path clears the digits identically. [#171]
        guard entry.count >= minLength else { triggerShake(); return }
        onSubmit(entry)
    }

    /// Shake the field and clear the entry. Token-guarded so a re-trigger cancels the
    /// in-flight step sequence — no overlapping timers, the shake restarts cleanly. [#168][#171]
    private func triggerShake() {
        entry = ""
        shakeRun += 1
        let run = shakeRun
        let seq: [CGFloat] = [-10, 10, -6, 6, 0]
        for (i, off) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(i)) {
                guard run == shakeRun else { return } // a newer shake superseded this one
                withAnimation(.easeOut(duration: 0.06)) { shakeOffset = off }
            }
        }
    }
}

/// Small helper so PINEntryView's title uses the app font at a title size without
/// pulling DSKit into this file (kept lightweight / reusable in plain SwiftUI).
private struct PINTitleText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(appFont(22, bold: true)).foregroundStyle(.primary)
    }
}
