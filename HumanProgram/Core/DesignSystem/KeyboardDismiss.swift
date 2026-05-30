import UIKit

/// Installs a window-level tap recognizer that dismisses the keyboard/numpad
/// when tapping anywhere, without swallowing taps (controls still work).
enum KeyboardDismisser {
    private static var installed = false

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
        window.addGestureRecognizer(tap)
        installed = true
    }
}
