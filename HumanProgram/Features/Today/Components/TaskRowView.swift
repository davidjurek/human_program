import SwiftUI

struct TaskRowView: View {
    let task: DailyPageTask
    let onToggle: () -> Void
    var showMeta: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            task.completed ? AppColors.accentGreen : AppColors.textTertiary,
                            lineWidth: task.completed ? 0 : 1.5
                        )
                        .background(
                            Circle().fill(task.completed ? AppColors.accentGreen : Color.clear)
                        )
                        .frame(width: 24, height: 24)
                    if task.completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(task.completed ? AppColors.textTertiary : AppColors.textPrimary)
                    .strikethrough(task.completed, color: AppColors.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if showMeta {
                    HStack(spacing: 8) {
                        if task.sourceType != .manual {
                            Text(task.sourceType.rawValue.capitalized)
                                .font(AppTypography.taskMeta())
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(task.completed ? AppColors.taskComplete : Color.clear)
        .contentShape(Rectangle())
    }
}
