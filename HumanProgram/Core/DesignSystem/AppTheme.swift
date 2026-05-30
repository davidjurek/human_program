import SwiftUI
import DSKit

/// Single source of truth for the app's DSKit appearance.
///
/// The whole app's UI is on DSKit. Reference `AppTheme` everywhere an
/// appearance is needed so the theme can be swapped in exactly one place.
enum AppTheme {
    /// Build the active appearance, applying the user's selected font + size step.
    /// Light, blue-accented base; the chosen font overrides typography app-wide.
    static func appearance(for font: FontChoice = .default,
                           sizeStep: Int = FontSizeStep.defaultIndex) -> DSAppearance {
        var appearance = LightBlueAppearance()
        appearance.fonts = font.fonts(scale: FontSizeStep.scale(for: sizeStep))
        return appearance
    }

    /// Default appearance, for any non-reactive call site.
    static var appearance: DSAppearance { appearance() }
}
