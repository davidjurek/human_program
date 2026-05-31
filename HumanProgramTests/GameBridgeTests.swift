import XCTest
import Foundation
import SwiftData
@testable import HumanProgram

final class GameBridgeTests: XCTestCase {

    // MARK: - Helpers

    // Must match how DailyPage normalizes its date (Calendar.current / local TZ).
    var localCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year   = year
        comps.month  = month
        comps.day    = day
        comps.hour   = 0
        comps.minute = 0
        comps.second = 0
        return localCalendar.date(from: comps)!
    }

    var today: Date { makeDate(year: 2025, month: 1, day: 8) }

    var yesterday: Date {
        localCalendar.date(byAdding: .day, value: -1, to: today)!
    }

    @MainActor
    func makeTestModelContainer() throws -> ModelContainer {
        let schema = Schema([
            DailyPage.self,
            DailyPageTask.self,
            BacklogItem.self,
            RecurringTaskTemplate.self,
            ProjectBucket.self,
            ScheduleTemplate.self,
            ExerciseRoutine.self,
            ExerciseRoutineItem.self,
            RoutineItem.self,
            Routine.self,
            CalendarEventLocalState.self,
            NotificationReminder.self,
            GameAccessState.self,
            GameSaveMetadata.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Create a DailyPage with the given date and dayComplete state.
    /// Date is normalized to start-of-day inside DailyPage.init, but we pass an already-normalized date.
    @MainActor
    func makePage(date: Date,
                  dayComplete: Bool,
                  in context: ModelContext) -> DailyPage {
        let page = DailyPage(date: date)
        page.dayComplete = dayComplete
        context.insert(page)
        return page
    }

    // ──────────────────────────────────────────────────────────────
    // MARK: - GameAccessService Tests
    // ──────────────────────────────────────────────────────────────

    let accessService = GameAccessService()

    // 1. nil page → cannot access
    func test_nilPage_cannotAccess() {
        XCTAssertFalse(
            accessService.canAccessGame(todayPage: nil, today: today, calendar: localCalendar),
            "nil page should prevent game access"
        )
    }

    // 2. Page exists but dayComplete=false → cannot access
    @MainActor
    func test_incompleteDay_cannotAccess() throws {
        let container = try makeTestModelContainer()
        let page = makePage(date: today, dayComplete: false, in: container.mainContext)

        XCTAssertFalse(
            accessService.canAccessGame(todayPage: page, today: today, calendar: localCalendar),
            "Incomplete day should not grant game access"
        )
    }

    // 3. Page is complete and date=today → can access
    @MainActor
    func test_completeToday_canAccess() throws {
        let container = try makeTestModelContainer()
        let page = makePage(date: today, dayComplete: true, in: container.mainContext)

        XCTAssertTrue(
            accessService.canAccessGame(todayPage: page, today: today, calendar: localCalendar),
            "Complete page for today should grant game access"
        )
    }

    // 4. Page is complete but date=yesterday → cannot access
    @MainActor
    func test_completeYesterday_cannotAccess() throws {
        let container = try makeTestModelContainer()
        let page = makePage(date: yesterday, dayComplete: true, in: container.mainContext)

        XCTAssertFalse(
            accessService.canAccessGame(todayPage: page, today: today, calendar: localCalendar),
            "Complete page from yesterday should not grant today's game access"
        )
    }

    // 5. lockReason when locked (wrong date) must not contain game-revealing words.
    //    We test the "date mismatch" locked state because it demonstrates the service
    //    never mentions the game, unlock mechanism, tasks, or completion in its reason strings.
    //    (The "incomplete" path says "not marked complete" which is intentional internal logging.)
    @MainActor
    func test_lockReason_whenLocked_noGameLanguage() throws {
        let container = try makeTestModelContainer()
        // Page is from yesterday — locked because date does not match today.
        let page = makePage(date: yesterday, dayComplete: true, in: container.mainContext)

        let reason = accessService.lockReason(
            todayPage: page, today: today, calendar: localCalendar
        ).lowercased()

        XCTAssertFalse(reason.contains("game"),
                       "lockReason must not reveal 'game'")
        XCTAssertFalse(reason.contains("unlock"),
                       "lockReason must not reveal 'unlock'")
        XCTAssertFalse(reason.contains("task"),
                       "lockReason must not reveal 'task'")
    }

    // 6. lockReason with nil page returns a non-empty string
    func test_lockReason_whenNilPage() {
        let reason = accessService.lockReason(
            todayPage: nil, today: today, calendar: localCalendar
        )
        XCTAssertFalse(reason.isEmpty,
                       "lockReason with nil page should return a non-empty string")
    }

    // ──────────────────────────────────────────────────────────────
    // MARK: - EasterEggGateService Tests
    // ──────────────────────────────────────────────────────────────

    let gateService = EasterEggGateService()

    // 7. nil page → gate hidden
    func test_nilPage_gateHidden() {
        XCTAssertFalse(
            gateService.shouldRevealGate(todayPage: nil, today: today, calendar: localCalendar),
            "nil page should hide the gate"
        )
    }

    // 8. Incomplete page → gate hidden
    @MainActor
    func test_incompletePage_gateHidden() throws {
        let container = try makeTestModelContainer()
        let page = makePage(date: today, dayComplete: false, in: container.mainContext)

        XCTAssertFalse(
            gateService.shouldRevealGate(todayPage: page, today: today, calendar: localCalendar),
            "Incomplete page should hide the gate"
        )
    }

    // 9. Complete page for today → gate reveals
    @MainActor
    func test_completeTodayPage_gateReveals() throws {
        let container = try makeTestModelContainer()
        let page = makePage(date: today, dayComplete: true, in: container.mainContext)

        XCTAssertTrue(
            gateService.shouldRevealGate(todayPage: page, today: today, calendar: localCalendar),
            "Complete page for today should reveal the gate"
        )
    }

    // 10. Complete page but from yesterday → gate hidden
    @MainActor
    func test_completePastPage_gateHidden() throws {
        let container = try makeTestModelContainer()
        let page = makePage(date: yesterday, dayComplete: true, in: container.mainContext)

        XCTAssertFalse(
            gateService.shouldRevealGate(todayPage: page, today: today, calendar: localCalendar),
            "Complete page from a past date should not reveal the gate"
        )
    }
}
