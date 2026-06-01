import SwiftUI
import DSKit

/// Accessibility options. The "Button borders" toggle outlines every tappable
/// button in the app at its real tap edges (dark grey in light mode, white in
/// dark mode) so controls are easy to locate. See `A11yTapBorder.swift`.
struct AccessibilitySettingsView: View {
    @AppStorage(a11yButtonBordersKey) private var buttonBorders = false

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Display") {
                SettingsToggleRow(label: "Button Borders",
                                  systemImage: "square.dashed",
                                  isOn: $buttonBorders)
            }
        }
    }
}
