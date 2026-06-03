import SwiftUI
import DSKit
import UIKit

struct AboutView: View {
    @State private var showDocument = false

    var body: some View {
        SettingsScreen(centered: true) {
            // App name header
            DSText("Human Program")
                .dsTextStyle(.title2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

            SettingsGroup {
                SettingsRowContent(label: "Developer", systemImage: "person", value: "David Ko") { EmptyView() }

                // Version — double-tap opens the hidden document
                SettingsRowContent(label: "Version", systemImage: "number", value: AppInfo.displayVersion) { EmptyView() }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showDocument = true }

                SettingsNavRow(label: "Licenses", systemImage: "doc.text") { LicensesView() }

                SettingsNavRow(label: "Terms of Service", systemImage: "doc.plaintext") {
                    TermsOfServiceView(mode: .reference)
                }

                SettingsNavRow(label: "Tutorial", systemImage: "questionmark.circle") {
                    TutorialView(mode: .reference)
                }

                SettingsNavRow(label: "Cat Corner", systemImage: "cat") { CatCornerView() }
            }
        }
        // Pushed page (back button + swipe-back), not a modal sheet.
        .navigationDestination(isPresented: $showDocument) {
            HiddenDocumentView()
        }
    }
}

// CatCornerView is defined in Features/Settings/CatCornerView.swift

// ── Hidden document view ──────────────────────────────────────────
// A pushed page on the shared SettingsScreen container (themed gradient
// background, back button, swipe-back) — not a modal sheet.
struct HiddenDocumentView: View {
    // Full text loaded from the bundled UDHR.txt resource (sourced from the UN). [#52]
    private var udhrText: String {
        guard let url = Bundle.main.url(forResource: "UDHR", withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    var body: some View {
        SettingsScreen(centered: true) {
            VStack(alignment: .leading, spacing: 16) {
                DSText("Universal Declaration of Human Rights")
                    .dsTextStyle(.title3)
                    .padding(.bottom, 4)
                DSText("Adopted by the UN General Assembly on 10 December 1948.")
                    .dsTextStyle(.subheadline)
                DSText(udhrText)
                    .dsTextStyle(.body)
                VStack(alignment: .leading, spacing: 6) {
                    DSText("United Nations General Assembly. Universal Declaration of Human Rights. Resolution 217 A (III), Paris, 10 December 1948.")
                        .dsTextStyle(.footnote)
                    Link("un.org/en/about-us/universal-declaration-of-human-rights",
                         destination: URL(string: "https://www.un.org/en/about-us/universal-declaration-of-human-rights")!)
                        .font(appFont(15))
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

