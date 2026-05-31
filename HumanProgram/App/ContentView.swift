import SwiftUI
import SwiftData
import DSKit

// ── Root view ─────────────────────────────────────────────────────────────────
// The HUB (top-level menu) is the navigation root. On launch the app deep-links
// straight to Today (pushed on top of the hub), so Today's back arrow returns to
// the hub. Every section is pushed from the hub the same way. No tab bar.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @State private var lockVM = AppLockViewModel()
    @State private var path: [HubDestination] = [.today]   // launch at Today
    @AppStorage("hp.hasLaunched") private var hasLaunched = false

    private var showInterstitial: Bool {
        appState.pendingInterstitial != nil || !hasLaunched
    }
    private var interstitialMode: AppInterstitialView.Mode {
        switch appState.pendingInterstitial {
        case .reset:    return .reset
        case .restored: return .restored
        case nil:       return .welcome
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            HubView()
                .navigationDestination(for: HubDestination.self) { dest in
                    dest.view(context: context)
                }
        }
        .fullScreenCover(isPresented: Binding(
            get: { lockVM.isLocked },
            set: { _ in }
        )) {
            LockScreenView(vm: lockVM)
        }
        .fullScreenCover(isPresented: Binding(
            get: { showInterstitial },
            set: { _ in }
        )) {
            AppInterstitialView(mode: interstitialMode, onAction: handleInterstitial)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            lockVM.checkLockOnForeground()
        }
        .task {
            do {
                try await AppStartup.run(context: context, appState: appState)
            } catch {
                print("[AppStartup] error: \(error)")
            }
        }
    }

    /// Tapping the interstitial button. For reset/restored we clear the pending
    /// state and return to Today; after a reset, `hasLaunched` was cleared so the
    /// Welcome screen appears next (waiting underneath). For Welcome, mark launched.
    private func handleInterstitial() {
        if appState.pendingInterstitial != nil {
            appState.pendingInterstitial = nil
            path = [.today]
        } else {
            hasLaunched = true
            path = [.today]
        }
    }
}

// ── Hub destinations ────────────────────────────────────────────────────────────
enum HubDestination: String, Hashable, CaseIterable {
    case today, backlog, calendar, routines, stats, settings

    var label: String {
        switch self {
        case .today:    return "Today"
        case .backlog:  return "Backlog"
        case .calendar: return "Calendar"
        case .routines: return "Routines"
        case .stats:    return "Stats"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today:    return "sun.max"
        case .backlog:  return "tray.full"
        case .calendar: return "calendar"
        case .routines: return "repeat"
        case .stats:    return "chart.bar"
        case .settings: return "gearshape"
        }
    }

    @ViewBuilder
    func view(context: ModelContext) -> some View {
        switch self {
        case .today:    TodayView(context: context)
        case .backlog:  BacklogView()
        case .calendar: CalendarView()
        case .routines: RoutinesView()
        case .stats:    StatsView()
        case .settings: SettingsView()
        }
    }
}

// ── Hub (top-level menu) ─────────────────────────────────────────────────────────
// Static (no scroll), centered both ways, 2-across glass tiles, ~42 side margins,
// no title and no back arrow (it's the root).
struct HubView: View {
    // Row-pairs in the requested order.
    private let rows: [[HubDestination]] = [
        [.today, .backlog],
        [.calendar, .routines],
        [.stats, .settings]
    ]

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 16) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 16) {
                        ForEach(pair, id: \.self) { dest in
                            NavigationLink(value: dest) {
                                HubTile(label: dest.label, icon: dest.icon)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct HubTile: View {
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            DSImageView(systemName: icon, size: 34, tint: .color(.primary))
            DSText(label).dsTextStyle(.headline)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)   // square tiles [#16]
        .popupGlass(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
