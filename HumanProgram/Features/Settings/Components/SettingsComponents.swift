import SwiftUI
import DSKit

// Shared DSKit building blocks for the Settings area.
//
// Every Settings screen is composed from these so the look stays consistent
// and a visual change is made in exactly one place (per the reuse rule).

/// Soft lavender → peach gradient used behind the Settings-area screens only.
struct SettingsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.80, green: 0.79, blue: 0.96),  // lavender
                Color(red: 0.86, green: 0.90, blue: 0.99),  // soft blue
                Color(red: 0.99, green: 0.85, blue: 0.78)   // peach
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Themed scrolling container for a settings screen.
/// Soft gradient background, no navigation title (header titles are hidden
/// app-wide; the back button stays).
struct SettingsScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content()
                }
                .padding(.leading, 44)
                .padding(.trailing, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Uppercase section label sitting above a group of rows.
struct SettingsSectionLabel: View {
    let title: String
    var body: some View {
        DSText(title.uppercased())
            .dsTextStyle(.caption1)
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
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            if let systemImage {
                DSImageView(systemName: systemImage, size: .font(.title3), tint: .color(.primary))
            }
            DSText(label).dsTextStyle(.title3)
            Spacer(minLength: 8)
            if let value {
                DSText(value).dsTextStyle(.subheadline)
            }
            trailing()
        }
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
