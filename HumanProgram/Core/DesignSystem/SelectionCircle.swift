import SwiftUI

/// The ONE shared selection / completion circle used everywhere a check appears
/// — Today's task checks, Import & CSV row selection, Backlog project select, etc.
/// Light-blue fill (the weekday-pill blue) with a white check when on; a hollow
/// ring when off. One size, one color, defined in a single place so every check
/// in the app stays consistent (per the reuse rule).
struct SelectionCircle: View {
    let isOn: Bool
    /// Slightly larger than the old 20pt glyphs.
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(weekdaySelectedColor)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1.6)
            }
        }
        .frame(width: size, height: size)
    }
}
