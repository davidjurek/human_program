import SwiftUI
import UIKit

/// Header-less text field backed by UITextView so we can control the caret:
/// tapping anywhere places the cursor at the END (no word-select). Grey
/// placeholder is the label. Uses the chosen app font; grows when multiline.
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

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)

        context.coordinator.textView = tv
        context.coordinator.refreshPlaceholder()
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self   // keep the latest binding/text
        uiView.font = appUIFont(fontSize)
        if !uiView.isFirstResponder {
            context.coordinator.refreshPlaceholder()
        }
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
        weak var textView: UITextView?
        private var showingPlaceholder = false

        init(_ parent: AppTextField) { self.parent = parent }

        @objc func handleTap() {
            guard let tv = textView else { return }
            if !tv.isFirstResponder { tv.becomeFirstResponder() }
            moveCaretToEnd(tv)
        }

        private func moveCaretToEnd(_ tv: UITextView) {
            DispatchQueue.main.async {
                let end = tv.endOfDocument
                tv.selectedTextRange = tv.textRange(from: end, to: end)
            }
        }

        func refreshPlaceholder() {
            guard let tv = textView, !tv.isFirstResponder else { return }
            if parent.text.isEmpty {
                tv.text = parent.placeholder
                tv.textColor = .placeholderText
                showingPlaceholder = true
            } else {
                tv.text = parent.text
                tv.textColor = .label
                showingPlaceholder = false
            }
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if showingPlaceholder {
                tv.text = ""
                tv.textColor = .label
                showingPlaceholder = false
            }
            moveCaretToEnd(tv)
        }

        func textViewDidChange(_ tv: UITextView) {
            if !showingPlaceholder { parent.text = tv.text }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            refreshPlaceholder()
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
