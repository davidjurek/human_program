import Foundation

struct BacklogCSVExporter {

    // MARK: - Export

    /// Returns a UTF-8 CSV string for the provided backlog items.
    /// Header: id,title,notes,project_bucket,assigned_date,status,created_at,updated_at
    /// - Date fields (assignedDate) use yyyy-MM-dd format.
    /// - Timestamp fields (createdAt, updatedAt) use ISO 8601 combined date-time.
    /// - Empty optional fields produce an empty cell, never the string "null".
    /// - Cells that start with = + - @ are prefixed with ' to prevent CSV injection.
    func export(items: [BacklogItem]) -> String {
        let header = "id,title,notes,project_bucket,assigned_date,status,created_at,updated_at"

        var lines: [String] = [header]

        let sorted = items.sorted { $0.createdAt < $1.createdAt }
        for item in sorted {
            let id            = CSV.cell(item.id)
            let title         = CSV.cell(item.title)
            let notes         = CSV.cell(item.notes)
            let projectBucket = CSV.cell(item.project?.name ?? "")
            let assignedDate  = CSV.cell(item.assignedDate.map { CSV.posixDate.string(from: $0) } ?? "")
            let status        = CSV.cell(item.status.rawValue)
            let createdAt     = CSV.cell(CSV.iso.string(from: item.createdAt))
            let updatedAt     = CSV.cell(CSV.iso.string(from: item.updatedAt))

            let row = "\(id),\(title),\(notes),\(projectBucket),\(assignedDate),\(status),\(createdAt),\(updatedAt)"
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Suggested Filename

    func suggestedFilename() -> String {
        let dateString = CSV.posixDate.string(from: Date())
        return "human-program-backlog-\(dateString).csv"
    }
}
