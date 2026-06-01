import SwiftUI
import UIKit

/// Header-less text field backed by UITextView. A grey placeholder label stays
/// visible whenever the field is empty — even while focused — until the user
/// types. Uses the chosen app font; grows when multiline. Native selection is
/// preserved: tap places the caret where you tap, double-tap selects a word,
/// long-press shows the selection loupe/menu (we no longer force the caret to
/// the end on every tap, which was blocking double-tap-to-select).
struct AppTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 20
    var multiline: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = appUIFont(fontSize)
        tv.returnKeyType = multiline ? .default : .done
        tv.text = text
        tv.textColor = .label

        // Placeholder label, shown whenever the field is empty (focused or not).
        let ph = UILabel()
        ph.text = placeholder
        ph.font = appUIFont(fontSize)
        ph.textColor = .placeholderText
        ph.numberOfLines = 0
        ph.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(ph)
        NSLayoutConstraint.activate([
            ph.topAnchor.constraint(equalTo: tv.topAnchor),
            ph.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            ph.trailingAnchor.constraint(lessThanOrEqualTo: tv.trailingAnchor)
        ])
        ph.isHidden = !text.isEmpty

        // No custom tap recognizer: UITextView is natively focusable/selectable,
        // so tap-to-focus, tap-to-place-caret, and double-tap-to-select-a-word
        // all work as users expect.
        context.coordinator.placeholderLabel = ph
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self   // keep the latest binding/text
        uiView.font = appUIFont(fontSize)
        context.coordinator.placeholderLabel?.font = appUIFont(fontSize)
        context.coordinator.placeholderLabel?.text = placeholder
        if uiView.text != text { uiView.text = text }
        context.coordinator.placeholderLabel?.isHidden = !uiView.text.isEmpty
    }

    /// Constrain to the proposed width so the text wraps and the field reports
    /// a correct height (otherwise UITextView lays out as one giant line).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(34, ceil(fitted.height)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AppTextField
        weak var placeholderLabel: UILabel?

        init(_ parent: AppTextField) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            placeholderLabel?.isHidden = !tv.text.isEmpty
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Single-line fields: Return dismisses instead of inserting a newline.
            if !parent.multiline, text == "\n" {
                tv.resignFirstResponder()
                return false
            }
            return true
        }
    }
}
