import Foundation

/// Weekday helpers using the app-wide encoding: **1=Sunday … 7=Saturday**
/// (matches iOS `Calendar`'s `.weekday` component and every feature in the app).
///
/// Centralizes the full-name table that was redeclared in `ScheduleRepository`,
/// `ExerciseSettingsView`, and `ExerciseRoutineEditorView`. Each call site keeps its
/// own fallback for an out-of-range value (e.g. "Day 3" vs "Exercise").
enum Weekday {
    /// Full English weekday name for `1...7`, or `nil` for an out-of-range value.
    static func fullName(_ weekday: Int) -> String? {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return nil
        }
    }
}
