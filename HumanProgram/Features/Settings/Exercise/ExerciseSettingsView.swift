import SwiftUI
import SwiftData
import DSKit

// Exercise routines list (Settings → Exercise). One routine per weekday
// (1=Sun … 7=Sat), always present. Built on the shared Settings convention:
// SettingsScreen container, open card-less rows, each pushing the routine editor.
struct ExerciseSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var allRoutines: [ExerciseRoutine]

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
        SettingsScreen(centered: true) {
            if allRoutines.isEmpty {
                DSText("Setting up routines…")
                    .dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                ForEach(sortedRoutines) { routine in
                    ExerciseRoutineRow(routine: routine, weekdayName: weekdayName(routine))
                }
            }
        }
        .onAppear(perform: ensureRoutines)
    }

    private func weekdayName(_ routine: ExerciseRoutine) -> String {
        let weekday = routine.recurrenceRule.weekdays.first ?? 0
        return Self.fullWeekdayName[weekday] ?? "Exercise"
    }

    private func ensureRoutines() {
        let repo = ExerciseRepository(context: context)
        try? repo.ensureSevenWeekdayRoutines()
    }
}

/// One routine row: weekday as the title, the routine name + exercise count as
/// the subtitle. Pushes the editor. (Same open-row look as the planning lists.)
private struct ExerciseRoutineRow: View {
    let routine: ExerciseRoutine
    let weekdayName: String

    private var subtitle: String {
        let raw = routine.name.trimmingCharacters(in: .whitespaces)
        // A name equal to the weekday default counts as "no custom name".
        let custom = (raw == weekdayName) ? "" : raw
        let count = routine.items.count
        let countLabel = count == 1 ? "1 exercise" : "\(count) exercises"
        let namePart = custom.isEmpty ? "Empty" : custom
        return "\(namePart) · \(countLabel)"
    }

    var body: some View {
        NavigationLink {
            ExerciseRoutineEditorView(routine: routine)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                DSText(weekdayName).dsTextStyle(.title3)
                DSText(subtitle).dsTextStyle(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 52)
    }
}
