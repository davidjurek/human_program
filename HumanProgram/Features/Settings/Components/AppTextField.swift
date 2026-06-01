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
    /// Single-line fields: vertically center the text within the field's height so it
    /// matches the read-mode `DSText` (which SwiftUI centers in the same frame) — no
    /// vertical jump between read and edit. Leave false for multiline (top-anchored). [#41]
    var verticallyCentered: Bool = false

    func makeUIView(context: Context) -> VCenterTextView {
        let tv = VCenterTextView()
        tv.verticallyCenter = verticallyCentered
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
            // Centered single-line fields pin the placeholder to centerY so it tracks
            // the centered text; multiline/top fields pin it to the top.
            verticallyCentered
                ? ph.centerYAnchor.constraint(equalTo: tv.centerYAnchor)
                : ph.topAnchor.constraint(equalTo: tv.topAnchor),
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

    func updateUIView(_ uiView: VCenterTextView, context: Context) {
        context.coordinator.parent = self   // keep the latest binding/text
        uiView.verticallyCenter = verticallyCentered
        uiView.font = appUIFont(fontSize)
        context.coordinator.placeholderLabel?.font = appUIFont(fontSize)
        context.coordinator.placeholderLabel?.text = placeholder
        if uiView.text != text { uiView.text = text }
        context.coordinator.placeholderLabel?.isHidden = !uiView.text.isEmpty
    }

    /// Constrain to the proposed width so the text wraps and the field reports
    /// a correct height (otherwise UITextView lays out as one giant line).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: VCenterTextView, context: Context) -> CGSize? {
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

/// UITextView that can vertically center its (single-line) text within its bounds by
/// padding the top inset — used so an editable title sits at the same vertical center
/// as the read-mode `DSText`, which SwiftUI centers in the same frame.
final class VCenterTextView: UITextView {
    var verticallyCenter = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard verticallyCenter else { return }
        let used = layoutManager.usedRect(for: textContainer).height
        let top = max(0, (bounds.height - used) / 2)
        if abs(textContainerInset.top - top) > 0.5 {
            textContainerInset = UIEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        }
    }
}
