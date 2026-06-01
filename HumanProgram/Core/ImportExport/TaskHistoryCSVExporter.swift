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

        // Sort pages by date ascending
        let sortedPages = pages.sorted { $0.date < $1.date }

        var lines: [String] = [header]

        for page in sortedPages {
            let pageDateString   = CSV.posixDate.string(from: page.date)
            let dayCompleteValue = page.dayComplete ? "true" : "false"

            // Sort tasks within the page by sortOrder
            let sortedTasks = page.tasks.sorted { $0.sortOrder < $1.sortOrder }

            for task in sortedTasks {
                let date        = CSV.cell(pageDateString)
                let dayComplete = CSV.cell(dayCompleteValue)
                let taskId      = CSV.cell(task.id)
                let taskTitle   = CSV.cell(task.title)
                let taskNotes   = CSV.cell(task.notes)
                let sourceType  = CSV.cell(task.sourceType.rawValue)
                let completed   = CSV.cell(task.completed ? "true" : "false")
                let completedAt = CSV.cell(task.completedAt.map { CSV.iso.string(from: $0) } ?? "")
                let sortOrder   = CSV.cell(String(task.sortOrder))

                let row = "\(date),\(dayComplete),\(taskId),\(taskTitle),\(taskNotes),\(sourceType),\(completed),\(completedAt),\(sortOrder)"
                lines.append(row)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Suggested Filename

    func suggestedFilename(from: Date, to: Date) -> String {
        let fromString = CSV.posixDate.string(from: from)
        let toString   = CSV.posixDate.string(from: to)
        return "human-program-task-history-\(fromString)-to-\(toString).csv"
    }
}
