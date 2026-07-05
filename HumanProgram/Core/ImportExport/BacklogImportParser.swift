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
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ParsedBacklogRow(title: $0, project: nil, date: nil, notes: "") }
    }

    // MARK: - CSV (title, project, date, notes — optional header)

    public enum CSVResult: Equatable {
        case rejected(String)                       // whole file rejected
        case parsed([ParsedBacklogRow], skippedNoTitle: Int)
    }

    /// CSV columns in order: title, project, assigned date, notes. Only the title column
    /// is required — project, date, and notes are OPTIONAL trailing columns, so a row may
    /// have 1 to 4 columns and any missing trailing column is treated as blank. Dates
    /// accept YYYY-MM-DD, M/D/YYYY, or M-D-YYYY (see `parseYMD`). A leading header row
    /// ("title,project,date,notes") is also optional — if present it's ignored. Rows with
    /// no title are skipped (counted). The WHOLE file is rejected only if a row has MORE
    /// than 4 columns or a present date in none of the accepted formats.
    public static func parseCSV(_ csv: String) -> CSVResult {
        var lines = csv.split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !isBlank($0) }

        // Drop an optional leading header row — the import is positional, so a first
        // line of the column names is metadata, not data. [#header]
        if let first = lines.first, isHeaderRow(parseCSVLine(first)) {
            lines.removeFirst()
        }

        var rows: [ParsedBacklogRow] = []
        var skipped = 0

        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count <= 4 else {
                return .rejected("Too many columns — each row has at most 4 (title, project, date, notes).")
            }
            // Pad missing trailing columns: project/date/notes are optional.
            let padded = cols + Array(repeating: "", count: 4 - cols.count)
            let title = padded[0].trimmingCharacters(in: .whitespaces)
            let projectRaw = padded[1].trimmingCharacters(in: .whitespaces)
            let dateRaw = padded[2].trimmingCharacters(in: .whitespaces)
            let notes = padded[3]

            // A titleless row is skipped uniformly — check it BEFORE validating the
            // date so a blank row with a bad date doesn't reject the whole file. [#78]
            if title.isEmpty { skipped += 1; continue }

            var date: Date? = nil
            if !dateRaw.isEmpty {
                guard let d = parseYMD(dateRaw) else {
                    return .rejected("Date “\(dateRaw)” isn’t a recognized date (use YYYY-MM-DD or M/D/YYYY).")
                }
                date = d
            }
            rows.append(ParsedBacklogRow(title: title,
                                         project: projectRaw.isEmpty ? nil : projectRaw,
                                         date: date, notes: notes))
        }
        return .parsed(rows, skippedNoTitle: skipped)
    }

    /// The downloadable template (header + one example row). The header is OPTIONAL on
    /// import — it's accepted and ignored, so the template imports as-is.
    public static let csvTemplate =
        "title,project,date,notes\n" +
        "Buy groceries,Errands,2026-06-15,Milk and eggs\n"

    // MARK: - Helpers

    /// True for a line that's empty once leading/trailing whitespace and newlines are
    /// stripped — the single blank-line rule shared by the text and CSV parsers. [#80]
    static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True if a parsed line is the optional column-header row — the four expected column
    /// names in order, ignoring case and surrounding whitespace. The import is positional,
    /// so only this exact header (not arbitrary first lines) is treated as a header. A real
    /// data row would never match (its date column couldn't literally be "date").
    static func isHeaderRow(_ cols: [String]) -> Bool {
        let expected = ["title", "project", "date", "notes"]
        guard cols.count == expected.count else { return false }
        return zip(cols, expected).allSatisfy {
            $0.0.trimmingCharacters(in: .whitespaces).lowercased() == $0.1
        }
    }

    /// Minimal CSV line parser supporting double-quoted fields (with commas / escaped "").
    /// Steps through the string's own characters (no copied index array). [#76]
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var iter = line.makeIterator()
        var pending = iter.next()
        while let c = pending {
            // Look ahead one character so an escaped "" inside quotes can be detected.
            let next = iter.next()
            if inQuotes {
                if c == "\"" {
                    if next == "\"" { field.append("\""); pending = iter.next(); continue }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == "," { fields.append(field); field = "" }
                else { field.append(c) }
            }
            pending = next
        }
        fields.append(field)
        return fields
    }

    /// The accepted date formats, tried in order. Non-lenient parsing makes each one
    /// reject a string meant for another (e.g. "M/d/yyyy" can't parse "2026-07-05" because
    /// month 2026 is out of range), so trying them in sequence is unambiguous. Slash/dash
    /// dates are month-first (US) — "7/5/2026" is July 5. Cached: rebuilt formatters are
    /// expensive per row. [#161]
    private static let dateFormatters: [DateFormatter] = ["yyyy-MM-dd", "M/d/yyyy", "M-d-yyyy"].map { fmt in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = fmt
        f.isLenient = false
        return f
    }

    static func parseYMD(_ s: String) -> Date? {
        for f in dateFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
