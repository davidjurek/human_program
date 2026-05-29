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

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = [header]

        let sorted = items.sorted { $0.createdAt < $1.createdAt }
        for item in sorted {
            let id            = csvCell(item.id)
            let title         = csvCell(item.title)
            let notes         = csvCell(item.notes)
            let projectBucket = csvCell(item.project?.name ?? "")
            let assignedDate  = csvCell(item.assignedDate.map { dateFormatter.string(from: $0) } ?? "")
            let status        = csvCell(item.status.rawValue)
            let createdAt     = csvCell(isoFormatter.string(from: item.createdAt))
            let updatedAt     = csvCell(isoFormatter.string(from: item.updatedAt))

            let row = "\(id),\(title),\(notes),\(projectBucket),\(assignedDate),\(status),\(createdAt),\(updatedAt)"
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Suggested Filename

    func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "human-program-backlog-\(dateString).csv"
    }

    // MARK: - Private Helpers

    /// Wraps a cell value in double quotes and escapes any embedded double quotes.
    /// Prefixes cells that start with =, +, -, or @ with an apostrophe to prevent
    /// formula injection when opened in spreadsheet applications.
    private func csvCell(_ value: String) -> String {
        var sanitized = value

        // Injection defense: prefix cells that start with formula-trigger characters
        let injectionPrefixes: [Character] = ["=", "+", "-", "@"]
        if let firstChar = sanitized.first, injectionPrefixes.contains(firstChar) {
            sanitized = "'" + sanitized
        }

        // Escape embedded double quotes by doubling them
        sanitized = sanitized.replacingOccurrences(of: "\"", with: "\"\"")

        // Always wrap in double quotes for safe handling of commas and newlines
        return "\"\(sanitized)\""
    }
}
