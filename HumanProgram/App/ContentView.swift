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
    @AppStorage(DefaultsKey.onboarded) private var onboarded = false
    // Fresh-install-only flag for the permissions step. A factory reset deliberately
    // SETS this true (FactoryResetView) so the re-run of onboarding skips permissions.
    @AppStorage(DefaultsKey.permissionsAsked) private var permissionsAsked = false
    // Shake-triggered undo/redo popup (shown only during normal app use).
    @State private var showUndoPopup = false

    /// The one full-screen gate (if any) to show over the app. Rendered as a single
    /// continuous overlay (see body) rather than a `.fullScreenCover`: covers never
    /// dismiss/re-present between steps, so the Today root never flashes in the gap.
    fileprivate enum StartupCover: Identifiable {
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
                StartupCoverView(
                    cover: cover,
                    lockVM: lockVM,
                    permissionsAsked: $permissionsAsked,
                    onInterstitialDone: finishInterstitial,
                    onOnboardingDone: finishOnboarding
                )
                .transition(.identity)
                .zIndex(1)
            }

            // Always-present shake listener (invisible, never intercepts touches).
            ShakeDetector().allowsHitTesting(false).frame(width: 0, height: 0)

            // Shake → undo/redo popup. Only during normal use (never over the lock
            // screen / onboarding / interstitials).
            if showUndoPopup && startupCover == nil {
                UndoRedoPopup(
                    onUndo: { UndoStore.shared.undo(context: context) },
                    onRedo: { UndoStore.shared.redo(context: context) },
                    onDismiss: { showUndoPopup = false }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .humanProgramShake)) { _ in
            guard startupCover == nil else { return }
            Haptics.impact(.medium)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showUndoPopup = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .humanProgramExitToHub)) { _ in
            // Pop everything back to the hub (e.g. after first-time PIN creation).
            path = []
        }
        .onOpenURL { url in
            // A home-screen widget tap opens humanprogram://today → show Today.
            guard url.scheme == "humanprogram" else { return }
            path = [.today]
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
        ) { _ in
            // Stamp the away-time AND lock immediately when the timeout is 0, so
            // "Lock immediately" is reliable and the app-switcher snapshot is hidden.
            lockVM.handleEnterBackground()
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

    /// Reset/restore confirmation dismissed. After a reset, onboarding must run
    /// again. FactoryResetView clears `hp.onboarded` in UserDefaults directly, but
    /// that external write isn't reliably observed by this @AppStorage instance — so
    /// we clear it here through the binding to guarantee the onboarding cover appears.
    /// The onboarding flow re-enters at `.welcome` on its own because the cover
    /// rebuilds `OnboardingFlowView` fresh (its step @State starts at `.welcome`).
    private func finishInterstitial() {
        let dismissed = appState.pendingInterstitial
        appState.pendingInterstitial = nil
        if dismissed == .reset {
            onboarded = false
        }
        path = [.today]
    }

    private func finishOnboarding() {
        onboarded = true
        path = [.today]
    }
}

// ── Startup gate ─────────────────────────────────────────────────────────────────
// The continuous full-screen cover (reset/restore confirmation, onboarding, or the
// app-unlock gate). One opaque overlay swapped in place, so the app underneath never
// flashes between steps. See ContentView.body for why this is an overlay, not a
// .fullScreenCover.
private struct StartupCoverView: View {
    let cover: ContentView.StartupCover
    let lockVM: AppLockViewModel
    @Binding var permissionsAsked: Bool
    let onInterstitialDone: () -> Void
    let onOnboardingDone: () -> Void

    var body: some View {
        switch cover {
        case .interstitial(let pending):
            AppInterstitialView(mode: interstitialMode(pending), onAction: onInterstitialDone)
        case .onboarding:
            OnboardingFlowView(permissionsAsked: $permissionsAsked, onFinish: onOnboardingDone)
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
}

// ── Onboarding flow ──────────────────────────────────────────────────────────────
// Welcome → Terms of Service (must agree) → Privacy Policy (must agree) → Tutorial
// → (fresh install only) Permissions. The app cannot be reached until both the Terms
// and the Privacy Policy are confirmed. Owns its own step state, which starts at
// `.welcome` every time the flow is presented (so it re-runs after a factory reset).
private struct OnboardingFlowView: View {
    @Binding var permissionsAsked: Bool
    let onFinish: () -> Void

    private enum Step { case welcome, terms, privacy, tutorial, permissions }
    @State private var step: Step = .welcome
    /// When the Terms were confirmed this run — paired with the Privacy confirmation
    /// to write one permanent acceptance record (see AcceptanceAuditLog).
    @State private var tosAcceptedAt: Date?

    var body: some View {
        switch step {
        case .welcome:
            AppInterstitialView(mode: .welcome) {
                withAnimation { step = .terms }
            }
        case .terms:
            TermsOfServiceView(mode: .onboarding) {
                tosAcceptedAt = Date()
                withAnimation { step = .privacy }
            }
        case .privacy:
            PrivacyPolicyView(mode: .onboarding) {
                let now = Date()
                // One permanent, on-device audit entry per acceptance cycle. Lives in
                // the Keychain, so it survives factory reset, backup restore, and even
                // reinstall — install logs 1, each later reset adds another.
                AcceptanceAuditLog.recordAcceptance(
                    tosAcceptedAt: tosAcceptedAt ?? now,
                    privacyAcceptedAt: now
                )
                withAnimation { step = .tutorial }
            }
        case .tutorial:
            TutorialView(mode: .onboarding) {
                // Fresh install → ask for permissions. After a factory reset,
                // permissionsAsked is already true, so skip straight to the app.
                if permissionsAsked {
                    onFinish()
                } else {
                    withAnimation { step = .permissions }
                }
            }
        case .permissions:
            PermissionsOnboardingView {
                permissionsAsked = true
                onFinish()
            }
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
