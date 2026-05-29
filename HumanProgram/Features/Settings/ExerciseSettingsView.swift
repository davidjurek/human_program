import SwiftUI

// Stub screen for the Exercise settings section.
// Full exercise block editor is a future milestone.
struct ExerciseSettingsView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(AppColors.textTertiary)
                Text("Exercise")
                    .font(AppTypography.pageTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text("Editor coming soon")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}
