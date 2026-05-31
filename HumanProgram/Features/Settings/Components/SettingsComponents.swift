import SwiftUI
import DSKit

// Shared DSKit building blocks for the Settings area.
//
// Every Settings screen is composed from these so the look stays consistent
// and a visual change is made in exactly one place (per the reuse rule).

/// The app background behind the Settings-area screens. Reacts to the system
/// color scheme: light mode uses the chosen light background, dark mode the
/// chosen dark background.
struct SettingsBackground: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("settings.bgLight") private var lightIndex: Int = 0
    @AppStorage("settings.bgDark") private var darkIndex: Int = 0

    var body: some View {
        AppBackground.resolved(light: lightIndex, dark: darkIndex, scheme: scheme).view
            .ignoresSafeArea()
    }
}

/// Themed scrolling container for a settings screen.
/// Soft gradient background, no navigation title (header titles are hidden
/// app-wide; the back button stays).
struct SettingsScreen<Content: View, Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss

    /// Menus use an asymmetric (right-shifted) inset; editor screens centered.
    var centered: Bool = false
    /// Custom back action (e.g. a discard-changes guard). Defaults to dismiss().
    var onBack: (() -> Void)?
    /// Returns true when a leading-edge swipe-back should be intercepted instead
    /// of popping — e.g. there are unsaved changes. When it returns true the
    /// swipe runs `onBack` (which shows the discard popup) rather than popping.
    /// Default `false`: swipe pops normally.
    var swipeBackBlocked: () -> Bool = { false }
    /// Freezes vertical scrolling — used while a row is being drag-reordered so
    /// the reorder drag doesn't also scroll the page.
    var scrollDisabled: Bool = false
    /// Opts out of SwiftUI's automatic keyboard avoidance so the screen can
    /// position the focused field itself (used by the Schedule editor for a
    /// consistent gap above the keyboard).
    var manualKeyboardAvoidance: Bool = false
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content()
                }
                .padding(.leading, centered ? 20 : 42)
                .padding(.trailing, centered ? 20 : 8)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Pull the vertical scroll indicator a few points inboard so the
                // FULL bar is visible — without it the indicator hugs (and gets
                // half-clipped by) the screen's trailing edge. Indicator-only; it
                // moves no content. This is the standard DSKit scroll behavior.
                .background(ScrollIndicatorInset(right: 7))
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(scrollDisabled)
            .modifier(IgnoreKeyboardSafeArea(active: manualKeyboardAvoidance))
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        // Hiding the system back button also turns off iOS's leading-edge
        // swipe-back gesture. Re-enable it here for EVERY settings screen.
        // When `swipeBackBlocked()` is true (unsaved changes) the swipe runs
        // `onBack` — which shows the discard popup — instead of popping, so a
        // swipe can't silently bypass the guard but still works everywhere.
        .background(SwipeBackEnabler(blocked: swipeBackBlocked,
                                     onBlocked: onBack ?? { dismiss() }))
    }

    // Bare buttons (no glass card). High-priority back tap so the leading-edge
    // swipe-back gesture can't swallow it. A gradient frost sits behind the bar
    // so the buttons stay legible when content scrolls up under them.
    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    if let onBack { onBack() } else { dismiss() }
                })
            Spacer()
            trailing()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .black, location: 0.55),
                                .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom)
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

/// Restores the iOS leading-edge swipe-back gesture on screens that hide the
/// system nav-bar back button (which normally disables the gesture).
///
/// All settings screens share ONE navigation controller and therefore one
/// `interactivePopGestureRecognizer`. The fix re-points that recognizer's
/// delegate at this screen's coordinator and re-asserts it every time the
/// screen (re)appears — `viewWillAppear` fires when you pop back, so returning
/// from a guarded editor no longer leaves a stale delegate that kills the swipe
/// on the screen underneath. That stale-delegate race was why swipe-back worked
/// on some screens but not others.
///
/// When `blocked()` returns true (unsaved changes) the swipe doesn't pop;
/// instead it runs `onBlocked` (the discard guard) so the popup appears.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    var blocked: () -> Bool
    var onBlocked: () -> Void

    func makeUIViewController(context: Context) -> Host {
        let host = Host()
        host.coordinator = context.coordinator
        context.coordinator.blocked = blocked
        context.coordinator.onBlocked = onBlocked
        return host
    }

    func updateUIViewController(_ host: Host, context: Context) {
        context.coordinator.blocked = blocked
        context.coordinator.onBlocked = onBlocked
        host.coordinator = context.coordinator
        host.reassert()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navController: UINavigationController?
        var blocked: () -> Bool = { false }
        var onBlocked: () -> Void = {}

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard (navController?.viewControllers.count ?? 0) > 1 else { return false }
            if blocked() {
                // Unsaved changes: don't pop. Trigger the guard (discard popup).
                onBlocked()
                return false
            }
            return true
        }
    }

    /// Host controller that re-claims the interactive-pop delegate whenever this
    /// screen appears (including when popped back to), so the swipe never goes
    /// stale after visiting another screen.
    final class Host: UIViewController {
        weak var coordinator: Coordinator?

        func reassert() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let nav = self.navigationController else { return }
                self.coordinator?.navController = nav
                nav.interactivePopGestureRecognizer?.delegate = self.coordinator
                nav.interactivePopGestureRecognizer?.isEnabled = true
            }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            reassert()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            reassert()
        }
    }
}

extension SettingsScreen where Trailing == EmptyView {
    init(centered: Bool = false,
         onBack: (() -> Void)? = nil,
         swipeBackBlocked: @escaping () -> Bool = { false },
         scrollDisabled: Bool = false,
         manualKeyboardAvoidance: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(centered: centered, onBack: onBack, swipeBackBlocked: swipeBackBlocked,
                  scrollDisabled: scrollDisabled, manualKeyboardAvoidance: manualKeyboardAvoidance,
                  trailing: { EmptyView() }, content: content)
    }
}

/// Reaches the enclosing `UIScrollView` and insets the vertical scroll indicator
/// inboard from the trailing edge, so the full bar is always visible instead of
/// being half-clipped at the screen edge. Keeps `automaticallyAdjustsScrollIndicatorInsets`
/// on (so the top safe-area inset still applies) and only adds a right inset.
/// Indicator-only — it never moves content.
struct ScrollIndicatorInset: UIViewRepresentable {
    var right: CGFloat

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var view: UIView? = uiView
            while let cur = view, !(cur is UIScrollView) { view = cur.superview }
            guard let scroll = view as? UIScrollView else { return }
            scroll.showsVerticalScrollIndicator = true
            let insets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: right)
            if scroll.verticalScrollIndicatorInsets != insets {
                scroll.verticalScrollIndicatorInsets = insets
            }
        }
    }
}

/// Conditionally opts a view out of keyboard safe-area avoidance.
private struct IgnoreKeyboardSafeArea: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            content
        }
    }
}

/// Top-right "+" that pushes a destination. Used by every planning LIST screen
/// (Recurring Tasks, Schedule, Reminders) so the look — and the tap target —
/// stay identical. The full 44×44 frame is made tappable with `contentShape`,
/// so a tap on the padding around the glyph still registers (without it, only
/// the opaque "+" pixels were hittable, which is why the tap sometimes missed).
struct AddNavButton<Destination: View>: View {
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Uppercase section label sitting above a group of rows.
struct SettingsSectionLabel: View {
    let title: String
    var body: some View {
        DSText(title.uppercased())
            .dsTextStyle(.caption1)
            .lineLimit(1)
            .frame(height: 20, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled group of settings rows (optional header + stacked rows).
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title { SettingsSectionLabel(title: title) }
            VStack(alignment: .leading, spacing: 38) { content() }
        }
    }
}

/// The visual content of a single open settings row: leading icon, label,
/// optional trailing value, and an arbitrary trailing accessory.
/// Card-less, no chevron — icon + label on the screen background.
struct SettingsRowContent<Trailing: View>: View {
    let label: String
    var systemImage: String? = nil
    var value: String? = nil
    /// Renders the icon + label in red (e.g. Factory Reset).
    var destructive: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            if let systemImage {
                DSImageView(systemName: systemImage, size: .font(.title3),
                            tint: destructive ? .color(.red) : .color(.primary))
            }
            if destructive {
                DSText(label).dsTextStyle(.title3, Color.red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DSText(label).dsTextStyle(.title3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let value {
                DSText(value).dsTextStyle(.subheadline)
            }
            trailing()
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A settings row that pushes a destination when tapped (icon + label, no chevron).
/// Optionally shows a trailing value and/or renders in the destructive (red) style.
struct SettingsNavRow<Destination: View>: View {
    let label: String
    var systemImage: String? = nil
    var value: String? = nil
    var destructive: Bool = false
    @ViewBuilder var destination: () -> Destination

    init(label: String, systemImage: String? = nil, value: String? = nil,
         destructive: Bool = false, @ViewBuilder destination: @escaping () -> Destination) {
        self.label = label
        self.systemImage = systemImage
        self.value = value
        self.destructive = destructive
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowContent(label: label, systemImage: systemImage,
                               value: value, destructive: destructive) { EmptyView() }
        }
        .buttonStyle(.plain)
    }
}

/// A settings row carrying a trailing native Toggle (icon + label + switch).
/// Used wherever a setting is a simple on/off (App Lock, biometrics, etc.).
struct SettingsToggleRow: View {
    let label: String
    var systemImage: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowContent(label: label, systemImage: systemImage) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(appToggleTint)
        }
    }
}

/// A settings row that runs an action when tapped (no navigation). Optionally destructive.
struct SettingsButtonRow: View {
    let label: String
    var systemImage: String? = nil
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(label: label, systemImage: systemImage, destructive: destructive) { EmptyView() }
        }
        .buttonStyle(.plain)
    }
}

/// A selectable option row (label + checkmark when selected). Used in option lists
/// such as Appearance, Date Format, Time Format.
struct SettingsSelectRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                DSText(label).dsTextStyle(.title3)
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
