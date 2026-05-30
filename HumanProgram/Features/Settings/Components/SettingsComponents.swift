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
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content()
                }
                .padding(.leading, centered ? 20 : 44)
                .padding(.trailing, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        // Hiding the system back button also turns off iOS's leading-edge
        // swipe-back gesture. Re-enable it here — but only on screens that use
        // the default back (onBack == nil). Screens with a custom back guard
        // (e.g. discard-changes) keep swipe off so a swipe can't bypass it.
        .background(SwipeBackEnabler(enabled: onBack == nil))
    }

    // Bare buttons (no glass card). High-priority back tap so the leading-edge
    // swipe-back gesture can't swallow it.
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
    }
}

/// Restores the iOS leading-edge swipe-back gesture on screens that hide the
/// system nav-bar back button (which normally disables the gesture). It does
/// this by re-pointing the navigation controller's interactive-pop gesture at
/// our own delegate, which allows the swipe whenever there's a screen to pop
/// back to. When `enabled` is false the gesture is suppressed (used by screens
/// with a custom back guard so a swipe can't skip the guard).
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    var enabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.enabled = enabled
        return UIViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        context.coordinator.enabled = enabled
        // Re-assert on every update so popping back to this screen restores it.
        DispatchQueue.main.async {
            guard let nav = vc.navigationController else { return }
            context.coordinator.navController = nav
            nav.interactivePopGestureRecognizer?.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navController: UINavigationController?
        var enabled = true

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard enabled else { return false }
            return (navController?.viewControllers.count ?? 0) > 1
        }
    }
}

extension SettingsScreen where Trailing == EmptyView {
    init(centered: Bool = false,
         onBack: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(centered: centered, onBack: onBack, trailing: { EmptyView() }, content: content)
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
            } else {
                DSText(label).dsTextStyle(.title3)
            }
            Spacer(minLength: 8)
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
struct SettingsNavRow<Destination: View>: View {
    let label: String
    var systemImage: String? = nil
    @ViewBuilder var destination: () -> Destination

    init(label: String, systemImage: String? = nil, @ViewBuilder destination: @escaping () -> Destination) {
        self.label = label
        self.systemImage = systemImage
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowContent(label: label, systemImage: systemImage) { EmptyView() }
        }
        .buttonStyle(.plain)
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
