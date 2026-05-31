import SwiftUI

// Shared PIN-entry screen used everywhere a PIN is typed: create, change,
// delete-verify, the app-unlock gate, and the Factory-Reset gate. One component
// so the look + behavior stay identical. Uses the custom GlassKeypad numpad and a
// masked field (last digit visible, the rest masked) — no dot indicators.
struct PINEntryView: View {
    /// Small instruction near the field (nil = nothing, e.g. the unlock gate).
    var title: String? = nil
    /// Sub-hint under the title (e.g. "4–20 digits").
    var subtitle: String? = nil
    var minLength: Int = 4
    var maxLength: Int = 20
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

    var body: some View {
        ZStack {
            SettingsBackground()

            // Back chevron pinned top-left.
            if showsBack {
                VStack {
                    HStack {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture { onBack?() }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                }
            }

            // Padlock → text → field block, centered at ~2/5 of the screen height.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.primary)
                        .padding(.bottom, 22)

                    if let title {
                        DSTextTitle(title)
                            .padding(.bottom, 6)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(appFont(15))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 18)
                    }

                    maskedField
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
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    }
                }
                .frame(width: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.4)
            }

            VStack(spacing: 0) {
                Spacer()
                GlassKeypad(onDigit: digit, onBackspace: backspace, onDone: done)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: shakeToken) { _, _ in
            triggerShake()
            entry = ""
        }
    }

    // MARK: - Masked field

    private var maskedField: some View {
        let chars = Array(entry)
        let masked = chars.enumerated()
            .map { i, c in i == chars.count - 1 ? String(c) : "•" }
            .joined(separator: "  ")
        return Text(masked)
            .font(appFont(30))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 40)
    }

    // MARK: - Keypad

    private func digit(_ d: String) {
        guard entry.count < maxLength else { return }
        entry += d
    }

    private func backspace() {
        guard !entry.isEmpty else { return }
        entry.removeLast()
    }

    private func done() {
        guard entry.count >= minLength else { triggerShake(); return }
        onSubmit(entry)
    }

    private func triggerShake() {
        let seq: [CGFloat] = [-10, 10, -6, 6, 0]
        for (i, off) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(i)) {
                withAnimation(.easeOut(duration: 0.06)) { shakeOffset = off }
            }
        }
    }
}

/// Small helper so PINEntryView's title uses the app font at a title size without
/// pulling DSKit into this file (kept lightweight / reusable in plain SwiftUI).
private struct DSTextTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(appFont(22, bold: true)).foregroundStyle(.primary)
    }
}
