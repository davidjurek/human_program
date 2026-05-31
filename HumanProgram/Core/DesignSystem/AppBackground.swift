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
            // Serene soft-aurora: mint / sage / butter / blue blobs over a base. [#56/#19]
            ZStack {
                Color(red: 0.88, green: 0.94, blue: 0.91)
                RadialGradient(colors: [Color(red: 0.66, green: 0.88, blue: 0.82).opacity(0.85), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 380)
                RadialGradient(colors: [Color(red: 0.99, green: 0.95, blue: 0.78).opacity(0.80), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 440)
                RadialGradient(colors: [Color(red: 0.78, green: 0.89, blue: 0.97).opacity(0.65), .clear],
                               center: .init(x: 0.15, y: 0.85), startRadius: 0, endRadius: 320)
            }
        case .gradientRose:
            // Peaceful soft-aurora: rose / lilac / periwinkle blobs over a base. [#56/#19]
            ZStack {
                Color(red: 0.96, green: 0.91, blue: 0.94)
                RadialGradient(colors: [Color(red: 0.99, green: 0.80, blue: 0.87).opacity(0.85), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 380)
                RadialGradient(colors: [Color(red: 0.83, green: 0.80, blue: 0.97).opacity(0.80), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 440)
                RadialGradient(colors: [Color(red: 0.78, green: 0.88, blue: 0.98).opacity(0.60), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 320)
            }
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
