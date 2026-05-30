import SwiftUI
import SwiftData
import DSKit

@main
struct HumanProgramApp: App {
    @State private var appState = AppState()
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
                .dsAppearance(AppTheme.appearance)
        }
        .modelContainer(container)
    }
}
