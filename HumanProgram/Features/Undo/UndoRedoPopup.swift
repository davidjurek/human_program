import SwiftUI
import DSKit

// The shake popup. DSKit-conformant (DSText / DSImageView / shared popupGlass),
// fixed size and fixed centred position so it never shifts with its contents. It
// lists the action each side would act on, and offers the two options Undo / Redo;
// whichever side has nothing to do is greyed out and disabled. It stays open after
// an Undo/Redo (the labels update live), so the user can chain. It closes ONLY via
// the Close button — outside taps are absorbed (modal), never dismiss.
struct UndoRedoPopup: View {
    var store = UndoStore.shared
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onDismiss: () -> Void

    private enum Side {
        case undo, redo
        var word: String { self == .undo ? "Undo" : "Redo" }
        var icon: String { self == .undo ? "arrow.uturn.backward" : "arrow.uturn.forward" }
        var empty: String { self == .undo ? "Nothing to undo" : "Nothing to redo" }
    }

    var body: some View {
        ZStack {
            // Full-screen catcher ABSORBS taps (modal) but never dismisses — the popup
            // closes only via its Close button.
            Color.clear.contentShape(Rectangle()).onTapGesture {}

            VStack(spacing: 0) {
                row(side: .undo, enabled: store.canUndo, action: store.undoDescription, perform: onUndo)
                separator
                row(side: .redo, enabled: store.canRedo, action: store.redoDescription, perform: onRedo)
                separator
                closeRow
            }
            .frame(width: 300)                 // fixed width → no horizontal shift
            .popupGlass(cornerRadius: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var separator: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
    }

    /// Fixed-size Close row, mirroring the Undo/Redo rows' metrics so adding it
    /// doesn't shift their size or position. The only way to dismiss the popup.
    private var closeRow: some View {
        Button {
            Haptics.impact(.light)
            onDismiss()
        } label: {
            HStack(spacing: 14) {
                DSImageView(systemName: "xmark", size: 20, tint: .color(Color.primary))
                    .frame(width: 24)
                DSText("Close").dsTextStyle(.headline, Color.primary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .frame(height: 72)                  // same fixed height as the rows
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(cornerRadius: 6)
    }

    /// One option row: the word (Undo/Redo) over the specific action it will act on.
    /// The action label wraps to TWO lines before truncating, and the label area
    /// ALWAYS reserves two lines (the invisible sizer) so a one-line and a two-line
    /// label produce the exact same row geometry — both rows stay identical in size,
    /// shape and position regardless of their text.
    private func row(side: Side, enabled: Bool, action: String?, perform: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            Haptics.impact(.light)
            perform()
        } label: {
            HStack(spacing: 14) {
                DSImageView(systemName: side.icon, size: 20,
                            tint: .color(enabled ? Color.primary : Color.secondary))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    DSText(side.word).dsTextStyle(.headline, enabled ? Color.primary : Color.secondary)
                    ZStack(alignment: .topLeading) {
                        // Invisible two-line sizer reserves a constant height (auto-scales
                        // with the app font), so short and long labels look identical.
                        DSText("X\nX").dsTextStyle(.subheadline, Color.clear).lineLimit(2)
                        DSText(enabled ? (action ?? "") : side.empty)
                            .dsTextStyle(.subheadline, Color.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(cornerRadius: 6)
        .disabled(!enabled)
    }
}
