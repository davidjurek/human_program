import SwiftUI

/// A selectable app background. Light mode uses the chosen light background;
/// dark mode always uses a plain dark background. For now only the first slot
/// of each set is defined — the other 5 are placeholders to fill in later.
enum AppBackground: String, Equatable {
    case gradient        // light slot 0
    case gradientMint    // light slot 1 [#56]
    case gradientRose    // light slot 2 [#56]
    case plainDark       // dark slot 0
    case darkGrey1       // dark slot 1 [#56]
    case darkGrey2       // dark slot 2 [#56]

    /// The 6 light-mode slots.
    static let lightOptions: [AppBackground?] = [.gradient, .gradientMint, .gradientRose, nil, nil, nil]
    /// The 6 dark-mode slots.
    static let darkOptions: [AppBackground?] = [.plainDark, .darkGrey1, .darkGrey2, nil, nil, nil]

    @ViewBuilder
    var view: some View {
        switch self {
        case .gradient:
            LinearGradient(
                colors: [
                    Color(red: 0.80, green: 0.79, blue: 0.96),  // lavender
                    Color(red: 0.86, green: 0.90, blue: 0.99),  // soft blue
                    Color(red: 0.99, green: 0.85, blue: 0.78)   // peach
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gradientMint:
            // Serene mint → sage → pale butter. [#56]
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.92, blue: 0.88),
                    Color(red: 0.86, green: 0.93, blue: 0.83),
                    Color(red: 0.99, green: 0.97, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gradientRose:
            // Peaceful rose → lilac → periwinkle. [#56]
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.86, blue: 0.90),
                    Color(red: 0.88, green: 0.85, blue: 0.96),
                    Color(red: 0.83, green: 0.90, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .plainDark:
            Color(red: 0.07, green: 0.07, blue: 0.08)
        case .darkGrey1:
            Color(red: 0.13, green: 0.13, blue: 0.14)   // [#56] dark grey
        case .darkGrey2:
            Color(red: 0.18, green: 0.18, blue: 0.20)   // [#56] lighter dark grey
        }
    }

    static func resolved(light lightIndex: Int, dark darkIndex: Int, scheme: ColorScheme) -> AppBackground {
        if scheme == .dark {
            return darkOptions[safe: darkIndex].flatMap { $0 } ?? .plainDark
        } else {
            return lightOptions[safe: lightIndex].flatMap { $0 } ?? .gradient
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
