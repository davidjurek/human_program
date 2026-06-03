import Foundation

/// Weekday helpers using the app-wide encoding: **1=Sunday … 7=Saturday**
/// (matches iOS `Calendar`'s `.weekday` component and every feature in the app).
///
/// Centralizes the full-name table that was redeclared in `ScheduleRepository`,
/// `ExerciseSettingsView`, and `ExerciseRoutineEditorView`. Each call site keeps its
/// own fallback for an out-of-range value (e.g. "Day 3" vs "Exercise").
enum Weekday {
    /// Full English weekday names in `1=Sun … 7=Sat` order (index 0 = Sunday).
    /// Canonical table for the labels other screens currently redeclare inline.
    static let fullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Single-letter weekday labels in `1=Sun … 7=Sat` order (index 0 = Sunday).
    /// Note Sunday and Saturday both read "S", and Tuesday/Thursday both "T" — these
    /// are the display letters, not unique keys; index by weekday, never by letter.
    static let shortLetters = ["S", "M", "T", "W", "T", "F", "S"]

    /// Full English weekday name for `1...7`, or `nil` for an out-of-range value.
    static func fullName(_ weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        return fullNames[weekday - 1]
    }

    /// Single-letter label for `1...7`, or `nil` for an out-of-range value.
    static func shortLetter(_ weekday: Int) -> String? {
        guard (1...7).contains(weekday) else { return nil }
        return shortLetters[weekday - 1]
    }
}
