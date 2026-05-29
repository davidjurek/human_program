import SwiftUI

// Design tokens. Custom palette — NOT stock iOS.
// Asset-catalog named colors support both light and dark mode.
public enum AppColors {

    // MARK: - Backgrounds (asset-catalog named colors)

    /// Primary app background.
    public static let background        = Color("Background")
    /// Slightly elevated surface for cards and sheets.
    public static let surfaceElevated   = Color("SurfaceElevated")
    /// Inset / sunken surface.
    public static let surfaceSunken     = Color("SurfaceSunken")
    /// Alias used throughout the app for card/row backgrounds.
    public static let surface           = surfaceElevated

    // MARK: - Content

    public static let textPrimary       = Color("TextPrimary")
    public static let textSecondary     = Color("TextSecondary")
    public static let textTertiary      = Color("TextTertiary")
    /// Disabled text — further faded tertiary.
    public static let textDisabled      = Color("TextTertiary").opacity(0.5)

    // MARK: - Accents

    /// Blue — primary actions and tint.
    public static let accent            = Color("Accent")
    /// Accent dim — pressed / secondary variant.
    public static let accentDim         = Color("Accent").opacity(0.7)
    /// Green — completion / success.
    public static let accentGreen       = Color("AccentGreen")
    /// Red — destructive actions.
    public static let accentRed         = Color("AccentRed")
    /// Orange — schedule / time blocks / lock state.
    public static let accentOrange      = Color("AccentOrange")

    // MARK: - Task States

    /// Background tint for a completed task row.
    public static let taskComplete      = Color("AccentGreen").opacity(0.10)
    public static let taskPending       = Color.clear

    // MARK: - Semantic Aliases

    public static let success           = Color("AccentGreen")
    public static let successTint       = Color("AccentGreen").opacity(0.12)
    public static let warning           = Color("AccentOrange")
    public static let warningTint       = Color("AccentOrange").opacity(0.10)
    public static let destructive       = Color("AccentRed")

    // MARK: - Separators & Borders

    /// Subtle separator line.
    public static let separator         = Color.primary.opacity(0.08)
    /// Border for interactive elements.
    public static let border            = Color.primary.opacity(0.13)
    /// Checkbox / circle stroke when unchecked.
    public static let checkboxBorder    = Color.primary.opacity(0.25)
    /// Filled background of a checked checkbox.
    public static let checkboxFilled    = Color("Accent")
    /// Checkmark icon color inside filled checkbox.
    public static let checkboxCheck     = Color.white

    // MARK: - Section Headers

    /// Section header label color.
    public static let sectionHeader     = Color("TextSecondary")

    // MARK: - Lock / Past State

    /// Past-locked banner background — warm tint using accentOrange.
    public static let lockBanner        = Color("AccentOrange").opacity(0.08)
    /// Past-locked banner text / icon color.
    public static let lockText          = Color("AccentOrange")
}
