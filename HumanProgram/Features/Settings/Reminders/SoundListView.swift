import SwiftUI

/// Sound picker for a reminder. For now lists a single option (the iOS default
/// notification sound). More sounds/chimes will be added later.
struct SoundListView: View {
    @Binding var selection: NotificationSoundMode

    var body: some View {
        SettingsScreen {
            SettingsGroup(title: "Sound") {
                SettingsSelectRow(label: "Default", isSelected: selection == .defaultSound) {
                    selection = .defaultSound
                }
            }
        }
    }
}
