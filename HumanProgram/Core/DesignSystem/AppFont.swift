import SwiftUI
import DSKit
import CoreText
#if canImport(UIKit)
import UIKit
#endif

// Variable-font axis identifiers.
private let AXIS_WGHT = 2003265652  // 'wght'
private let AXIS_SLNT = 1936486004  // 'slnt'
private let AXIS_CRSV = 1129468758  // 'CRSV'

/// Describes one concrete font: a base PostScript name, optional variable-font
/// axis overrides, and a per-font size multiplier (to visually match others).
struct FontSpec {
    let psName: String
    var variations: [Int: Double] = [:]
    var sizeMultiplier: CGFloat = 1.0

    func uiFont(_ size: CGFloat) -> UIFont {
        var attrs: [UIFontDescriptor.AttributeName: Any] = [.name: psName]
        if !variations.isEmpty {
            attrs[UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)] = variations
        }
        let descriptor = UIFontDescriptor(fontAttributes: attrs)
        return UIFont(descriptor: descriptor, size: size * sizeMultiplier)
    }
}

/// A DSKit fonts implementation backed by a custom font (regular + bold specs),
/// scaled by the global font-size step. Scales with Dynamic Type too.
final class AppFontTypography: DSFontsProtocol {
    private let regular: FontSpec
    private let bold: FontSpec
    private let scale: CGFloat

    init(regular: FontSpec, bold: FontSpec, scale: CGFloat) {
        self.regular = regular
        self.bold = bold
        self.scale = scale
    }

    var body: DSFont { reg(17) }
    var callout: DSFont { reg(16) }
    var caption1: DSFont { reg(12) }
    var caption2: DSFont { reg(11) }
    var footnote: DSFont { reg(13) }
    var headline: DSFont { bld(17) }
    var subheadline: DSFont { reg(15) }
    var largeTitle: DSFont { reg(34) }
    var title1: DSFont { reg(28) }
    var title2: DSFont { reg(22) }
    var title3: DSFont { reg(20) }

    private func reg(_ size: CGFloat) -> DSFont { make(regular, size) }
    private func bld(_ size: CGFloat) -> DSFont { make(bold, size) }

    private func make(_ spec: FontSpec, _ size: CGFloat) -> DSFont {
        let base = spec.uiFont(size * scale)
        #if canImport(UIKit)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        #else
        return base
        #endif
    }
}

/// The user-selectable app font. Cardo is the default.
enum FontChoice: String, CaseIterable, Identifiable {
    case cardo, libertinus, martelSans, lilex, bitcount

    static let `default`: FontChoice = .cardo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cardo:      return "Cardo"
        case .libertinus: return "Libertinus Serif"
        case .martelSans: return "Martel Sans"
        case .lilex:      return "Lilex"
        case .bitcount:   return "Bitcount Grid Single"
        }
    }

    var regularSpec: FontSpec {
        switch self {
        case .cardo:      return FontSpec(psName: "Cardo-Regular")
        case .libertinus: return FontSpec(psName: "LibertinusSerif-Regular")
        case .martelSans: return FontSpec(psName: "MartelSans-Regular")
        case .lilex:      return FontSpec(psName: "Lilex-Thin", variations: [AXIS_WGHT: 700])
        case .bitcount:   return FontSpec(psName: "BitcountGridSingle-Regular_Thin-Italic",
                                          variations: [AXIS_WGHT: 344, AXIS_SLNT: 0, AXIS_CRSV: 0],
                                          sizeMultiplier: 1.18)
        }
    }

    var boldSpec: FontSpec {
        switch self {
        case .cardo:      return FontSpec(psName: "Cardo-Bold")
        case .libertinus: return FontSpec(psName: "LibertinusSerif-Bold")
        case .martelSans: return FontSpec(psName: "MartelSans-Bold")
        case .lilex:      return FontSpec(psName: "Lilex-Thin", variations: [AXIS_WGHT: 700])
        case .bitcount:   return FontSpec(psName: "BitcountGridSingle-Regular_Thin-Italic",
                                          variations: [AXIS_WGHT: 344, AXIS_SLNT: 0, AXIS_CRSV: 0],
                                          sizeMultiplier: 1.18)
        }
    }

    func fonts(scale: CGFloat) -> DSFontsProtocol {
        AppFontTypography(regular: regularSpec, bold: boldSpec, scale: scale)
    }

    /// SwiftUI Font for previewing this choice in its own typeface in the picker.
    func previewFont(size: CGFloat) -> Font {
        Font(regularSpec.uiFont(size))
    }

    static func from(_ raw: String) -> FontChoice {
        FontChoice(rawValue: raw) ?? .default
    }
}

extension FontChoice {
    /// This choice as a SwiftUI Font at an explicit size (for plain Text/TextField).
    func font(size: CGFloat, bold: Bool = false) -> Font {
        Font((bold ? boldSpec : regularSpec).uiFont(size))
    }
}

/// The currently-selected app font as a SwiftUI Font. Reads the persisted choice
/// so plain SwiftUI Text/TextField (which can't use DSText) still match the app font.
/// Re-reads on each render, so it updates when the font changes.
func appFont(_ size: CGFloat, bold: Bool = false) -> Font {
    let raw = UserDefaults.standard.string(forKey: "settings.fontChoice") ?? FontChoice.default.rawValue
    return FontChoice.from(raw).font(size: size, bold: bold)
}

/// The on-screen point size for a DSKit text-style base size at the current
/// global font scale. Use this so a plain `Text`/`TextField`/`AppTextField` that
/// must line up with a `DSText(...).dsTextStyle(...)` matches its size (DSKit text
/// styles apply the global FontSizeStep scale; `appFont`/`appUIFont` do not).
/// e.g. `.title2` → `appScaledSize(22)`, `.title3` → `appScaledSize(20)`.
func appScaledSize(_ base: CGFloat) -> CGFloat {
    let step = UserDefaults.standard.object(forKey: "settings.fontSizeStep") as? Int ?? FontSizeStep.defaultIndex
    return base * FontSizeStep.scale(for: step)
}

/// The currently-selected app font as a UIFont (for UIKit-backed views).
func appUIFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
    let raw = UserDefaults.standard.string(forKey: "settings.fontChoice") ?? FontChoice.default.rawValue
    let choice = FontChoice.from(raw)
    return (bold ? choice.boldSpec : choice.regularSpec).uiFont(size)
}

/// Soft-green toggle "on" color (#CDEBC5), used app-wide.
let appToggleTint = Color(red: 205.0/255, green: 235.0/255, blue: 197.0/255)

/// Selected weekday circle color (#A3D5FF).
let weekdaySelectedColor = Color(red: 163.0/255, green: 213.0/255, blue: 255.0/255)

/// Six fixed font-size steps for the size slider. Index 0…5; the value is a
/// global scale multiplier applied to all typography.
enum FontSizeStep {
    static let count = 6
    static let defaultIndex = 2
    static let scales: [CGFloat] = [0.85, 0.92, 1.0, 1.10, 1.20, 1.32]

    static func scale(for index: Int) -> CGFloat {
        scales[min(max(index, 0), count - 1)]
    }
}
