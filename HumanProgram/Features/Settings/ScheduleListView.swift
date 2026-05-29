import SwiftUI

// Stub screen for the Schedule settings section.
// Full schedule block editor is a future milestone.
struct ScheduleListView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "clock")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(AppColors.textTertiary)
                Text("Schedule")
                    .font(AppTypography.pageTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text("Editor coming soon")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
