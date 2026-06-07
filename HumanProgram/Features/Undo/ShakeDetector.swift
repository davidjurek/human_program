import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when the device is shaken anywhere in the app.
    static let humanProgramShake = Notification.Name("HumanProgramShake")
    /// Posted to pop the navigation stack all the way back to the hub (top-level menu).
    /// Used after first-time PIN creation so the user exits to the hub instead of
    /// landing on the now-PIN-gated Security screen.
    static let humanProgramExitToHub = Notification.Name("HumanProgramExitToHub")
}

/// Invisible host that catches the device-shake motion event anywhere in the app
/// and posts `.humanProgramShake`. It keeps itself first responder so motion events
/// reach it while the user is idle on a screen. When a text field is editing, iOS
/// routes the shake to that field (its own shake-to-undo) instead — the desired
/// behaviour. First responder is re-asserted when the keyboard hides or the app
/// reactivates so it never goes stale after editing.
struct ShakeDetector: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeViewController { ShakeViewController() }
    func updateUIViewController(_ vc: ShakeViewController, context: Context) {}
}

final class ShakeViewController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reassertFirstResponder),
            name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(reassertFirstResponder),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func reassertFirstResponder() {
        if !isFirstResponder { becomeFirstResponder() }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .humanProgramShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
