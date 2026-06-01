import Foundation

/// Shared CSV-writing helpers used by both `BacklogCSVExporter` and `TaskHistoryCSVExporter`.
///
/// The cell sanitizer and the two date formatters were byte-for-byte identical in both
/// exporters; a tightening of the formula-injection rule had to be made in two places or one
/// export path would silently lose the protection.
enum CSV {

    /// Wraps a cell value in double quotes, escapes embedded double quotes by doubling them,
    /// and prefixes cells starting with a formula-trigger character (`=`, `+`, `-`, `@`) with
    /// an apostrophe to prevent CSV injection when opened in spreadsheet apps.
    static func cell(_ value: String) -> String {
        var sanitized = value

        let injectionPrefixes: [Character] = ["=", "+", "-", "@"]
        if let firstChar = sanitized.first, injectionPrefixes.contains(firstChar) {
            sanitized = "'" + sanitized
        }

        sanitized = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(sanitized)\""
    }

    /// `yyyy-MM-dd`, POSIX locale — for date-only columns and filenames.
    static let posixDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// ISO 8601 combined date-time — for timestamp columns.
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
