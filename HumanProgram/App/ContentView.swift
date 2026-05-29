import SwiftUI
import SwiftData

// ── Root view ─────────────────────────────────────────────────────────────────
// Today is the root. A hamburger button in the top-left toolbar pushes to
// ProgramView inside the same NavigationStack — no sheet, no TabView.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            TodayView(context: context)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink(destination: ProgramView()) {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .accessibilityLabel("Open Program menu")
                    }
                }
        }
        .task {
            do {
                try await AppStartup.run(context: context, appState: appState)
            } catch {
                print("[AppStartup] error: \(error)")
            }
        }
    }
}

// ── Program view ──────────────────────────────────────────────────────────────
// Full-screen push page. 2-column grid of tiles navigating to each section.
struct ProgramView: View {
    private struct Destination: Identifiable {
        let id: String
        let label: String
        let icon: String
        let view: AnyView
    }

    private let destinations: [Destination] = [
        Destination(id: "backlog",   label: "Backlog",   icon: "tray.full",      view: AnyView(BacklogView())),
        Destination(id: "calendar",  label: "Calendar",  icon: "calendar",       view: AnyView(CalendarPlaceholderView())),
        Destination(id: "routines",  label: "Routines",  icon: "repeat",         view: AnyView(RoutinesView())),
        Destination(id: "stats",     label: "Stats",     icon: "chart.bar",      view: AnyView(StatsView())),
        Destination(id: "settings",  label: "Settings",  icon: "gear",           view: AnyView(SettingsView())),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 16
            ) {
                ForEach(destinations) { dest in
                    NavigationLink(destination: dest.view) {
                        ProgramTileView(label: dest.label, icon: dest.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(AppColors.background)
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.large)
    }
}

// ── Program tile ──────────────────────────────────────────────────────────────
struct ProgramTileView: View {
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppColors.accent)
            Text(label)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(AppColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColors.border, lineWidth: 0.5)
        )
    }
}

// ── Calendar placeholder ──────────────────────────────────────────────────────
struct CalendarPlaceholderView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "calendar")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(AppColors.textTertiary)
                Text("Calendar")
                    .font(AppTypography.pageTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text("Coming soon")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
