import Foundation

/// One parsed backlog candidate from a text/CSV import (not yet imported).
public struct ParsedBacklogRow: Identifiable, Equatable {
    public let id = UUID()
    public var title: String
    public var project: String?
    public var date: Date?
    public var notes: String
}

/// Pure parsing for the backlog text and CSV importers. No SwiftData.
public enum BacklogImportParser {

    // MARK: - Text (titles only)

    /// Each non-blank line becomes one title-only row. Blank lines are ignored.
    public static func parseText(_ text: String) -> [ParsedBacklogRow] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ParsedBacklogRow(title: $0, project: nil, date: nil, notes: "") }
    }

    // MARK: - CSV (title, project, date, notes — headerless)

    public enum CSVResult: Equatable {
        case rejected(String)                       // whole file rejected
        case parsed([ParsedBacklogRow], skippedNoTitle: Int)
    }

    /// Headerless CSV: exactly 4 columns (title, project, assigned date YYYY-MM-DD,
    /// notes). Rows with no title are skipped (counted). The WHOLE file is rejected
    /// if any row has the wrong column count or a present date not in YYYY-MM-DD.
    public static func parseCSV(_ csv: String) -> CSVResult {
        let lines = csv.split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var rows: [ParsedBacklogRow] = []
        var skipped = 0

        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count == 4 else {
                return .rejected("Wrong number of columns — each row needs exactly 4 (title, project, date, notes).")
            }
            let title = cols[0].trimmingCharacters(in: .whitespaces)
            let projectRaw = cols[1].trimmingCharacters(in: .whitespaces)
            let dateRaw = cols[2].trimmingCharacters(in: .whitespaces)
            let notes = cols[3]

            var date: Date? = nil
            if !dateRaw.isEmpty {
                guard let d = parseYMD(dateRaw) else {
                    return .rejected("Date “\(dateRaw)” is not in YYYY-MM-DD format.")
                }
                date = d
            }
            if title.isEmpty { skipped += 1; continue }
            rows.append(ParsedBacklogRow(title: title,
                                         project: projectRaw.isEmpty ? nil : projectRaw,
                                         date: date, notes: notes))
        }
        return .parsed(rows, skippedNoTitle: skipped)
    }

    /// The downloadable template (header + one example row). The imported file must
    /// be HEADERLESS — the header is for reference only.
    public static let csvTemplate =
        "title,project,date,notes\n" +
        "Buy groceries,Errands,2026-06-15,Milk and eggs\n"

    // MARK: - Helpers

    /// Minimal CSV line parser supporting double-quoted fields (with commas / escaped "").
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == "," { fields.append(field); field = "" }
                else { field.append(c) }
            }
            i += 1
        }
        fields.append(field)
        return fields
    }

    static func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f.date(from: s)
    }
}
