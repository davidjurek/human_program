import SwiftUI
import UIKit

/// Shared numeric-keypad text logic for the planning editors' time fields. Pure
/// string/Int math (no view state), so the Schedule and Reminder editors share ONE
/// HHMM rule instead of each keeping a byte-identical copy that could drift.
enum TimeKeypad {
    /// Append a digit, keep only digits, cap at the last 4 (HHMM).
    static func appending(_ digit: String, to typed: String) -> String {
        String((typed + digit).filter(\.isNumber).suffix(4))
    }

    /// Parse typed "HHMM" digits to minutes-of-day, minutes snapped to the nearest 5
    /// (the same rule as the wheel). Returns nil if `typed` is empty.
    static func minutes(from typed: String) -> Int? {
        guard !typed.isEmpty else { return nil }
        let hh = min(23, Int(String(typed.prefix(2))) ?? 0)
        var mm = typed.count >= 3 ? (Int(String(typed.dropFirst(2))) ?? 0) : 0
        mm = min(55, Int((Double(mm) / 5).rounded()) * 5)
        return hh * 60 + mm
    }
}

// Shared interaction infrastructure for the planning editors (Schedule, Exercise,
// …). These pieces were first written for the Schedule editor; they live here so
// every editable-row screen reuses the SAME hold-to-reorder, swipe-to-delete,
// keyboard nudge, and custom keypad behaviour instead of re-deriving it.
//
// The recognizers are generic over the row's identifier type (`ID: Hashable`) so
// they work whether rows are keyed by `UUID` (Schedule's draft blocks) or any
// other Hashable id.

// MARK: - Row frame reporting

/// Reports each editable row's window (global) frame so the reorder/swipe
/// recognizers can tell which row a gesture began on. Generic over the row id.
struct RowFrameKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Reports the custom keypad's measured height so an anchored wheel popup can sit
/// a small, consistent gap above it.
struct KeypadHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// The bottom-pinned GlassKeypad overlay shared by the Schedule + Reminder editors:
/// it slides up from the bottom and reports its measured height (so popups lift
/// above it). One copy instead of the same block in each editor. [#47]
struct KeypadOverlay: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onDone: () -> Void
    var onHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            GlassKeypad(onDigit: onDigit, onBackspace: onBackspace, onDone: onDone)
                .background(GeometryReader { g in
                    Color.clear.preference(key: KeypadHeightKey.self, value: g.size.height)
                })
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.move(edge: .bottom))
        .onPreferenceChange(KeypadHeightKey.self) { onHeight($0) }
    }
}

// MARK: - Reorder (UIKit long-press)

/// Drives row reordering with a real UIKit long-press recognizer installed on the
/// enclosing scroll view. A genuine 0.4s hold with a small allowable movement
/// means a tap, a scroll, or a swipe never arms it — only a deliberate stationary
/// hold. It coexists with scrolling and SwiftUI taps (simultaneous recognition,
/// doesn't cancel touches).
struct ReorderRecognizer<ID: Hashable>: UIViewRepresentable {
    var rowFrames: [ID: CGRect]            // window coords
    var onBegan: (ID) -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false  // just a hook to reach the scroll view
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.install(from: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ReorderRecognizer
        private weak var recognizer: UILongPressGestureRecognizer?
        private var activeId: ID?
        private var startY: CGFloat = 0
        init(_ parent: ReorderRecognizer) { self.parent = parent }

        func install(from view: UIView) {
            guard recognizer == nil else { return }
            var v: UIView? = view
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let target = v else {
                DispatchQueue.main.async { [weak self, weak view] in
                    if let self, let view { self.install(from: view) }
                }
                return
            }
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            lp.minimumPressDuration = 0.4
            lp.allowableMovement = 10
            lp.delegate = self
            lp.cancelsTouchesInView = false
            target.addGestureRecognizer(lp)
            recognizer = lp
        }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: nil)   // window coordinates
            switch g.state {
            case .began:
                if let id = parent.rowFrames.first(where: { $0.value.contains(p) })?.key {
                    activeId = id
                    startY = p.y
                    parent.onBegan(id)
                }
            case .changed:
                if activeId != nil { parent.onChanged(p.y - startY) }
            case .ended:
                if activeId != nil { parent.onEnded(p.y - startY) }
                activeId = nil
            case .cancelled, .failed:
                if activeId != nil { parent.onCancelled() }
                activeId = nil
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Swipe-to-delete (UIKit pan)

/// A pan that commits to a horizontal swipe as soon as the finger moves a few
/// points sideways (and sideways more than up/down), and fails for vertical drags
/// so they fall through to scrolling. Beginning this EARLY (≈4pt, before SwiftUI's
/// ~10pt tap slop) is what guarantees even a small horizontal slide engages the
/// swipe and can never be mistaken for a tap. [owner: tiny-swipe must not tap]
final class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    private var startPoint: CGPoint = .zero
    private let beginThreshold: CGFloat = 4
    private let failThreshold: CGFloat = 8

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        startPoint = touches.first?.location(in: view) ?? .zero
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let p = touches.first?.location(in: view) else { return }
        let dx = p.x - startPoint.x
        let dy = p.y - startPoint.y
        if abs(dx) > beginThreshold, abs(dx) > abs(dy) {
            state = .began                     // horizontal slide → engage the swipe
        } else if abs(dy) > failThreshold, abs(dy) >= abs(dx) {
            state = .failed                    // vertical drag → let the scroll view have it
        }
    }
}

/// Drives swipe-to-delete with a UIKit pan recognizer that only begins for
/// HORIZONTAL drags — so vertical drags fall straight through to native
/// scrolling. Hit-tests which row the pan started on.
struct SwipePanRecognizer<ID: Hashable>: UIViewRepresentable {
    var rowFrames: [ID: CGRect]
    var canStart: () -> Bool
    var onBegan: (ID) -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.install(from: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SwipePanRecognizer
        private weak var pan: UIPanGestureRecognizer?
        private var activeId: ID?
        init(_ parent: SwipePanRecognizer) { self.parent = parent }

        func install(from view: UIView) {
            guard pan == nil else { return }
            var v: UIView? = view
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let target = v else {
                DispatchQueue.main.async { [weak self, weak view] in
                    if let self, let view { self.install(from: view) }
                }
                return
            }
            let p = HorizontalPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            p.delegate = self
            p.cancelsTouchesInView = false
            target.addGestureRecognizer(p)
            pan = p
        }

        @objc func handle(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                let loc = g.location(in: nil)
                if let id = parent.rowFrames.first(where: { $0.value.contains(loc) })?.key {
                    activeId = id
                    parent.onBegan(id)
                }
            case .changed:
                if activeId != nil { parent.onChanged(g.translation(in: g.view).x) }
            case .ended:
                if activeId != nil { parent.onEnded(g.translation(in: g.view).x, g.velocity(in: g.view).x) }
                activeId = nil
            case .cancelled, .failed:
                if activeId != nil { parent.onEnded(g.translation(in: g.view).x, 0) }
                activeId = nil
            default:
                break
            }
        }

        // Begin only for horizontal drags over a row (vertical → scroll). The custom
        // recognizer already commits to .began only when horizontal motion dominates,
        // so here we confirm the gate and that the touch started on a row (translation,
        // not velocity, which is unreliable at the early begin threshold).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard parent.canStart(), let pan = g as? UIPanGestureRecognizer else { return false }
            let t = pan.translation(in: pan.view)
            guard abs(t.x) >= abs(t.y) else { return false }
            let loc = pan.location(in: nil)
            // Leave the leading-edge zone to iOS's swipe-back gesture, so a swipe-back
            // from the left edge of a list screen always works (and isn't eaten by a
            // row's delete-swipe). [owner: edge swipe-back]
            if loc.x < 24 { return false }
            return parent.rowFrames.contains(where: { $0.value.contains(loc) })
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Keyboard scroll nudge

/// Scrolls the focused text field to a uniform gap above the keyboard. SwiftUI's
/// avoidance is OFF on these screens and a bottom spacer (= keyboard height) gives
/// the scroll the range — so this can position the field itself, identically for
/// every field, without SwiftUI fighting/resetting it. Only scrolls when the
/// field is actually covered/too close; clear fields are left alone.
struct KeyboardScrollNudge: UIViewRepresentable {
    var gap: CGFloat = 20

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        context.coordinator.hostView = v
        context.coordinator.start()
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.hostView = uiView }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: KeyboardScrollNudge
        weak var hostView: UIView?
        private var didNudge = false
        init(_ parent: KeyboardScrollNudge) { self.parent = parent }

        func start() {
            NotificationCenter.default.addObserver(self, selector: #selector(didShow(_:)),
                name: UIResponder.keyboardDidShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(willHide),
                name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        @objc func willHide() { didNudge = false }

        // Runs after the keyboard is up (so the bottom spacer is laid out and the
        // scroll has range). One nudge per keyboard session.
        @objc func didShow(_ note: Notification) {
            guard !didNudge,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let host = hostView else { return }
            var v: UIView? = host
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let scroll = v as? UIScrollView,
                  let responder = scroll.firstResponderInHierarchy else { return }
            didNudge = true
            let fieldFrame = responder.convert(responder.bounds, to: nil)   // window coords
            let overlap = fieldFrame.maxY - (frame.minY - parent.gap)
            guard overlap > 1 else { return }   // already clear → leave it
            let maxOffset = max(0, scroll.contentSize.height + scroll.adjustedContentInset.bottom
                                   - scroll.bounds.height)
            let target = min(scroll.contentOffset.y + overlap, maxOffset)
            guard target > scroll.contentOffset.y + 1 else { return }
            UIView.animate(withDuration: 0.13, delay: 0, options: [.curveEaseOut]) {
                scroll.contentOffset = CGPoint(x: scroll.contentOffset.x, y: target)
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

extension UIView {
    var firstResponderInHierarchy: UIView? {
        if isFirstResponder { return self }
        for sub in subviews { if let r = sub.firstResponderInHierarchy { return r } }
        return nil
    }
}

// MARK: - Stepped wheel (hours/minutes or generic value), tap → keypad

/// Hours + minutes wheel where minutes snap to 5-minute steps. `.duration`
/// renders "Nh" / "Nm" (always). `.time` honors the app's 12h/24h setting: in
/// 24h it shows HH (0–23) : MM; in 12h it shows H (1–12) : MM + an AM/PM column.
/// A tap (not a drag) requests the custom keypad; drags still scroll the wheel.
/// (The keypad always types HHMM in 24h — unambiguous — regardless of display.)
struct SteppedWheel: View {
    @Binding var minutes: Int
    enum Mode { case time, duration }
    let mode: Mode
    let onRequestKeypad: () -> Void

    private let step = 5
    private var minuteOptions: [Int] { Array(stride(from: 0, to: 60, by: step)) }
    private var is24: Bool { TimeFormatSetting.is24Hour }

    private var hourBinding: Binding<Int> {
        Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + (minutes % 60) })
    }
    private var minuteBinding: Binding<Int> {
        Binding(get: { ((minutes % 60) / step) * step },
                set: { minutes = (minutes / 60) * 60 + $0 })
    }
    /// Displayed hour 1…12 (12h mode), preserving the current AM/PM.
    private var hour12Binding: Binding<Int> {
        Binding(
            get: { let h = minutes / 60 % 12; return h == 0 ? 12 : h },
            set: { newH12 in
                let isPM = (minutes / 60) >= 12
                let base = newH12 % 12            // 12 → 0
                minutes = (base + (isPM ? 12 : 0)) * 60 + (minutes % 60)
            }
        )
    }
    /// true = PM (12h mode).
    private var isPMBinding: Binding<Bool> {
        Binding(
            get: { (minutes / 60) >= 12 },
            set: { pm in
                let base = (minutes / 60) % 12    // 0…11
                minutes = (base + (pm ? 12 : 0)) * 60 + (minutes % 60)
            }
        )
    }

    var body: some View {
        Group {
            if mode == .duration {
                HStack(spacing: 0) {
                    Picker("", selection: hourBinding) {
                        ForEach(0..<24, id: \.self) { Text("\($0)h").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("", selection: minuteBinding) {
                        ForEach(minuteOptions, id: \.self) { Text("\($0)m").tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(width: 180, height: 150)
            } else if is24 {
                HStack(spacing: 0) {
                    Picker("", selection: hourBinding) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Text(":").font(.system(size: 20, weight: .semibold))
                    Picker("", selection: minuteBinding) {
                        ForEach(minuteOptions, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(width: 180, height: 150)
            } else {
                // 12-hour: hour (1–12) : minute  +  AM/PM
                HStack(spacing: 0) {
                    Picker("", selection: hour12Binding) {
                        ForEach(1...12, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel).frame(maxWidth: .infinity)
                    Text(":").font(.system(size: 20, weight: .semibold))
                    Picker("", selection: minuteBinding) {
                        ForEach(minuteOptions, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    .pickerStyle(.wheel).frame(maxWidth: .infinity)
                    Picker("", selection: isPMBinding) {
                        Text("AM").tag(false)
                        Text("PM").tag(true)
                    }
                    .pickerStyle(.wheel).frame(maxWidth: .infinity)
                }
                .frame(width: 230, height: 150)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .simultaneousGesture(TapGesture().onEnded { onRequestKeypad() })
    }
}

/// Amount + unit (min / hr) two-wheel picker for reminder intervals ("Every N").
/// Lives inside an `AnchoredPopup`; no custom keypad (the amount range is small
/// enough to just scroll). Mirrors the old IntervalFieldRow's wheel.
struct IntervalWheel: View {
    @Binding var amount: Int
    @Binding var unitIsHours: Bool

    private var amountRange: ClosedRange<Int> { unitIsHours ? 1...10 : 1...59 }

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $amount) {
                ForEach(Array(amountRange), id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            Picker("", selection: $unitIsHours) {
                Text("min").tag(false)
                Text("hr").tag(true)
            }
            .pickerStyle(.wheel)
        }
        .frame(width: 190, height: 150)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .onChange(of: unitIsHours) { _, hours in
            if hours, amount > 10 { amount = 10 }
            if amount < 1 { amount = 1 }
        }
    }
}

/// A single integer-value wheel (0…max). Tap requests the custom keypad; drags
/// scroll the wheel. Used where a row edits a plain count (e.g. sets / reps).
struct CountWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""
    let onRequestKeypad: () -> Void

    var body: some View {
        Picker("", selection: $value) {
            ForEach(Array(range), id: \.self) { n in
                Text(suffix.isEmpty ? "\(n)" : "\(n) \(suffix)").tag(n)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 120, height: 150)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .simultaneousGesture(TapGesture().onEnded { onRequestKeypad() })
    }
}

// MARK: - Custom numeric keypad

/// One key on the custom keypad.
enum KeypadKey {
    case digit(String, String)   // number, decorative letters
    case backspace
    case done
}

/// Custom numeric keypad — a bottom-pinned liquid-glass panel with capsule keys,
/// replacing Apple's numpad so the layout, look, and the ✓ are fully ours.
struct GlassKeypad: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onDone: () -> Void

    private let rows: [[KeypadKey]] = [
        [.digit("1", ""), .digit("2", "ABC"), .digit("3", "DEF")],
        [.digit("4", "GHI"), .digit("5", "JKL"), .digit("6", "MNO")],
        [.digit("7", "PQRS"), .digit("8", "TUV"), .digit("9", "WXYZ")],
        [.backspace, .digit("0", ""), .done]
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        keyButton(key)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        // Extra bottom space lifts the keys up by ~one row (empty space below).
        .padding(.bottom, 84)
        .frame(maxWidth: .infinity)
        .background(keypadGlass)
    }

    @ViewBuilder
    private var keypadGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26.0, *) {
            // Clear glass — more see-through/glassy than .regular.
            shape.fill(.clear).glassEffect(.clear, in: shape).ignoresSafeArea(edges: .bottom)
        } else {
            BlurView(style: .systemUltraThinMaterial)
                .clipShape(shape)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Key fill — light in light mode, dark grey in dark mode (so the keys don't glare
    /// against the dark glass). One adaptive color for every key. [owner: numpad dark mode]
    static let keyFill = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1.0)
            : UIColor(white: 1.0, alpha: 0.8)
    })

    @ViewBuilder
    private func keyButton(_ key: KeypadKey) -> some View {
        switch key {
        case .digit(let number, let letters):
            Button { onDigit(number) } label: {
                VStack(spacing: 0) {
                    Text(number).font(.system(size: 24, weight: .regular))
                    if !letters.isEmpty {
                        Text(letters).font(.system(size: 9, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }
                .keypadKeyChrome()
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Capsule())
        case .backspace:
            BackspaceKey(onBackspace: onBackspace)
        case .done:
            Button(action: onDone) {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold))
                    .keypadKeyChrome()
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Capsule())
        }
    }
}

/// Backspace key with press-and-hold auto-repeat, shared by every GlassKeypad use
/// (PIN entry + the planning editors). A quick tap deletes once; holding repeats
/// with a natural acceleration — the first 3 deletes at a regular pace, the next 2
/// quicker, then a steady faster pace. [owner: hold-to-delete]
private struct BackspaceKey: View {
    let onBackspace: () -> Void
    @State private var repeatTask: Task<Void, Never>? = nil
    @State private var pressing = false

    var body: some View {
        Image(systemName: "delete.left").font(.system(size: 20))
            .keypadKeyChrome()
            .contentShape(Capsule())
            .a11yTapBorder(Capsule())
            // A min-distance-0 drag fires on touch-down (start the repeat) and on
            // lift (stop it); the repeat cadence is driven by our own task, so a
            // perfectly still hold still repeats.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressing { begin() } }
                    .onEnded { _ in end() }
            )
    }

    private func begin() {
        pressing = true
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            var count = 0
            while !Task.isCancelled {
                onBackspace()
                count += 1
                // Gap BEFORE the next delete: deletes 1–3 regular, 4–5 quicker, 6+ fastest.
                let gap: Double = count <= 2 ? 0.32 : (count <= 4 ? 0.17 : 0.09)
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
        }
    }

    private func end() {
        pressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

private extension View {
    /// Shared key chrome (primary glyph, full-width, 50pt tall, adaptive capsule fill)
    /// so the three key types can't drift. [#146]
    func keypadKeyChrome() -> some View {
        self.foregroundStyle(.primary)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Capsule().fill(GlassKeypad.keyFill))
    }
}
