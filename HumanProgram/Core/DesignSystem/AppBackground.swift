import SwiftUI

/// A selectable app background. Light mode uses the chosen light background;
/// dark mode always uses a plain dark background. For now only the first slot
/// of each set is defined — the other 5 are placeholders to fill in later.
enum AppBackground: String, Equatable {
    case gradient    // light slot 0
    case plainDark   // dark slot 0

    /// The 6 light-mode slots (only the first is populated).
    static let lightOptions: [AppBackground?] = [.gradient, nil, nil, nil, nil, nil]
    /// The 6 dark-mode slots (only the first is populated).
    static let darkOptions: [AppBackground?] = [.plainDark, nil, nil, nil, nil, nil]

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
        case .plainDark:
            Color(red: 0.07, green: 0.07, blue: 0.08)
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
