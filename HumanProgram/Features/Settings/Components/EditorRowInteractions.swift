import SwiftUI
import UIKit

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
            let p = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
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

        // Begin only for horizontal drags over a row (vertical → scroll).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard parent.canStart(), let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            guard abs(v.x) > abs(v.y) else { return false }
            let loc = pan.location(in: nil)
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

/// Hours + minutes wheel where minutes snap to 5-minute steps. Hours are free
/// (0–23). `.time` renders "HH" / "MM"; `.duration` renders "Nh" / "Nm". A tap
/// (not a drag) requests the custom keypad; drags still scroll the wheel.
struct SteppedWheel: View {
    @Binding var minutes: Int
    enum Mode { case time, duration }
    let mode: Mode
    let onRequestKeypad: () -> Void

    private let step = 5
    private var minuteOptions: [Int] { Array(stride(from: 0, to: 60, by: step)) }

    private var hourBinding: Binding<Int> {
        Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + (minutes % 60) })
    }
    private var minuteBinding: Binding<Int> {
        Binding(get: { ((minutes % 60) / step) * step },
                set: { minutes = (minutes / 60) * 60 + $0 })
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { h in
                    Text(mode == .time ? String(format: "%02d", h) : "\(h)h").tag(h)
                }
            }
            .pickerStyle(.wheel)

            if mode == .time {
                Text(":").font(.system(size: 20, weight: .semibold))
            }

            Picker("", selection: minuteBinding) {
                ForEach(minuteOptions, id: \.self) { m in
                    Text(mode == .time ? String(format: "%02d", m) : "\(m)m").tag(m)
                }
            }
            .pickerStyle(.wheel)
        }
        .frame(width: 180, height: 150)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .simultaneousGesture(TapGesture().onEnded { onRequestKeypad() })
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
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        case .backspace:
            Button(action: onBackspace) {
                Image(systemName: "delete.left").font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        case .done:
            Button(action: onDone) {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        }
    }
}
