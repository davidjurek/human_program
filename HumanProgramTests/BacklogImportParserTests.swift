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

    func test_csv_threeColumns_notesTreatedAsBlank() {
        // title,project,date with the notes column omitted entirely.
        let csv = "Buy groceries,Errands,2026-06-15"
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.title, "Buy groceries")
        XCTAssertEqual(parsed.first?.project, "Errands")
        XCTAssertEqual(parsed.first?.notes, "", "Missing notes column should be blank")
        XCTAssertNotNil(parsed.first?.date)
    }

    func test_csv_titleOnly_singleColumn_works() {
        let csv = "Just a title"
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.title, "Just a title")
        XCTAssertNil(parsed.first?.project)
        XCTAssertNil(parsed.first?.date)
    }

    func test_csv_moreThanFourColumns_rejects() {
        let csv = "Title,Project,2026-06-15,notes,extra"
        if case .rejected = BacklogImportParser.parseCSV(csv) {
            // expected
        } else {
            XCTFail("A row with 5 columns should be rejected")
        }
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

    // MARK: - Date formats

    func test_parseYMD_isoFormat() {
        XCTAssertNotNil(BacklogImportParser.parseYMD("2026-07-05"))
    }

    func test_parseYMD_usSlashFormat() {
        // 7/5/2026 and its zero-padded form should both parse (month-first).
        XCTAssertNotNil(BacklogImportParser.parseYMD("7/5/2026"))
        XCTAssertNotNil(BacklogImportParser.parseYMD("07/05/2026"))
    }

    func test_parseYMD_usDashFormat() {
        XCTAssertNotNil(BacklogImportParser.parseYMD("7-5-2026"))
    }

    func test_parseYMD_slashDate_isMonthFirst() {
        // 3/4/2026 must be March 4, not April 3.
        guard let d = BacklogImportParser.parseYMD("3/4/2026") else {
            return XCTFail("3/4/2026 should parse")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        XCTAssertEqual(cal.component(.month, from: d), 3)
        XCTAssertEqual(cal.component(.day, from: d), 4)
    }

    func test_parseYMD_rejectsGarbage() {
        XCTAssertNil(BacklogImportParser.parseYMD("June 15"))
        XCTAssertNil(BacklogImportParser.parseYMD("2026/13/40"))
    }

    func test_csv_usSlashDateRow_imports() {
        // The real-world case: 3-column rows with US slash dates and no notes column.
        let csv = """
        Work on speech,,7/5/2026
        Look into run clubs,,7/7/2026
        """
        let parsed = rows(BacklogImportParser.parseCSV(csv))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertNotNil(parsed.first?.date)
    }
}
