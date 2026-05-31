import SwiftUI
import DSKit

// Shared custom controls for the planning editors (Reminders, Recurring Tasks,
// Schedule). Text uses the chosen app font; containers are fixed-height so the
// layout doesn't shift when the font changes.
//
// Expandable rows (dropdown, time/interval pickers) share a single
// `openSection` binding so only one can be open at a time.

// MARK: - Weekday circle selector (S M T W T F S, 1=Sun … 7=Sat), centered

struct WeekdayCircleSelector: View {
    @Binding var selected: Set<Int>

    private let days: [(day: Int, letter: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(days, id: \.day) { item in
                let isOn = selected.contains(item.day)
                Button {
                    if isOn { selected.remove(item.day) } else { selected.insert(item.day) }
                } label: {
                    ZStack {
                        Circle().fill(isOn ? weekdaySelectedColor : Color.clear)
                        Text(item.letter)
                            .font(appFont(16, bold: true))
                            .foregroundStyle(Color.primary)
                            .fixedSize()
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Weekday strip (read-only S M T W T F S summary for list rows)

/// Compact S M T W T F S strip: enabled days bold/primary, the rest grey.
/// Used by the planning LIST rows (reminders, recurring tasks, schedule).
struct WeekdayStrip: View {
    let days: Set<Int>
    private let letters: [(day: Int, letter: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]
    var body: some View {
        HStack(spacing: 7) {
            ForEach(letters, id: \.day) { item in
                let on = days.contains(item.day)
                Text(item.letter)
                    .font(appFont(13, bold: on))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Clear interactive glass (toolbar buttons: stretch, no white card)

extension View {
    /// Applies a clear, interactive Liquid Glass effect (iOS 26) — gives the
    /// expand/stretch on press with no visible white capsule. No-op on older OS.
    @ViewBuilder
    func clearGlassButton(_ shape: some Shape = Circle()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: shape)
        } else {
            self
        }
    }
}

// MARK: - Shared popup glass (heavy blur, translucent)

/// UIKit blur so blur strength and tint opacity are independent (SwiftUI
/// materials couple them). A translucent style = heavy blur, low opacity.
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: style)
    }
}

extension View {
    /// Shared popup background — the liquid-glass look used by EVERY popup
    /// (confirm dialogs, the Repeat dropdown, the wheel popups). One place, so a
    /// glass tweak hits all of them.
    func popupGlass(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(PopupGlassBackground(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }

    /// Transparent liquid glass for the hub tiles — applied DIRECTLY to the view
    /// (the proper iOS-26 API; applying it as a background shape rendered opaque
    /// white). Kept SEPARATE from `popupGlass`. [#22]
    @ViewBuilder
    func hubTileGlass(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Genuinely translucent — the gradient shows through (ultra-thin material
        // reads transparent in the simulator, unlike glassEffect(.clear) which
        // renders opaque-white there). A faint white rim + soft shadow give the
        // liquid-glass sheen. [#22]
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}

/// Frosty liquid glass (iOS 26 `glassEffect(.regular)`), with a thin-material
/// blur fallback. A translucent white tint sits over the glass so content behind
/// is muted rather than bleeding through (the old `.clear`/ultra-thin look read
/// as confusing). One place — every popup picks up the frost.
struct PopupGlassBackground: View {
    let cornerRadius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if #available(iOS 26.0, *) {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                BlurView(style: .systemThinMaterial).clipShape(shape)
            }
        }
        .overlay(shape.fill(Color.white.opacity(0.6)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Anchored popup (screen-level, drops under a tapped value)

/// Collects the on-screen (global) frame of tagged views, keyed by id, so a
/// screen-level popup can anchor itself beneath the value that was tapped.
struct AnchorFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Tag this view so its frame (in `space`) is reported under `id` (read with
    /// `.onPreferenceChange(AnchorFrameKey.self)`). Use the SAME coordinate space
    /// for the matching `AnchoredPopup` so the two line up exactly.
    func anchorFrame(_ id: String, in space: CoordinateSpace = .global) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: AnchorFrameKey.self, value: [id: proxy.frame(in: space)])
            }
        )
    }
}

/// A translucent popup (shared `popupGlass`) that drops directly beneath an
/// on-screen anchor, aligned to it horizontally (so it sits under the tapped
/// value, not centered on screen), and flips above when there isn't room below.
/// Tapping outside closes it. Reused for the Repeat picker and the wheel/name
/// editors so they all share one look.
struct AnchoredPopup<Content: View>: View {
    let anchor: CGRect              // frame of the tapped value, in `space`
    var width: CGFloat = 210
    var estimatedHeight: CGFloat = 190
    var alignment: HorizontalAlignment = .trailing
    /// Must match the coordinate space used by the value's `anchorFrame(_:in:)`.
    var space: CoordinateSpace = .global
    /// Height of a bottom obstruction to clear (e.g. the custom keypad). The
    /// popup floats above it with a gap, same as it does for the keyboard.
    var bottomInset: CGFloat = 0
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let pos = position(in: geo)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onClose)
                content()
                    .frame(width: width)
                    .popupGlass(cornerRadius: 22)
                    .offset(x: pos.x, y: pos.y)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, UIScreen.main.bounds.height - frame.minY)
            withAnimation(.easeInOut(duration: 0.18)) { keyboardHeight = overlap }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { keyboardHeight = 0 }
        }
    }

    /// Computes the popup's offset within `geo`: drops under the anchor, flips
    /// above when tight, and lifts fully above the keyboard when it's up.
    private func position(in geo: GeometryProxy) -> CGPoint {
        let origin = geo.frame(in: space).origin
        let a = CGRect(x: anchor.minX - origin.x, y: anchor.minY - origin.y,
                       width: anchor.width, height: anchor.height)
        let gap: CGFloat = 8

        // Natural position (ignore the keyboard): under the value, flip above if
        // there's no room below on the full screen.
        var y = (geo.size.height - gap - a.maxY >= estimatedHeight) ? a.maxY + gap
                                                                     : a.minY - gap - estimatedHeight
        // Only lift for a bottom obstruction (keyboard or custom keypad) if it
        // would ACTUALLY cover the popup; if it's already fully visible, stay put.
        let obstruction = max(keyboardHeight, bottomInset)
        if obstruction > 0 {
            let obstructionTop = geo.size.height - obstruction - gap
            if y + estimatedHeight > obstructionTop { y = obstructionTop - estimatedHeight }
        }
        y = max(8, y)

        let rawX: CGFloat
        switch alignment {
        case .leading:  rawX = a.minX
        case .trailing: rawX = a.maxX - width
        default:        rawX = a.midX - width / 2
        }
        let x = min(max(8, rawX), max(8, geo.size.width - width - 8))
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Confirmation popup (custom, so it uses the chosen app font)

struct ConfirmPopup: View {
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // No dim — fully clear tap-catcher just dismisses on outside tap.
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(spacing: 20) {
                Text(message)
                    .font(appFont(20)).foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("Cancel").font(appFont(18)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    Button(action: onConfirm) {
                        Text(confirmTitle).font(appFont(18)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 300)
            .popupGlass(cornerRadius: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - Date field — label + native calendar popup (for custom date ranges)

/// A row with a label and a compact date control that opens the system calendar
/// popup on tap. Shared by the Recurring Task and Schedule editors.
struct DateFieldRow: View {
    let label: String
    @Binding var date: Date
    /// When set, the picker won't allow a date earlier than this (used for "To").
    var notBefore: Date? = nil

    var body: some View {
        HStack {
            DSText(label).dsTextStyle(.title3)
            Spacer(minLength: 8)
            DSDateField(date: $date, minDate: notBefore)   // custom DSKit calendar, card-less [#13]
        }
        .frame(height: 34)
    }
}

