import SwiftUI

// Stub screen for the Recurring Tasks settings section.
// Full recurring task editor is a future milestone.
struct RecurringTasksView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "repeat")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(AppColors.textTertiary)
                Text("Recurring Tasks")
                    .font(AppTypography.pageTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text("Editor coming soon")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("Recurring Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }
}
