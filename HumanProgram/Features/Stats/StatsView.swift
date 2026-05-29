import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        StatCardView(label: "Current Streak", value: "\(appState.streakStats.currentStreak)", unit: "days", color: AppColors.accentGreen)
                        StatCardView(label: "Longest Streak", value: "\(appState.streakStats.longestStreak)", unit: "days", color: AppColors.accent)
                    }
                    HStack(spacing: 16) {
                        StatCardView(label: "Days Tracked", value: "\(appState.streakStats.totalTrackedDays)", unit: "days", color: AppColors.textSecondary)
                        StatCardView(label: "Complete Days", value: "\(appState.streakStats.totalCompleteDays)", unit: "days", color: AppColors.accentOrange)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatCardView: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                Text(unit)
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
