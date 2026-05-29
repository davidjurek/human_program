import SwiftUI

// Centralized font styles for Human Program.
// All fonts are exposed both as static functions (primary API) and as
// static computed properties (convenience aliases) for ergonomic use in views.
public enum AppTypography {

    // MARK: - Primary API (function form — called as AppTypography.taskTitle())

    public static func pageTitle() -> Font         { .system(size: 22, weight: .semibold) }
    public static func sectionHeader() -> Font     { .system(size: 11, weight: .semibold) }
    public static func taskTitle() -> Font         { .system(size: 16, weight: .regular) }
    public static func taskMeta() -> Font          { .system(size: 12, weight: .regular) }
    public static func timeLabel() -> Font         { .system(size: 11, weight: .regular).monospacedDigit() }
    public static func completionMessage() -> Font { .system(size: 15, weight: .medium) }
    public static func caption() -> Font           { .system(size: 12) }
    public static func dateLabel() -> Font         { .system(size: 17, weight: .semibold) }
    public static func buttonLabel() -> Font       { .system(size: 13, weight: .medium) }
    public static func bodyText() -> Font          { .system(size: 16, weight: .regular) }
    public static func bodyMediumText() -> Font    { .system(size: 16, weight: .medium) }
    public static func bodySmallText() -> Font     { .system(size: 14, weight: .regular) }
    public static func monoText() -> Font          { .system(size: 14, weight: .regular, design: .monospaced) }

    // MARK: - Convenience static property aliases
    // These allow `AppTypography.body` style access in views that prefer property syntax.

    /// Primary body text — 16pt regular.
    public static var body: Font          { bodyText() }
    /// Body with medium weight.
    public static var bodyMedium: Font    { bodyMediumText() }
    /// Slightly smaller body — 14pt regular.
    public static var bodySmall: Font     { bodySmallText() }
    /// Small body with medium weight — 14pt medium.
    public static var bodySmallMedium: Font { .system(size: 14, weight: .medium) }
    /// Small action button labels.
    public static var buttonSmall: Font   { buttonLabel() }
    /// Navigation / date label.
    public static var dateHeader: Font    { dateLabel() }
    /// Navigation arrow size.
    public static var navButton: Font     { .system(size: 18, weight: .regular) }
    /// Monospaced for time/number display.
    public static var mono: Font          { monoText() }
    /// Caption / metadata.
    public static var captionStyle: Font  { caption() }
    /// Caption with medium weight.
    public static var captionMedium: Font { .system(size: 12, weight: .medium) }
}
