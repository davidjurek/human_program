import SwiftUI
import SwiftData
import DSKit
import UIKit

@main
struct HumanProgramApp: App {
    @State private var appState = AppState()
    @AppStorage(DefaultsKey.fontChoice) private var fontChoiceRaw = FontChoice.default.rawValue
    @AppStorage(DefaultsKey.fontSizeStep) private var fontSizeStep = FontSizeStep.defaultIndex
    @AppStorage(DefaultsKey.appearanceMode) private var appearanceModeRaw = AppearanceMode.system.rawValue
    private let container: ModelContainer

    init() {
        // Unify text selection app-wide: every caret + selection highlight uses the app
        // lavender, instead of a per-field system default that could render invisibly
        // (and hide the copy/paste menu with it). SwiftUI TextField is UITextField-backed
        // and AppTextField is a UITextView, so these two proxies cover the whole app. [owner]
        let selection = UIColor(appSelectionLavender)
        UITextField.appearance().tintColor = selection
        UITextView.appearance().tintColor = selection

        do {
            container = try makeModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .dsAppearance(AppTheme.appearance(for: FontChoice.from(fontChoiceRaw), sizeStep: fontSizeStep))
                .preferredColorScheme(AppearanceMode.from(appearanceModeRaw).colorScheme)
                .onAppear { KeyboardDismisser.installIfNeeded() }
        }
        .modelContainer(container)
    }
}
