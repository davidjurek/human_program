import SwiftUI
import UIKit

/// On-brand swatch palette for schedule blocks + default-by-name assignment. [#20/#13]
enum BlockColors {
    /// Preset swatches shown in the picker (the "custom" option adds any colour).
    static let swatches: [String] = [
        "5B6CF0", // indigo
        "4F9DF7", // blue
        "3FB6A8", // teal
        "5FBF6A", // green
        "E8B84B", // amber
        "EE8A4E", // orange
        "E86A8C", // rose
        "A56EE0", // violet
        "8A94A6", // slate
        "C2B59B", // taupe
    ]

    /// Default colour for a block from its title (keyword match), falling back to
    /// a stable palette pick derived from the title. [#13]
    static func defaultHex(forTitle title: String) -> String {
        let t = title.lowercased()
        if t.contains("sleep") { return "5B6CF0" }                                   // indigo
        if t.contains("work")  { return "4F9DF7" }                                   // blue
        if t.contains("exercise") || t.contains("workout") || t.contains("gym")
            || t.contains("run") { return "5FBF6A" }                                 // green
        if t.contains("eat") || t.contains("dinner") || t.contains("lunch")
            || t.contains("breakfast") || t.contains("meal") { return "EE8A4E" }     // orange
        if t.contains("read") || t.contains("study") { return "A56EE0" }             // violet
        if t.contains("relax") || t.contains("fool") || t.contains("break") { return "3FB6A8" } // teal
        // Stable fallback (deterministic across launches, unlike hashValue).
        let fold = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return swatches[fold % swatches.count]
    }

    /// Resolved colour for a block: its assigned hex, or the default-by-name.
    static func color(hex: String?, title: String) -> Color {
        Color(hex: hex ?? defaultHex(forTitle: title)) ?? .gray
    }
}

extension Color {
    /// 6-digit "RRGGBB" hex for this colour (for persisting a picked colour).
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// "RRGGBB" / "#RRGGBB" → Color. Returns nil for nil/malformed input.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
