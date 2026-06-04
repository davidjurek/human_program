import SwiftUI

// A normal-looking body paragraph that hides a secret unlock: double-tapping two
// specific words, in order, within it fires `onUnlock`. Used on the Privacy Policy
// reference screen to open the private acceptance log. The trigger words look
// identical to the surrounding text (no highlight) so the paragraph reads normally.
//
// The text is laid out word-by-word in a wrapping FlowLayout so individual words
// can carry their own double-tap gesture (a single SwiftUI Text can't). Only the
// two trigger words carry a gesture; every other word is inert.
struct SecretTapParagraph: View {
    /// Full paragraph text. "\n\n" splits visual paragraphs.
    let text: String
    /// The two trigger words, in the order they must be double-tapped. Matched
    /// case-insensitively with surrounding punctuation ignored. Choose words that
    /// each appear once, in the same visual paragraph.
    let triggers: [String]
    let onUnlock: () -> Void

    /// How many triggers have been matched in order so far.
    @State private var progress = 0

    private var paragraphs: [String] { text.components(separatedBy: "\n\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(paragraphs.indices, id: \.self) { pi in
                paragraphView(paragraphs[pi])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraphView(_ p: String) -> some View {
        let words = p.split(separator: " ").map(String.init)
        return FlowLayout(spacing: 5, lineSpacing: 7) {
            ForEach(words.indices, id: \.self) { wi in
                wordToken(words[wi])
            }
        }
    }

    @ViewBuilder
    private func wordToken(_ word: String) -> some View {
        let norm = Self.normalize(word)
        let isTrigger = triggers.contains { Self.normalize($0) == norm }
        let base = Text(word)
            .font(appFont(17))
            .foregroundStyle(.primary)
        if isTrigger {
            base
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleTriggerTap(norm) }
        } else {
            base
        }
    }

    private func handleTriggerTap(_ norm: String) {
        let normTriggers = triggers.map(Self.normalize)
        guard progress < normTriggers.count else { progress = 0; return }
        if norm == normTriggers[progress] {
            progress += 1
            if progress >= normTriggers.count {
                progress = 0
                onUnlock()
            }
        } else if norm == normTriggers.first {
            // Tapped the first trigger again — restart the sequence at step 1.
            progress = 1
        } else {
            progress = 0
        }
    }

    /// Lowercased, stripped of any non-alphanumeric characters (so "transmit," and
    /// "transmit" match).
    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// A simple line-wrapping layout (like flowing text). Places each subview left to
// right, wrapping to the next line when the next subview would overflow the width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                // wrap
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        let totalHeight = y + lineHeight
        let width = (proposal.width != nil) ? maxWidth : maxLineWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
