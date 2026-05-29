import SwiftUI
import SwiftData

struct ExerciseSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var allRoutines: [ExerciseRoutine]

    @State private var selectedRoutine: ExerciseRoutine? = nil

    // Short weekday abbreviation for display
    private static let shortWeekdayName: [Int: String] = [
        1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed",
        5: "Thu", 6: "Fri", 7: "Sat"
    ]

    // Full weekday name for the sheet title
    private static let fullWeekdayName: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    /// Sorted by primary weekday (1–7).
    private var sortedRoutines: [ExerciseRoutine] {
        allRoutines.sorted {
            ($0.recurrenceRule.weekdays.first ?? 0) < ($1.recurrenceRule.weekdays.first ?? 0)
        }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if allRoutines.isEmpty {
                ProgressView()
                    .tint(AppColors.textTertiary)
            } else {
                routineList
            }
        }
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRoutine) { routine in
            ExerciseRoutineEditorView(routine: routine)
        }
        .onAppear {
            ensureRoutines()
        }
    }

    // MARK: - List

    private var routineList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedRoutines) { routine in
                    routineRow(routine)
                    Divider()
                        .padding(.leading, 64)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func routineRow(_ routine: ExerciseRoutine) -> some View {
        Button {
            selectedRoutine = routine
        } label: {
            HStack(spacing: 12) {
                // Left: short weekday abbreviation
                let weekday = routine.recurrenceRule.weekdays.first ?? 0
                Text(Self.shortWeekdayName[weekday] ?? "—")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 36, alignment: .leading)
                    .padding(.leading, 16)

                // Middle: name + item count
                VStack(alignment: .leading, spacing: 2) {
                    let displayName = routine.name.trimmingCharacters(in: .whitespaces)
                    Text(displayName.isEmpty ? "Rest day" : displayName)
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textPrimary)

                    let count = routine.items.count
                    let countLabel = count == 0
                        ? "No exercises"
                        : count == 1 ? "1 exercise" : "\(count) exercises"
                    Text(countLabel)
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                // Right: chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Setup

    private func ensureRoutines() {
        let repo = ExerciseRepository(context: context)
        try? repo.ensureSevenWeekdayRoutines()
    }
}
