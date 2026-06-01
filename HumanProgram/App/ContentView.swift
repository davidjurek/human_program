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
    @AppStorage("hp.onboarded") private var onboarded = false
    // Fresh-install-only flag for the permissions step. A factory reset deliberately
    // SETS this true (FactoryResetView) so the re-run of onboarding skips permissions.
    @AppStorage("hp.permissionsAsked") private var permissionsAsked = false
    @State private var onboardingStep: OnboardingStep = .welcome

    private enum OnboardingStep { case welcome, terms, tutorial, permissions }

    /// The one full-screen gate (if any) to show over the app. Rendered as a single
    /// continuous overlay (see body) rather than a `.fullScreenCover`: covers never
    /// dismiss/re-present between steps, so the Today root never flashes in the gap.
    private enum StartupCover: Identifiable {
        case interstitial(AppInterstitial)   // reset / restore confirmation
        case onboarding                       // welcome → terms → tutorial
        case lock                             // app-unlock gate
        var id: String {
            switch self {
            case .interstitial(let m): return "interstitial-\(m)"
            case .onboarding:          return "onboarding"
            case .lock:                return "lock"
            }
        }
    }

    private var startupCover: StartupCover? {
        // Reset/restore confirmation first; after a reset it clears `onboarded`,
        // so the onboarding sequence then takes over.
        if let pending = appState.pendingInterstitial { return .interstitial(pending) }
        if !onboarded { return .onboarding }
        if lockVM.isLocked { return .lock }
        return nil
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                HubView()
                    .navigationDestination(for: HubDestination.self) { dest in
                        dest.view(context: context)
                    }
            }
            // Continuous full-screen gate, drawn as an OVERLAY (not a
            // fullScreenCover). Moving from one startup screen to the next — e.g. the
            // reset confirmation → onboarding — is an in-place content swap while the
            // overlay stays mounted, so the Today root never flashes between them.
            // Each gate view is opaque full-screen (SettingsBackground ignores the
            // safe area), so it fully blocks the app underneath.
            if let cover = startupCover {
                startupCoverView(cover)
                    .transition(.identity)
                    .zIndex(1)
            }
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

    @ViewBuilder
    private func startupCoverView(_ cover: StartupCover) -> some View {
        switch cover {
        case .interstitial(let pending):
            AppInterstitialView(mode: interstitialMode(pending), onAction: finishInterstitial)
        case .onboarding:
            onboardingView
        case .lock:
            LockScreenView(vm: lockVM)
        }
    }

    private func interstitialMode(_ pending: AppInterstitial) -> AppInterstitialView.Mode {
        switch pending {
        case .reset:    return .reset
        case .restored: return .restored
        }
    }

    // Onboarding sequence: Welcome → Terms of Service (must agree) → Tutorial →
    // (fresh install only) Permissions. The app cannot be reached until the Terms
    // are confirmed.
    @ViewBuilder
    private var onboardingView: some View {
        switch onboardingStep {
        case .welcome:
            AppInterstitialView(mode: .welcome) {
                withAnimation { onboardingStep = .terms }
            }
        case .terms:
            TermsOfServiceView(mode: .onboarding) {
                withAnimation { onboardingStep = .tutorial }
            }
        case .tutorial:
            TutorialView(mode: .onboarding) {
                // Fresh install → ask for permissions. After a factory reset,
                // permissionsAsked is already true, so skip straight to the app.
                if permissionsAsked {
                    finishOnboarding()
                } else {
                    withAnimation { onboardingStep = .permissions }
                }
            }
        case .permissions:
            PermissionsOnboardingView { finishPermissions() }
        }
    }

    /// Reset/restore confirmation dismissed. After a reset, onboarding must run
    /// again. FactoryResetView clears `hp.onboarded` in UserDefaults directly, but
    /// that external write isn't reliably observed by this @AppStorage instance — so
    /// we clear it here through the binding to guarantee the onboarding cover appears.
    private func finishInterstitial() {
        let dismissed = appState.pendingInterstitial
        appState.pendingInterstitial = nil
        if dismissed == .reset {
            onboardingStep = .welcome
            onboarded = false
        }
        path = [.today]
    }

    private func finishPermissions() {
        permissionsAsked = true
        finishOnboarding()
    }

    private func finishOnboarding() {
        onboarded = true
        onboardingStep = .welcome
        path = [.today]
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

    private let hPad: CGFloat = 20
    private let colSpacing: CGFloat = 16

    var body: some View {
        ZStack {
            SettingsBackground()
            GeometryReader { geo in
                // Explicit square side from the available width (aspectRatio alone
                // didn't constrain the greedy-width tiles). [#44]
                let side = (geo.size.width - hPad * 2 - colSpacing) / 2
                VStack(spacing: colSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: colSpacing) {
                            ForEach(pair, id: \.self) { dest in
                                NavigationLink(value: dest) {
                                    HubTile(label: dest.label, icon: dest.icon)
                                        .frame(width: side, height: side)   // square
                                }
                                .buttonStyle(.plain)
                                .a11yTapBorder(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                    }
                }
                .padding(.horizontal, hPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // fill the square from the parent [#44]
        .hubTileGlass(cornerRadius: 22)                     // clear glass, separate from popups [#22]
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
