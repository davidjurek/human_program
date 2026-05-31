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

// MARK: - App dropdown (translucent panel, expands inline)

/// Repeat-style picker. The options panel expands INLINE (pushing the rows below
/// down) rather than floating over them. The old floating version drew its panel
/// over the next row (the weekday circles), and that row intercepted the tap on
/// the top option — so selecting the first option (e.g. switching back to
/// "Weekly") silently did nothing. Expanding inline gives every option a real,
/// unobstructed tap target and matches the time/duration rows' behaviour.
struct AppDropdown: View {
    let label: String
    let options: [(value: String, title: String)]
    @Binding var selection: String
    @Binding var openSection: String?
    let id: String

    private var isOpen: Bool { openSection == id }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DSText(label).dsTextStyle(.title3)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy(duration: 0.15)) { openSection = isOpen ? nil : id }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentTitle).font(appFont(18)).foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 34)

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options, id: \.value) { option in
                        Button {
                            selection = option.value
                            withAnimation(.snappy(duration: 0.15)) { openSection = nil }
                        } label: {
                            HStack(spacing: 12) {
                                Text(option.title).font(appFont(18)).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if option.value == selection {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .popupGlass()
                .transition(.opacity)
            }
        }
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

// MARK: - Time field — value-only tap opens the wheel

struct TimeFieldRow: View {
    let id: String
    let label: String
    @Binding var minutesOfDay: Int
    @Binding var openSection: String?

    private var isOpen: Bool { openSection == id }
    private var hour: Int { minutesOfDay / 60 }
    private var minute: Int { minutesOfDay % 60 }
    private var timeString: String { String(format: "%02d:%02d", hour, minute) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DSText(label).dsTextStyle(.title3)
                Spacer()
                Button { withAnimation { openSection = isOpen ? nil : id } } label: {
                    Text(timeString).font(appFont(18)).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 34)

            if isOpen {
                WheelHourMinute(minutesOfDay: $minutesOfDay)
                    .transition(.opacity)
            }
        }
    }
}

/// Narrow, centered hour:minute wheel. Scrolls normally (drags scroll the
/// wheel). A tap opens a single numpad for the whole time (HHMM, HH first).
struct WheelHourMinute: View {
    @Binding var minutesOfDay: Int

    @State private var typed = ""
    @FocusState private var keypadFocused: Bool

    private var hourBinding: Binding<Int> {
        Binding(get: { minutesOfDay / 60 }, set: { minutesOfDay = $0 * 60 + (minutesOfDay % 60) })
    }
    private var minuteBinding: Binding<Int> {
        Binding(get: { minutesOfDay % 60 }, set: { minutesOfDay = (minutesOfDay / 60) * 60 + $0 })
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)

            Text(":").font(.system(size: 20, weight: .semibold))

            Picker("", selection: minuteBinding) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
        }
        .frame(width: 210, height: 140)
        .frame(maxWidth: .infinity)
        // Tap (not drag) opens the numpad; drags still scroll the wheel.
        .simultaneousGesture(TapGesture().onEnded {
            typed = ""
            keypadFocused = true
        })
        .overlay(
            TextField("", text: $typed)
                .keyboardType(.numberPad)
                .focused($keypadFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onChange(of: typed) { _, _ in applyTyped() }
        )
    }

    private func applyTyped() {
        let s = String(typed.filter(\.isNumber).prefix(4))
        guard !s.isEmpty else { return }
        var hh = 0, mm = 0
        hh = Int(String(s.prefix(2))) ?? 0
        if s.count >= 3 { mm = Int(String(s.dropFirst(2))) ?? 0 }
        minutesOfDay = min(23, hh) * 60 + min(59, mm)
        if s.count >= 4 { keypadFocused = false }
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
            Group {
                if let notBefore {
                    DatePicker("", selection: $date, in: notBefore..., displayedComponents: .date)
                } else {
                    DatePicker("", selection: $date, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .tint(weekdaySelectedColor)
        }
        .frame(height: 34)
    }
}

// MARK: - Interval field ("Every N min/hr"), value-only tap

struct IntervalFieldRow: View {
    let id: String
    let label: String
    @Binding var amount: Int
    @Binding var unitIsHours: Bool
    @Binding var openSection: String?

    private var isOpen: Bool { openSection == id }
    private var unitLabel: String { unitIsHours ? (amount == 1 ? "hour" : "hours") : "min" }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DSText(label).dsTextStyle(.title3)
                Spacer(minLength: 8)
                Button { withAnimation { openSection = isOpen ? nil : id } } label: {
                    Text("\(amount) \(unitLabel)").font(appFont(18)).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 34)

            if isOpen {
                HStack(spacing: 0) {
                    Picker("", selection: $amount) {
                        ForEach(1...(unitIsHours ? 10 : 59), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("", selection: $unitIsHours) {
                        Text("min").tag(false)
                        Text("hr").tag(true)
                    }
                    .pickerStyle(.wheel)
                }
                .frame(width: 210, height: 140)
                .frame(maxWidth: .infinity)
                .onChange(of: unitIsHours) { _, hours in
                    if hours { amount = min(amount, 10) }
                    if amount < 1 { amount = 1 }
                }
            }
        }
    }
}
