import XCTest
import SwiftData
@testable import HumanProgram

final class TodayDifferencesTests: XCTestCase {

    // A recurring template + an assigned backlog item both belong today, but the page
    // has NEITHER (both deleted) → both surface as differences.
    @MainActor
    func test_missingRecurringAndBacklog_areReported() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())

        let page = DailyPage(date: today)
        context.insert(page)

        let rec = RecurringTaskInput(id: "r1", title: "Meditate", notes: "", rule: .daily(), active: true)
        let back = BacklogTaskInput(id: "b1", title: "Pay rent", assignedDate: today, status: .backlog)

        let diffs = TodayDifferenceEngine.taskDifferences(page: page, recurring: [rec], backlog: [back], schedule: [])
        XCTAssertEqual(diffs.count, 2)
        XCTAssertTrue(diffs.contains { $0.kind == .recurring && $0.sourceId == "r1" })
        XCTAssertTrue(diffs.contains { $0.kind == .backlog && $0.sourceId == "b1" })
    }

    // An item that IS present on the page is not a difference.
    @MainActor
    func test_presentItem_isNotADifference() throws {
        let container = try makeTestModelContainer()
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())

        let page = DailyPage(date: today)
        context.insert(page)
        let t = DailyPageTask(title: "Meditate", sourceType: .recurring, sourceId: "r1", sortOrder: 0)
        t.page = page
        page.tasks.append(t)
        context.insert(t)

        let rec = RecurringTaskInput(id: "r1", title: "Meditate", notes: "", rule: .daily(), active: true)
        let diffs = TodayDifferenceEngine.taskDifferences(page: page, recurring: [rec], backlog: [], schedule: [])
        XCTAssertTrue(diffs.isEmpty, "An item present on the page must not be reported as a difference")
    }
}
