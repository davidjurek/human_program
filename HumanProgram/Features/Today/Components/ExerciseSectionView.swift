import SwiftUI

struct ExerciseSectionView: View {
    let routine: ExerciseRoutine?

    var body: some View {
        if let routine = routine {
            routineContent(routine)
        } else {
            noRoutineView
        }
    }

    // MARK: - No routine

    private var noRoutineView: some View {
        Text("No exercise routine for this day")
            .font(AppTypography.caption())
            .foregroundStyle(AppColors.textTertiary)
            .padding(.bottom, 4)
    }

    // MARK: - Routine content

    @ViewBuilder
    private func routineContent(_ routine: ExerciseRoutine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Show name if non-empty
            let displayName = routine.name.trimmingCharacters(in: .whitespaces)
            if !displayName.isEmpty {
                Text(displayName)
                    .font(AppTypography.sectionHeader())
                    .foregroundStyle(AppColors.textSecondary)
                    .kerning(0.3)
                    .padding(.bottom, 2)
            }

            if routine.items.isEmpty {
                Text("No exercises added yet")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                let sorted = routine.items.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, item in
                    exerciseItemRow(item: item, number: index + 1)
                }
            }
        }
    }

    // MARK: - Item row

    private func exerciseItemRow(item: ExerciseRoutineItem, number: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Number
            Text("\(number).")
                .font(AppTypography.taskMeta())
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 20, alignment: .trailing)
                .padding(.top, 1)

            // Text
            Text(item.text)
                .font(AppTypography.taskTitle())
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // Sets × reps badge
            if let sets = item.sets, let reps = item.reps {
                Text("\(sets)×\(reps)")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.accentOrange)
            } else if let sets = item.sets {
                Text("\(sets) sets")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.accentOrange)
            } else if let reps = item.reps {
                Text("\(reps) reps")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.accentOrange)
            }
        }
        .padding(.vertical, 3)
    }
}
