import XCTest
import SwiftData
import Foundation
@testable import HumanProgram

/// Verifies that a .hprgm export captures the TRUE full app state and that an
/// import faithfully restores it — every model (minus the game), relationships,
/// past-locked snapshots, and the user's UserDefaults preferences.
@MainActor
final class HprgmBackupRoundTripTests: XCTestCase {

    private let settingKeys = [
        "settings.fontChoice", "settings.fontSizeStep", "settings.appearanceMode",
        "settings.appIcon", "settings.bgLight", "settings.bgDark",
        "settings.dateFormat", "settings.timeFormat", "selectedCalendarIds"
    ]
    private var savedDefaults: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for k in settingKeys { savedDefaults[k] = UserDefaults.standard.object(forKey: k) }
    }
    override func tearDown() {
        for k in settingKeys {
            if let v = savedDefaults[k] ?? nil { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
        super.tearDown()
    }

    func testFullExportImportRoundTripRestoresEverything() throws {
        // ── Source state ────────────────────────────────────────────────
        let srcContainer = try makeTestModelContainer()
        let src = ModelContext(srcContainer)

        let project = ProjectBucket(name: "Health")
        src.insert(project)

        let backlog = BacklogItem(title: "Buy vitamins")
        backlog.notes = "from the pharmacy"
        backlog.assignedDate = Calendar.current.startOfDay(for: Date())
        backlog.project = project
        src.insert(backlog)

        let recurring = RecurringTaskTemplate(title: "Meditate", rule: .daily())
        recurring.notes = "10 minutes"
        src.insert(recurring)

        let exercise = ExerciseRoutine(name: "Morning", rule: RecurrenceRule(frequency: .everyDay))
        src.insert(exercise)
        let exItem = ExerciseRoutineItem(text: "Pushups", sortOrder: 0)
        exItem.sets = 3; exItem.reps = 12; exItem.routine = exercise
        src.insert(exItem)

        let schedule = ScheduleTemplate(name: "Weekday")
        schedule.assignedWeekdays = [2, 3, 4, 5, 6]
        schedule.blocks = [ScheduleBlock(title: "Sleep", startMinuteOfDay: 1290, endMinuteOfDay: 330, sortOrder: 0)]
        src.insert(schedule)

        // A past-LOCKED page (the critical fidelity case).
        let pastDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let page = DailyPage(date: pastDate, createdAutomatically: true)
        page.isPastLocked = true
        page.dayComplete = true
        page.scheduleBlocks = [DailyPageScheduleBlock(title: "Work", startMinuteOfDay: 540, endMinuteOfDay: 1020, sortOrder: 0)]
        src.insert(page)
        let task = DailyPageTask(title: "Snapshot task", sourceType: .manual, sortOrder: 0)
        task.completed = true
        task.page = page
        src.insert(task)

        let reminder = NotificationReminder(title: "Stretch", message: "time to stretch")
        reminder.fireHour = 14
        src.insert(reminder)

        // Previously NOT backed up — must survive now.
        let routine = Routine(title: "Skincare")
        routine.emoji = "🧴"
        src.insert(routine)
        let rItem = RoutineItem(text: "Cleanser", sortOrder: 0)
        rItem.routine = routine
        src.insert(rItem)

        let calState = CalendarEventLocalState(date: pastDate, eventId: "evt-123")
        calState.completed = true
        calState.titleOverride = "Renamed event"
        src.insert(calState)

        try src.save()

        // Settings the backup should carry.
        let d = UserDefaults.standard
        d.set("libertinus", forKey: "settings.fontChoice")
        d.set(4, forKey: "settings.fontSizeStep")
        d.set(["cal-A", "cal-B"], forKey: "selectedCalendarIds")

        // ── Export → file → decode ──────────────────────────────────────
        let url = try HprgmExportService().export(context: src)
        let bundle = try HprgmImportService().preview(fileURL: url)

        XCTAssertEqual(bundle.formatVersion, 2)
        XCTAssertEqual(bundle.backlogItems.count, 1)
        XCTAssertEqual(bundle.routines?.count, 1)
        XCTAssertEqual(bundle.routines?.first?.items.count, 1)
        XCTAssertEqual(bundle.calendarEventStates?.count, 1)
        XCTAssertEqual(bundle.dailyPages.count, 1)
        XCTAssertTrue(bundle.dailyPages.first?.isPastLocked == true)
        XCTAssertEqual(bundle.settings?.fontChoice, "libertinus")
        XCTAssertEqual(bundle.settings?.selectedCalendarIds, ["cal-A", "cal-B"])

        // Change settings to prove the import overwrites them.
        d.set("cardo", forKey: "settings.fontChoice")
        d.set(2, forKey: "settings.fontSizeStep")
        d.removeObject(forKey: "selectedCalendarIds")

        // ── Import into a fresh container that already holds junk ────────
        let dstContainer = try makeTestModelContainer()
        let dst = ModelContext(dstContainer)
        // Junk that must be wiped — including a locked page (full restore replaces it).
        let junk = BacklogItem(title: "DELETE ME")
        dst.insert(junk)
        let junkPage = DailyPage(date: Date(), createdAutomatically: false)
        junkPage.isPastLocked = true
        dst.insert(junkPage)
        try dst.save()

        try HprgmImportService().importData(bundle, context: dst)

        // ── Assert exact restore ────────────────────────────────────────
        let items = try dst.fetch(FetchDescriptor<BacklogItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Buy vitamins")
        XCTAssertEqual(items.first?.notes, "from the pharmacy")
        XCTAssertEqual(items.first?.project?.name, "Health", "backlog→project relationship must survive")

        XCTAssertEqual(try dst.fetch(FetchDescriptor<ProjectBucket>()).count, 1)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<RecurringTaskTemplate>()).count, 1)

        let exercises = try dst.fetch(FetchDescriptor<ExerciseRoutine>())
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.items.count, 1)
        XCTAssertEqual(exercises.first?.items.first?.sets, 3)

        let schedules = try dst.fetch(FetchDescriptor<ScheduleTemplate>())
        XCTAssertEqual(schedules.first?.blocks.first?.title, "Sleep")
        XCTAssertEqual(schedules.first?.assignedWeekdays, [2, 3, 4, 5, 6])

        let pages = try dst.fetch(FetchDescriptor<DailyPage>())
        XCTAssertEqual(pages.count, 1, "junk page wiped, backup page restored")
        XCTAssertTrue(pages.first?.isPastLocked == true, "locked snapshot restored as locked")
        XCTAssertEqual(pages.first?.tasks.count, 1)
        XCTAssertEqual(pages.first?.tasks.first?.title, "Snapshot task")

        XCTAssertEqual(try dst.fetch(FetchDescriptor<NotificationReminder>()).first?.fireHour, 14)

        let routines = try dst.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1, "Routines must be restored (were silently dropped before)")
        XCTAssertEqual(routines.first?.emoji, "🧴")
        XCTAssertEqual(routines.first?.items.first?.text, "Cleanser")

        let states = try dst.fetch(FetchDescriptor<CalendarEventLocalState>())
        XCTAssertEqual(states.count, 1, "calendar local state must be restored")
        XCTAssertEqual(states.first?.titleOverride, "Renamed event")
        XCTAssertTrue(states.first?.completed == true)

        // Settings restored from the backup, overwriting the changed values.
        XCTAssertEqual(d.string(forKey: "settings.fontChoice"), "libertinus")
        XCTAssertEqual(d.integer(forKey: "settings.fontSizeStep"), 4)
        XCTAssertEqual(d.stringArray(forKey: "selectedCalendarIds"), ["cal-A", "cal-B"])

        try? FileManager.default.removeItem(at: url)
    }

    /// A v1 backup (no routines / calendarEventStates / settings keys) must still
    /// decode and import without error.
    func testV1BundleDecodesWithoutNewSections() throws {
        let json = """
        {
          "formatName": "Human Program Export",
          "formatVersion": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "appVersion": "1.0.0",
          "backlogItems": [],
          "projectBuckets": [],
          "recurringTaskTemplates": [],
          "exerciseRoutines": [],
          "scheduleTemplates": [],
          "dailyPages": [],
          "notifications": []
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v1.hprgm")
        try json.data(using: .utf8)!.write(to: url)
        let bundle = try HprgmImportService().preview(fileURL: url)
        XCTAssertNil(bundle.routines)
        XCTAssertNil(bundle.settings)

        let container = try makeTestModelContainer()
        let ctx = ModelContext(container)
        XCTAssertNoThrow(try HprgmImportService().importData(bundle, context: ctx))
        try? FileManager.default.removeItem(at: url)
    }
}
