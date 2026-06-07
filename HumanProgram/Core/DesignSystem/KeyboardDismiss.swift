import UIKit

/// Installs a window-level tap recognizer that dismisses the keyboard/numpad
/// when tapping empty space, without swallowing taps (controls still work).
enum KeyboardDismisser {
    private static var installed = false
    // Strong reference: a gesture recognizer holds its delegate weakly.
    private static let delegate = IgnoreTextInputDelegate()

    static func installIfNeeded() {
        guard !installed else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first else { return }

        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        tap.requiresExclusiveTouchType = false
        // Don't fire on taps that land on a text input or control — otherwise tapping
        // INSIDE a field to place the caret, select a word, or summon the copy/paste
        // menu would trigger endEditing mid-gesture, which blanked the selection
        // highlight and suppressed the menu (the selection range survived, so the
        // handles still showed). [owner: selection highlight + menu]
        tap.delegate = delegate
        window.addGestureRecognizer(tap)
        installed = true
    }

    private final class IgnoreTextInputDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            // Walk up from the touched view: if it's within a text input or a control,
            // let that view handle the touch (selection / menu / control action) and
            // don't dismiss. Taps on plain background still dismiss the keyboard.
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextView || current is UITextField || current is UIControl {
                    return false
                }
                view = current.superview
            }
            return true
        }

        // Coexist with the text view's own selection/tap recognizers.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
