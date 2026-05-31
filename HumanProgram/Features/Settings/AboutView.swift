import SwiftUI
import DSKit
import UIKit

struct AboutView: View {
    @State private var showSudokuGate = false
    @State private var showDocument = false
    private let gateService = EasterEggGateService()
    @Environment(AppState.self) private var appState

    private var versionValue: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        SettingsScreen(centered: true) {
            // App name header
            DSText("Human Program")
                .dsTextStyle(.title2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

            SettingsGroup {
                // Developer — double-tap triggers the hidden game gate (no affordance)
                SettingsRowContent(label: "Developer", systemImage: "person", value: "David Ko") { EmptyView() }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { handleDeveloperTap() }

                // Version — double-tap opens the hidden document
                SettingsRowContent(label: "Version", systemImage: "number", value: versionValue) { EmptyView() }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showDocument = true }

                SettingsNavRow(label: "Licenses", systemImage: "doc.text") { LicensesView() }

                SettingsNavRow(label: "Cat Corner", systemImage: "cat") { CatCornerView() }
            }
        }
        .fullScreenCover(isPresented: $showSudokuGate) {
            SudokuGateView()
        }
        // Pushed page (back button + swipe-back), not a modal sheet.
        .navigationDestination(isPresented: $showDocument) {
            HiddenDocumentView()
        }
    }

    /// Double-tap the developer name: reveal the gate if today is complete,
    /// otherwise a subtle haptic and nothing else (no visual affordance).
    private func handleDeveloperTap() {
        let today = Calendar.current.startOfDay(for: Date())
        let tempPage = DailyPage(date: today)
        tempPage.dayComplete = appState.streakStats.currentStreak > 0 || isCurrentDayComplete()
        if gateService.shouldRevealGate(todayPage: tempPage, today: today) {
            showSudokuGate = true
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func isCurrentDayComplete() -> Bool {
        appState.streakStats.currentStreak > 0
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
                Link("Source: United Nations (un.org)",
                     destination: URL(string: "https://www.un.org/en/about-us/universal-declaration-of-human-rights")!)
                    .font(appFont(15))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

