import Foundation

struct TaskHistoryCSVExporter {

    // MARK: - Export

    /// Returns a UTF-8 CSV string of all tasks across the provided daily pages.
    /// One row per DailyPageTask, sorted by page date ascending, then sortOrder ascending.
    ///
    /// Columns:
    ///   date, day_complete, task_id, task_title, task_notes,
    ///   source_type, completed, completed_at, sort_order
    func export(pages: [DailyPage]) -> String {
        let header = "date,day_complete,task_id,task_title,task_notes,source_type,completed,completed_at,sort_order"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        // Sort pages by date ascending
        let sortedPages = pages.sorted { $0.date < $1.date }

        var lines: [String] = [header]

        for page in sortedPages {
            let pageDateString   = dateFormatter.string(from: page.date)
            let dayCompleteValue = page.dayComplete ? "true" : "false"

            // Sort tasks within the page by sortOrder
            let sortedTasks = page.tasks.sorted { $0.sortOrder < $1.sortOrder }

            for task in sortedTasks {
                let date        = csvCell(pageDateString)
                let dayComplete = csvCell(dayCompleteValue)
                let taskId      = csvCell(task.id)
                let taskTitle   = csvCell(task.title)
                let taskNotes   = csvCell(task.notes)
                let sourceType  = csvCell(task.sourceType.rawValue)
                let completed   = csvCell(task.completed ? "true" : "false")
                let completedAt = csvCell(task.completedAt.map { isoFormatter.string(from: $0) } ?? "")
                let sortOrder   = csvCell(String(task.sortOrder))

                let row = "\(date),\(dayComplete),\(taskId),\(taskTitle),\(taskNotes),\(sourceType),\(completed),\(completedAt),\(sortOrder)"
                lines.append(row)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Suggested Filename

    func suggestedFilename(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let fromString = formatter.string(from: from)
        let toString   = formatter.string(from: to)
        return "human-program-task-history-\(fromString)-to-\(toString).csv"
    }

    // MARK: - Private Helpers

    /// Wraps a cell value in double quotes, escapes embedded double quotes,
    /// and prefixes injection-trigger characters (=, +, -, @) with an apostrophe.
    private func csvCell(_ value: String) -> String {
        var sanitized = value

        let injectionPrefixes: [Character] = ["=", "+", "-", "@"]
        if let firstChar = sanitized.first, injectionPrefixes.contains(firstChar) {
            sanitized = "'" + sanitized
        }

        sanitized = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(sanitized)\""
    }
}
