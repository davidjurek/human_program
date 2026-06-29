import XCTest
@testable import HumanProgram

final class BacklogImportParserTests: XCTestCase {

    // Helper: pull the rows out of a .parsed result, failing otherwise.
    private func rows(_ result: BacklogImportParser.CSVResult,
                      file: StaticString = #file, line: UInt = #line) -> [ParsedBacklogRow] {
        guard case let .parsed(rows, _) = result else {
            XCTFail("Expected .parsed, got \(result)", file: file, line: line)
            return []
        }
        return rows
    }

    func test_csv_withHeader_isAccepted_andHeaderIgnored() {
        let csv = """
        title,project,date,notes
        Buy groceries,Errands,2026-06-15,Milk
        """
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 1, "Header should be ignored, leaving one data row")
        XCTAssertEqual(parsed.first?.title, "Buy groceries")
        XCTAssertEqual(parsed.first?.project, "Errands")
    }

    func test_csv_withoutHeader_stillWorks() {
        let csv = "Buy groceries,Errands,2026-06-15,Milk"
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.title, "Buy groceries")
    }

    func test_csv_headerDetection_isCaseAndSpaceInsensitive() {
        let csv = """
        Title , Project , Date , Notes
        Task one,,2026-06-15,
        """
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 1, "A header with odd case/spacing should still be skipped")
        XCTAssertEqual(parsed.first?.title, "Task one")
    }

    func test_csv_realFirstRowIsNotMistakenForHeader() {
        // A genuine data row that happens to start with "title" but isn't the full header
        // set must NOT be skipped.
        let csv = "title of my task,Work,2026-06-15,some notes"
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.title, "title of my task")
    }

    func test_csv_badDateOnDataRow_stillRejects() {
        let csv = """
        title,project,date,notes
        Buy groceries,Errands,June 15,Milk
        """
        if case .rejected = BacklogImportParser.parseCSV(csv) {
            // expected
        } else {
            XCTFail("A real bad date should still reject the file")
        }
    }
}
