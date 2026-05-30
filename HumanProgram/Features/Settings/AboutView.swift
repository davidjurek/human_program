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
        SettingsScreen {
            // App name header
            DSText("Human Program")
                .dsTextStyle(.title2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

            SettingsGroup {
                // Developer — double-tap triggers the hidden game gate (no affordance)
                SettingsRowContent(label: "Developer", systemImage: "person", value: "David Jurek") { EmptyView() }
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
        .sheet(isPresented: $showDocument) {
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
struct HiddenDocumentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DSText("Universal Declaration of Human Rights")
                        .dsTextStyle(.title3)
                        .padding(.bottom, 4)
                    DSText("Adopted by the UN General Assembly on 10 December 1948.")
                        .dsTextStyle(.subheadline)
                    DSText(humanRightsExcerpt)
                        .dsTextStyle(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .dsScreen()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private let humanRightsExcerpt = """
Article 1. All human beings are born free and equal in dignity and rights. They are endowed with reason and conscience and should act towards one another in a spirit of brotherhood.

Article 2. Everyone is entitled to all the rights and freedoms set forth in this Declaration, without distinction of any kind, such as race, colour, sex, language, religion, political or other opinion, national or social origin, property, birth or other status.

Article 3. Everyone has the right to life, liberty and security of person.

Article 4. No one shall be held in slavery or servitude; slavery and the slave trade shall be prohibited in all their forms.

Article 5. No one shall be subjected to torture or to cruel, inhuman or degrading treatment or punishment.

Article 6. Everyone has the right to recognition everywhere as a person before the law.

Article 7. All are equal before the law and are entitled without any discrimination to equal protection of the law.

Article 8. Everyone has the right to an effective remedy by the competent national tribunals for acts violating the fundamental rights granted him by the constitution or by law.

Article 9. No one shall be subjected to arbitrary arrest, detention or exile.

Article 10. Everyone is entitled in full equality to a fair and public hearing by an independent and impartial tribunal, in the determination of his rights and obligations and of any criminal charge against him.

(Full text available at un.org/en/about-us/universal-declaration-of-human-rights)
"""
