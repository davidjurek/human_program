import SwiftUI
import DSKit

/// One numbered clause of a legal document (title + body paragraph(s)).
struct LegalSection { let title: String; let body: String }

// Shared renderer for the app's legal documents (Terms of Service, Privacy
// Policy). ONE body of styled text drives two presentations so the chrome,
// spacing, and the agree-gate live in a single place:
//  • .onboarding — a full-screen gate shown once on fresh install / after a
//    factory reset. The agree checkbox + Confirm button sit at the very BOTTOM
//    of the scroll, so they're only reachable after scrolling through the text.
//    Confirm is disabled until the box is checked.
//  • .reference  — a normal pushed page (Settings → About), read-only.
//
// NOTE: developer-authored text to be reviewed by a qualified legal professional
// before release. It is not legal advice.
struct LegalDocumentView: View {
    enum Mode { case onboarding, reference }

    let mode: Mode
    /// Big centered title ("Terms of Service" / "Privacy Policy").
    let docTitle: String
    /// Secondary line under the title (effective / last-updated line).
    let subtitle: String
    /// Optional unnumbered lead paragraph(s) shown before the numbered sections.
    var lead: String? = nil
    /// Optional custom view rendered IN PLACE of the plain `lead` text (used by the
    /// Privacy Policy reference screen to host its hidden log-access paragraph).
    var leadView: AnyView? = nil
    /// The numbered clauses.
    let sections: [LegalSection]
    /// Checkbox label shown in onboarding mode.
    let agreeText: String
    /// Called when the user confirms in onboarding mode.
    var onConfirm: () -> Void = {}

    @State private var agreed = false

    var body: some View {
        switch mode {
        case .reference:
            SettingsScreen(centered: true) {
                header
                bodyContent
            }
        case .onboarding:
            OnboardingScrollScaffold {
                header
            } content: {
                VStack(alignment: .leading, spacing: 16) {
                    bodyContent
                    gate
                }
            }
        }
    }

    // MARK: - Shared body (lead + numbered sections)

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let leadView {
                leadView
            } else if let lead, !lead.isEmpty {
                DSText(lead).dsTextStyle(.body)
            }
            ForEach(sections.indices, id: \.self) { i in
                section(number: i + 1, sections[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(number: Int, _ s: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DSText("\(number). \(s.title)").dsTextStyle(.headline)
            DSText(s.body).dsTextStyle(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Onboarding gate (bottom of the scroll)

    private var gate: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                .padding(.vertical, 4)

            Button { agreed.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(agreed ? appOnboardingBlue : Color.secondary)
                    DSText(agreeText)
                        .dsTextStyle(.body)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .a11yTapBorder(cornerRadius: 6)

            OnboardingPrimaryButton(title: "Confirm", enabled: agreed) {
                if agreed { onConfirm() }
            }
        }
    }

    // MARK: - Header (center-aligned title, shared by both modes)

    /// Uses plain Text (not DSText) so multi-line center alignment actually
    /// applies. In onboarding mode this is frozen above the scroll; in reference
    /// mode it sits at the top of the scroll.
    private var header: some View {
        VStack(spacing: 8) {
            Text(docTitle)
                .font(appFont(22)).foregroundStyle(.primary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text("Human Program")
                .font(appFont(17, bold: true)).foregroundStyle(.primary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text(subtitle)
                .font(appFont(15)).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
