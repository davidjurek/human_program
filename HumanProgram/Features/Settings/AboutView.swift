import SwiftUI

struct AboutView: View {
    @State private var showSudokuGate = false
    @State private var showDocument = false
    private let gateService = EasterEggGateService()
    // In a real flow, todayPage is injected. For now read from environment.
    @Environment(AppState.self) private var appState

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            List {
                Section {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Human Program")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(versionString)
                            .font(AppTypography.caption())
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section {
                    // Version row — double tap opens hidden document
                    HStack {
                        Text("Build")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showDocument = true }

                    // Developer name — double tap triggers easter egg (no visual affordance)
                    HStack {
                        Text("Developer")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("David Jurek")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        // Attempt gate reveal. If locked: silent haptic only.
                        // We pass nil for todayPage if not loaded — gate returns false safely.
                        let today = Calendar.current.startOfDay(for: Date())
                        // We don't have a live DailyPage reference here without a repo call,
                        // so the gate check is done via AppState completion:
                        // Build a synthetic page state from AppState for the check.
                        let tempPage = DailyPage(date: today)
                        tempPage.dayComplete = appState.streakStats.currentStreak > 0 || isCurrentDayComplete()
                        if gateService.shouldRevealGate(todayPage: tempPage, today: today) {
                            showSudokuGate = true
                        } else {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }

                    NavigationLink(destination: CatCornerView()) {
                        Text("Cat Corner")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }

                Section("Licenses") {
                    Text("This app uses only Apple frameworks and contains no third-party libraries. XcodeGen (MIT) is used only as a development tool and is not included in the app binary.")
                        .font(AppTypography.caption())
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showSudokuGate) {
            SudokuGateView()
        }
        .sheet(isPresented: $showDocument) {
            HiddenDocumentView()
        }
    }

    private func isCurrentDayComplete() -> Bool {
        // Lightweight check: currentStreak > 0 means today (the latest) is complete.
        // More accurate check requires a repo call; this is sufficient for the gate.
        appState.streakStats.currentStreak > 0
    }
}

// ── Cat Corner (placeholder until user provides photos) ───────────
struct CatCornerView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Photos coming soon")
                    .font(AppTypography.caption())
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .navigationTitle("Cat Corner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ── Hidden document view ──────────────────────────────────────────
struct HiddenDocumentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Universal Declaration of Human Rights")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.bottom, 4)
                    Text("Adopted by the UN General Assembly on 10 December 1948.")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.textSecondary)
                    Text(humanRightsExcerpt)
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textPrimary)
                        .lineSpacing(5)
                }
                .padding(24)
            }
            .background(AppColors.background)
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
