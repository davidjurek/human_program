import SwiftUI

struct DateHeaderView: View {
    let date: Date
    let isToday: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    let onPickerRequested: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 36, height: 36)
            }

            Button(action: onPickerRequested) {
                Text(formatDate(date))
                    .font(AppTypography.dateLabel())
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 36, height: 36)
            }

            if !isToday {
                Button(action: onToday) {
                    Text("Today")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Button(action: onPickerRequested) {
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
}
