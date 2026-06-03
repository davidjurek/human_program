import SwiftUI
import DSKit

// Full-screen interstitials shown over the whole app (status bar stays visible):
// the one-time Welcome screen on first install, and the confirmation screens after
// a factory reset or a backup restore. Penguin logo centered, one full-width
// light-blue rectangle button.
struct AppInterstitialView: View {
    enum Mode { case welcome, reset, restored }
    let mode: Mode
    let onAction: () -> Void

    private var title: String {
        switch mode {
        case .welcome:  return "Welcome to the Human Program!"
        case .reset:    return "Human Program has been reset back to its factory state."
        case .restored: return "The backup has been restored."
        }
    }
    private var buttonLabel: String {
        mode == .welcome ? "Start" : "OK"
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 0) {
                Spacer()
                logo
                Spacer().frame(height: 28)
                // Plain Text (not DSText) so multi-line CENTER alignment actually
                // applies — DSText renders leading-aligned regardless. title2 ≈ 22.
                Text(title)
                    .font(appFont(22))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                Spacer()
                OnboardingPrimaryButton(title: buttonLabel, action: onAction)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let img = UIImage(named: "PenguinIcon") {
            Image(uiImage: img).resizable().scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            // DSKit icon instead of a raw .system(size:) glyph. [#101]
            DSImageView(systemName: "figure.stand", size: 90, tint: .color(.primary))
        }
    }
}

/// Shared onboarding layout: a frozen `header` over a scrolling `content`, on the
/// lavender gradient background. Used by the onboarding presentations of Terms and
/// Tutorial so the chrome (paddings, freeze-over-scroll) lives in ONE place. [#166]
struct OnboardingScrollScaffold<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 0) {
                // Frozen header — stays put while the body scrolls.
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    .padding(.bottom, 18)
                ScrollView {
                    content
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

/// Full-width light-blue onboarding CTA. Shared by the interstitials and the
/// permissions screen so the accent + shape live in ONE place. [#29]
struct OnboardingPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(appFont(20))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(enabled ? appOnboardingBlue : appOnboardingBlue.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .a11yTapBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(!enabled)
    }
}
