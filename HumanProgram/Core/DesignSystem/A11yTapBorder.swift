import SwiftUI

/// Accessibility option: when `settings.a11yButtonBorders` is on, every tappable
/// BUTTON in the app draws a 1pt border at its real tappable edges — dark grey in
/// light mode, white in dark mode — so tap targets are easy to locate. Gesture
/// surfaces (drag/hold/swipe rows, the padlock) deliberately do NOT get a border.
///
/// This is the one shared place the border is defined; tappable views apply it
/// with `.a11yTapBorder(...)`, matching the shape of their hit area so the line
/// sits exactly on the tappable edge (`strokeBorder` insets the line inward).
let a11yButtonBordersKey = "settings.a11yButtonBorders"

private struct A11yTapBorderModifier<S: InsettableShape>: ViewModifier {
    @AppStorage(a11yButtonBordersKey) private var enabled = false
    @Environment(\.colorScheme) private var scheme
    let shape: S
    let lineWidth: CGFloat

    private var color: Color { scheme == .dark ? .white : Color(white: 0.35) }

    func body(content: Content) -> some View {
        content.overlay {
            if enabled {
                shape.strokeBorder(color, lineWidth: lineWidth)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Border the tappable edge using an explicit shape (match the button's hit area).
    func a11yTapBorder<S: InsettableShape>(_ shape: S, lineWidth: CGFloat = 1) -> some View {
        modifier(A11yTapBorderModifier(shape: shape, lineWidth: lineWidth))
    }

    /// Border the tappable edge as a rounded rectangle (default for most buttons).
    func a11yTapBorder(cornerRadius: CGFloat = 6, lineWidth: CGFloat = 1) -> some View {
        modifier(A11yTapBorderModifier(shape: RoundedRectangle(cornerRadius: cornerRadius),
                                       lineWidth: lineWidth))
    }
}
