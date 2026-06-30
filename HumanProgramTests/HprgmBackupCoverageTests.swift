import XCTest
import SwiftData
@testable import HumanProgram

/// Safety net for backup fidelity. Reflects every backed-up @Model and asserts each of
/// its stored properties is represented in the matching *JSON mirror struct
/// (HprgmExportService). When you add a @Model field, this test FAILS until you also add
/// it to the JSON struct + the export map + the import insert (CLAUDE.md's #1 fidelity
/// rule) — or knowingly list it in `except:` as intentionally not backed up.
///
/// This turns the previously-silent "added a field but forgot the backup" data loss into
/// a build-time failure. It does not replace HprgmBackupRoundTripTests (which verifies the
/// values actually survive) — it guards the field LIST.
@MainActor
final class HprgmBackupCoverageTests: XCTestCase {

    func test_everyModelFieldIsRepresentedInItsBackupJSON() {
        // Relationships are represented differently in the JSON (by id, or restored from
        // the other side), so they are excluded by name:
        assertBackedUp(BacklogItem(title: ""),
                       json: BacklogItemJSON(id: "", title: "", notes: "", projectBucketId: nil,
                                             assignedDate: nil, status: .backlog, createdAt: Date(), updatedAt: Date()),
                       except: ["project"])   // -> projectBucketId

        assertBackedUp(ProjectBucket(name: ""),
                       json: ProjectBucketJSON(id: "", name: "", createdAt: Date(), updatedAt: Date()),
                       except: ["items"])      // restored from each BacklogItem.projectBucketId

        assertBackedUp(RecurringTaskTemplate(title: "", rule: .daily()),
                       json: RecurringTaskTemplateJSON(id: "", title: "", notes: "", recurrenceRule: .daily(),
                                                       active: true, createdAt: Date(), updatedAt: Date()))

        assertBackedUp(ExerciseRoutineItem(text: "", sortOrder: 0),
                       json: ExerciseRoutineItemJSON(id: "", text: "", sets: nil, reps: nil, notes: "", sortOrder: 0),
                       except: ["routine"])

        assertBackedUp(ExerciseRoutine(name: "", rule: RecurrenceRule(frequency: .everyDay)),
                       json: ExerciseRoutineJSON(id: "", name: "", notes: "", recurrenceRule: .daily(),
                                                 active: true, createdAt: Date(), updatedAt: Date(), items: []))

        assertBackedUp(ScheduleTemplate(name: ""),
                       json: ScheduleTemplateJSON(id: "", name: "", isEnabled: true, assignedWeekdays: [],
                                                  customDateStart: nil, customDateEnd: nil, blocks: [],
                                                  createdAt: Date(), updatedAt: Date()))

        assertBackedUp(DailyPageTask(title: "", sourceType: .manual, sortOrder: 0),
                       json: DailyPageTaskJSON(id: "", sourceType: .manual, sourceId: nil, title: "", notes: "",
                                               completed: false, completedAt: nil, sortOrder: 0),
                       except: ["page"])

        assertBackedUp(DailyPage(date: Date(), createdAutomatically: false),
                       json: DailyPageJSON(id: "", date: Date(), createdAutomatically: false, dayComplete: false,
                                           isPastLocked: false, hiddenRecurringTaskIds: nil, scheduleBlocks: [], createdAt: Date(),
                                           updatedAt: Date(), tasks: []))

        assertBackedUp(NotificationReminder(title: "", message: ""),
                       json: NotificationReminderJSON(id: "", title: "", message: "", isEnabled: true,
                                                      recurrenceMode: .selectedWeekdays, weekdays: [], fireHour: 0,
                                                      fireMinute: 0, intervalMinutes: 0, windowStartMinute: 0,
                                                      windowEndMinute: 0, soundMode: .defaultSound, imageFilename: nil,
                                                      attachedTaskId: nil, createdAt: Date(), updatedAt: Date()))

        assertBackedUp(RoutineItem(text: "", sortOrder: 0),
                       json: RoutineItemJSON(id: "", text: "", notes: "", sortOrder: 0),
                       except: ["routine"])

        assertBackedUp(Routine(title: ""),
                       json: RoutineJSON(id: "", title: "", emoji: "", notes: "", body: "", createdAt: Date(),
                                         updatedAt: Date(), items: []))

        assertBackedUp(CalendarEventLocalState(date: Date(), eventId: ""),
                       json: CalendarEventLocalStateJSON(date: Date(), eventId: "", completed: false, hidden: false,
                                                         titleOverride: nil, notesOverride: nil, sortOrder: 0,
                                                         updatedAt: Date()))
    }

    // MARK: - Helper

    private func assertBackedUp<M, J>(
        _ model: M, json: J, except notInBackup: Set<String> = [],
        file: StaticString = #file, line: UInt = #line
    ) {
        let modelFields = storedFieldNames(model)
        let jsonFields = storedFieldNames(json)
        let missing = modelFields.subtracting(jsonFields).subtracting(notInBackup)
        XCTAssertTrue(
            missing.isEmpty,
            "\(type(of: model)) has stored field(s) not in \(type(of: json)) and not excluded: \(missing.sorted()). " +
            "Add them to the JSON struct + the export map + the import insert (backup fidelity), " +
            "or list them in `except:` if intentionally not backed up.",
            file: file, line: line
        )
    }

    /// Mirror labels for a @Model come back as `_id`, `_title`, … plus the SwiftData
    /// internals `_$backingData` / `_$observationRegistrar`. Strip the leading underscore
    /// and drop the `$`-prefixed internals.
    private func storedFieldNames(_ value: Any) -> Set<String> {
        Set(
            Mirror(reflecting: value).children
                .compactMap { $0.label }
                .map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
                .filter { !$0.hasPrefix("$") }
        )
    }
}
