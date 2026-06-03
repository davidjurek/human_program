import SwiftUI
import DSKit

/// The reference-only Exercise section of the Today screen, extracted from the
/// TodayView monolith. Read-only: it lists the day's routine items (bullet + name
/// + sets/reps), or a centred "Nothing for today" when the day has no routine. [#33]
struct TodayExerciseSection: View {
    let routine: ExerciseRoutine?

    private var isEmpty: Bool { routine?.items.isEmpty ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSText("Exercise").dsTextStyle(.headline)
            VStack(alignment: .leading, spacing: 8) {
                if let routine, !routine.items.isEmpty {
                    ForEach(routine.items.sorted { $0.sortOrder < $1.sortOrder }) { item in
                        HStack(spacing: 10) {
                            DSText("•").dsTextStyle(.body)
                            DSText(item.text).dsTextStyle(.body)
                            Spacer()
                            if let s = item.sets, let r = item.reps {
                                DSText("\(s) × \(r)").dsTextStyle(.subheadline)
                            } else if let s = item.sets {
                                DSText("\(s) sets").dsTextStyle(.subheadline)
                            } else if let r = item.reps {
                                DSText("\(r) reps").dsTextStyle(.subheadline)
                            }
                        }
                    }
                } else {
                    // Centered within the content area's empty min-height. [#5]
                    DSText("Nothing for today")
                        .dsTextStyle(.subheadline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            // Empty content area ≈ the empty Tasks section height (header + ~100). [#5]
            .frame(maxWidth: .infinity,
                   minHeight: isEmpty ? 100 : 0,
                   alignment: isEmpty ? .center : .leading)
        }
    }
}
