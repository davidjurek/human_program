import SwiftUI
import DSKit

/// Single source of truth for the app's DSKit appearance.
///
/// The whole app is being migrated to DSKit for its UI. Reference
/// `AppTheme.appearance` everywhere an appearance or its resolved colors are
/// needed (root `.dsAppearance(...)`, `NavigationView` accent colors, etc.)
/// so the theme can be swapped in exactly one place.
enum AppTheme {
    /// The active DSKit appearance. Light, blue-accented to match the app's
    /// existing look. Swap this single value to re-theme the entire app.
    static let appearance: DSAppearance = LightBlueAppearance()
}
