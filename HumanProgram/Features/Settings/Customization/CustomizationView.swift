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
    @AppStorage("settings.bgLight") private var lightIndex: Int = 0
    @AppStorage("settings.bgDark") private var darkIndex: Int = 0

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Light Mode") {
                BackgroundSwatchGrid(options: AppBackground.lightOptions, selected: $lightIndex)
            }
            SettingsGroup(title: "Dark Mode") {
                BackgroundSwatchGrid(options: AppBackground.darkOptions, selected: $darkIndex)
            }
        }
    }
}

/// A 3×2 grid of background swatches. Filled options are selectable; empty
/// placeholder slots are shown but disabled (to be filled in later).
private struct BackgroundSwatchGrid: View {
    let options: [AppBackground?]
    @Binding var selected: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(options.indices, id: \.self) { index in
                BackgroundSwatch(
                    background: options[index],
                    isSelected: selected == index,
                    action: { if options[index] != nil { selected = index } }
                )
            }
        }
    }
}

private struct BackgroundSwatch: View {
    let background: AppBackground?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let background {
                    background.view
                } else {
                    // Filled neutral placeholder slot (not selectable yet).
                    Color.primary.opacity(0.08)
                }
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.gray.opacity(isSelected ? 0.9 : 0.0), lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .disabled(background == nil)
    }
}

// MARK: - Font (size + type)

struct FontSettingsView: View {
    @AppStorage("settings.fontChoice") private var fontChoice: String = FontChoice.default.rawValue
    @AppStorage("settings.fontSizeStep") private var sizeStep: Int = FontSizeStep.defaultIndex

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Font") {
                ForEach(FontChoice.allCases) { choice in
                    FontOptionRow(choice: choice, isSelected: fontChoice == choice.rawValue) {
                        fontChoice = choice.rawValue
                    }
                }
            }
            SettingsGroup(title: "Font Size") {
                // Cancel the screen's asymmetric leading inset (44 vs 20) so the
                // slider sits centered in the screen.
                FontSizeSlider(step: $sizeStep)
                    .padding(.leading, -24)
            }
        }
    }
}

/// iOS text-size-style slider: small A … large A, a track with a tick dot at
/// each of the 6 steps, and a pill thumb that snaps to steps. Sizes are fixed
/// (not app-font driven) so the control doesn't move when the font changes.
private struct FontSizeSlider: View {
    @Binding var step: Int
    private let count = FontSizeStep.count

    var body: some View {
        HStack(spacing: 14) {
            Text("A").font(.system(size: 15)).foregroundStyle(.secondary)
            track
            Text("A").font(.system(size: 27)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let xs = (0..<count).map { CGFloat($0) / CGFloat(count - 1) * (w - 30) + 15 }
            let thumbX = xs[min(max(step, 0), count - 1)]
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.25)).frame(height: 4)
                Capsule().fill(Color.primary.opacity(0.6)).frame(width: thumbX, height: 4)
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(Color.primary.opacity(0.35))
                        .frame(width: 4, height: 4)
                        .offset(x: xs[i] - 2, y: 11)
                }
                Capsule().fill(Color.white)
                    .frame(width: 30, height: 26)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(x: thumbX - 15)
            }
            .frame(height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let clamped = max(15, min(w - 15, value.location.x))
                    let idx = Int(((clamped - 15) / (w - 30) * CGFloat(count - 1)).rounded())
                    if idx != step { step = idx }
                }
            )
        }
        .frame(height: 30)
    }
}

/// A font-choice row that previews each font in its own typeface. Fixed height
/// so switching fonts (which have different metrics) doesn't shift the layout.
private struct FontOptionRow: View {
    let choice: FontChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(choice.label)
                    .font(choice.previewFont(size: 20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                if isSelected {
                    DSImageView(systemName: "checkmark", size: .font(.body), tint: .color(.primary))
                }
            }
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    /// nil = follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    static func from(_ raw: String) -> AppearanceMode { AppearanceMode(rawValue: raw) ?? .system }
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
