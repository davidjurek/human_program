import SwiftUI
import SwiftData
import DSKit

@main
struct HumanProgramApp: App {
    @State private var appState = AppState()
    @AppStorage(DefaultsKey.fontChoice) private var fontChoiceRaw = FontChoice.default.rawValue
    @AppStorage(DefaultsKey.fontSizeStep) private var fontSizeStep = FontSizeStep.defaultIndex
    @AppStorage(DefaultsKey.appearanceMode) private var appearanceModeRaw = AppearanceMode.system.rawValue
    private let container: ModelContainer

    init() {
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
