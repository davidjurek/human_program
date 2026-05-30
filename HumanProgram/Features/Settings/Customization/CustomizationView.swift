import SwiftUI
import DSKit

// Customization area. STRUCTURE + SCREENS first — the controls below persist
// their selections (@AppStorage) but are not yet applied app-wide. Wiring them
// into the live appearance/typography is a follow-up.

struct CustomizationView: View {
    var body: some View {
        SettingsScreen {
            SettingsGroup {
                SettingsNavRow(label: "Background", systemImage: "paintpalette") { BackgroundSettingsView() }
                SettingsNavRow(label: "Font", systemImage: "textformat.size") { FontSettingsView() }
                SettingsNavRow(label: "Appearance", systemImage: "circle.lefthalf.filled") { AppearanceSettingsView() }
            }
        }
    }
}

// MARK: - Background (color + hue)

struct BackgroundSettingsView: View {
    @State private var color: Color = Color(red: 0.80, green: 0.79, blue: 0.96)
    @State private var hue: Double = 0.5

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Background Color") {
                ColorPicker(selection: $color, supportsOpacity: false) {
                    DSText("Color").dsTextStyle(.title3)
                }
            }
            SettingsGroup(title: "Hue") {
                Slider(value: $hue, in: 0...1)
            }
        }
    }
}

// MARK: - Font (size + type)

struct FontSettingsView: View {
    @AppStorage("settings.fontSize") private var fontSize: Double = 17
    @AppStorage("settings.fontType") private var fontType: String = "System"

    private let types = ["System", "Rounded", "Serif", "Monospaced"]

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Font Size") {
                Slider(value: $fontSize, in: 12...24, step: 1)
                DSText("\(Int(fontSize)) pt").dsTextStyle(.subheadline)
            }
            SettingsGroup(title: "Font Type") {
                ForEach(types, id: \.self) { type in
                    SettingsSelectRow(label: type, isSelected: fontType == type) {
                        fontType = type
                    }
                }
            }
        }
    }
}

// MARK: - Appearance (dark mode)

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Always Light"
        case .dark: return "Always Dark"
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("settings.appearanceMode") private var mode: String = AppearanceMode.system.rawValue

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Appearance") {
                ForEach(AppearanceMode.allCases) { option in
                    SettingsSelectRow(label: option.label, isSelected: mode == option.rawValue) {
                        mode = option.rawValue
                    }
                }
            }
        }
    }
}
