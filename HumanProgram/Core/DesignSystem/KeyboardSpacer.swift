import SwiftUI

/// Drives a bottom-spacer height from the keyboard's show/hide notifications.
///
/// The screens that manage their own keyboard avoidance (`SettingsScreen(manualKeyboardAvoidance:)`)
/// add a `Color.clear.frame(height: keyboardSpacer)` at the bottom of their scroll content so the
/// focused field has room. This modifier owns the two notification observers that set that height —
/// previously hand-copied (identically) into TodayView and the Schedule/Reminder/Exercise/Routine
/// editors. Keep the `@State` value and the spacer view in the screen; replace the observer pair
/// with `.keyboardSpacer($keyboardSpacer)`.
private struct KeyboardSpacerModifier: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.25)) { height = frame.height }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { height = 0 }
            }
    }
}

extension View {
    /// Updates `height` to the keyboard height while it is shown (animated easeOut 0.25),
    /// and back to 0 when it hides (easeOut 0.2). Pair with a bottom `Color.clear.frame(height:)`.
    func keyboardSpacer(_ height: Binding<CGFloat>) -> some View {
        modifier(KeyboardSpacerModifier(height: height))
    }
}
