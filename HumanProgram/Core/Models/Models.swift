import Foundation
import SwiftData

// ── Shared constants ──────────────────────────────────────────────
// Named once so the same value can't drift between copies. [#63]
public let minutesPerDay = 1440
public let daysPerWeek = 7

// ── Enums (plain Codable types, NOT @Model) ───────────────────────

public enum BacklogStatus: String, Codable, Sendable {
    case backlog, done
}

public enum DailyTaskSourceType: String, Codable, Sendable {
    case recurring, backlog, manual, calendar
}

// ── Schedule block duration (shared math) ─────────────────────────
// Minutes a block covers, handling overnight wrap (end <= start). Lives in ONE
// place so the template type and the page-snapshot type can't drift. [#62][#63]
func scheduleBlockDurationMinutes(startMinuteOfDay: Int, endMinuteOfDay: Int) -> Int {
    if endMinuteOfDay > startMinuteOfDay {
        return endMinuteOfDay - startMinuteOfDay
    } else {
        // Overnight block: e.g. 21:30 (1290) to 05:30 (330)
        return (minutesPerDay - startMinuteOfDay) + endMinuteOfDay
    }
}

// ── ScheduleBlock ─────────────────────────────────────────────────
// Stored as a Codable struct inside ScheduleTemplate (not a @Model)
public struct ScheduleBlock: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var startMinuteOfDay: Int   // minutes from midnight (0–1439)
    public var endMinuteOfDay: Int     // may be <= start for overnight blocks
    public var sortOrder: Int
    public var colorHex: String?       // assigned block colour (nil → default-by-name) [#20]

    /// The mandatory first block of every schedule is the Sleep block, identified by
    /// this reserved title. Routing all "is this the Sleep block?" checks through the
    /// computed `isSleep` keeps the sentinel in ONE place instead of scattering the
    /// literal "Sleep" across the repository. [#21]
    public static let sleepBlockTitle = "Sleep"
    public var isSleep: Bool { title == Self.sleepBlockTitle }

    public var durationMinutes: Int {
        scheduleBlockDurationMinutes(startMinuteOfDay: startMinuteOfDay, endMinuteOfDay: endMinuteOfDay)
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        sortOrder: Int,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.sortOrder = sortOrder
        self.colorHex = colorHex
    }
}

// ── DailyPageScheduleBlock (snapshot of a ScheduleBlock on a page) ─
public struct DailyPageScheduleBlock: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var sortOrder: Int
    public var colorHex: String?       // snapshot of the block colour [#20]

    /// Minutes this block covers, handling overnight wrap — same math as
    /// `ScheduleBlock.durationMinutes` so the duration lives in one place. [#62]
    public var durationMinutes: Int {
        scheduleBlockDurationMinutes(startMinuteOfDay: startMinuteOfDay, endMinuteOfDay: endMinuteOfDay)
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        sortOrder: Int,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.sortOrder = sortOrder
        self.colorHex = colorHex
    }
}

// ── NotificationRecurrenceMode ────────────────────────────────────
public enum NotificationRecurrenceMode: String, Codable {
    case daily
    case weekdays
    case selectedWeekdays
    case everyNMinutes   // interval + startMinuteOfDay + endMinuteOfDay + weekdays
    case hourlyWindow    // every hour between startMinuteOfDay..endMinuteOfDay on weekdays
}

public enum NotificationSoundMode: String, Codable {
    case defaultSound, silent, chimeOnly
}

// ── ProjectBucket ─────────────────────────────────────────────────
@Model public final class ProjectBucket {
    @Attribute(.unique) public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \BacklogItem.project)
    public var items: [BacklogItem]

    public init(name: String) {
        self.id = UUID().uuidString
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
    }
}

// ── BacklogItem ───────────────────────────────────────────────────
@Model public final class BacklogItem {
    @Attribute(.unique) public var id: String
    public var title: String
    public var notes: String
    public var assignedDate: Date?
    public var status: BacklogStatus
    public var project: ProjectBucket?
    public var createdAt: Date
    public var updatedAt: Date

    public init(title: String) {
        self.id = UUID().uuidString
        self.title = title
        self.notes = ""
        self.assignedDate = nil
        self.status = .backlog
        self.project = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// ── RecurringTaskTemplate ──────────────────────────────────────────
@Model public final class RecurringTaskTemplate {
    @Attribute(.unique) public var id: String
    public var title: String
    public var notes: String
    public var recurrenceRule: RecurrenceRule
    public var active: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(title: String, rule: RecurrenceRule) {
        self.id = UUID().uuidString
        self.title = title
        self.notes = ""
        self.recurrenceRule = rule
        self.active = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// ── ExerciseRoutineItem ───────────────────────────────────────────
@Model public final class ExerciseRoutineItem {
    @Attribute(.unique) public var id: String
    public var text: String
    public var sets: Int?
    public var reps: Int?
    public var notes: String
    public var sortOrder: Int
    public var routine: ExerciseRoutine?

    public init(text: String, sortOrder: Int) {
        self.id = UUID().uuidString
        self.text = text
        self.sets = nil
        self.reps = nil
        self.notes = ""
        self.sortOrder = sortOrder
        self.routine = nil
    }
}

// ── ExerciseRoutine ───────────────────────────────────────────────
@Model public final class ExerciseRoutine {
    @Attribute(.unique) public var id: String
    public var name: String
    public var notes: String
    public var recurrenceRule: RecurrenceRule
    public var active: Bool
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ExerciseRoutineItem.routine)
    public var items: [ExerciseRoutineItem]

    public init(name: String, rule: RecurrenceRule) {
        self.id = UUID().uuidString
        self.name = name
        self.notes = ""
        self.recurrenceRule = rule
        self.active = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
    }
}

// ── ScheduleTemplate ─────────────────────────────────────────────
@Model public final class ScheduleTemplate {
    @Attribute(.unique) public var id: String
    public var name: String
    public var isEnabled: Bool
    public var assignedWeekdays: [Int]       // 1=Sun...7=Sat
    public var customDateStart: Date?
    public var customDateEnd: Date?
    public var blocks: [ScheduleBlock]       // Codable array attribute; first block MUST be Sleep
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String) {
        self.id = UUID().uuidString
        self.name = name
        self.isEnabled = true
        self.assignedWeekdays = []
        self.customDateStart = nil
        self.customDateEnd = nil
        self.blocks = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// ── DailyPageTask ─────────────────────────────────────────────────
@Model public final class DailyPageTask {
    @Attribute(.unique) public var id: String
    public var sourceType: DailyTaskSourceType
    public var sourceId: String?
    public var title: String
    public var notes: String
    public var completed: Bool
    public var completedAt: Date?
    public var sortOrder: Int
    public var page: DailyPage?

    public init(
        title: String,
        sourceType: DailyTaskSourceType,
        sourceId: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.notes = ""
        self.completed = false
        self.completedAt = nil
        self.sortOrder = sortOrder
        self.page = nil
    }
}

// ── DailyPage ─────────────────────────────────────────────────────
@Model public final class DailyPage {
    @Attribute(.unique) public var id: String
    public var date: Date                        // normalized to start-of-day
    public var createdAutomatically: Bool
    public var dayComplete: Bool
    public var isPastLocked: Bool                // true = historical snapshot, protected from edits
    public var hiddenRecurringTaskIds: [String]? // recurring template ids hidden on this page only
    public var scheduleBlocks: [DailyPageScheduleBlock]   // Codable array snapshot
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \DailyPageTask.page)
    public var tasks: [DailyPageTask]

    public init(date: Date, createdAutomatically: Bool = true) {
        self.id = UUID().uuidString
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAutomatically = createdAutomatically
        self.dayComplete = false
        self.isPastLocked = false
        self.hiddenRecurringTaskIds = []
        self.scheduleBlocks = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tasks = []
    }

    /// Reserved word a completed task's title must contain to count the day toward
    /// the exercise streak. Exercise routines never become page-tasks (exercise
    /// doesn't count toward completion), so a user-named completed task is the only
    /// signal that a day "had exercise" — this keeps that one signal in ONE place
    /// instead of an inline title scan in the Stats view. [#52]
    public static let exerciseTitleMarker = "exercise"

    /// True if the day had a completed task the user named for exercise.
    public var hadCompletedExercise: Bool {
        tasks.contains { $0.completed && $0.title.lowercased().contains(Self.exerciseTitleMarker) }
    }

    public func hideRecurringTask(id: String) {
        var ids = hiddenRecurringTaskIds ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        hiddenRecurringTaskIds = ids
    }

    public func unhideRecurringTask(id: String) {
        hiddenRecurringTaskIds = (hiddenRecurringTaskIds ?? []).filter { $0 != id }
    }
}

// ── CalendarEventLocalState ───────────────────────────────────────
@Model public final class CalendarEventLocalState {
    // composite identity: date + eventId
    public var date: Date
    public var eventId: String
    public var completed: Bool
    public var hidden: Bool
    public var titleOverride: String?
    public var notesOverride: String?
    public var sortOrder: Int
    public var updatedAt: Date

    public init(date: Date, eventId: String) {
        self.date = Calendar.current.startOfDay(for: date)
        self.eventId = eventId
        self.completed = false
        self.hidden = false
        self.titleOverride = nil
        self.notesOverride = nil
        self.sortOrder = 0
        self.updatedAt = Date()
    }
}

// ── NotificationReminder ──────────────────────────────────────────
@Model public final class NotificationReminder {
    @Attribute(.unique) public var id: String
    public var title: String
    public var message: String
    public var isEnabled: Bool
    public var recurrenceMode: NotificationRecurrenceMode
    public var weekdays: [Int]              // for selectedWeekdays / hourlyWindow
    public var fireHour: Int               // 0–23
    public var fireMinute: Int             // 0–59
    public var intervalMinutes: Int        // for everyNMinutes
    public var windowStartMinute: Int      // for hourlyWindow (minutes from midnight)
    public var windowEndMinute: Int
    public var soundMode: NotificationSoundMode
    public var imageFilename: String?
    public var attachedTaskId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(title: String, message: String) {
        self.id = UUID().uuidString
        self.title = title
        self.message = message
        self.isEnabled = true
        self.recurrenceMode = .daily
        self.weekdays = []
        self.fireHour = 8
        self.fireMinute = 0
        self.intervalMinutes = 60
        self.windowStartMinute = 480   // 08:00
        self.windowEndMinute = 1200    // 20:00
        self.soundMode = .defaultSound
        self.imageFilename = nil
        self.attachedTaskId = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// ── RoutineItem ────────────────────────────────────────────────────
@Model public final class RoutineItem {
    @Attribute(.unique) public var id: String
    public var text: String
    public var notes: String
    public var sortOrder: Int
    public var routine: Routine?

    public init(text: String, sortOrder: Int) {
        self.id = UUID().uuidString
        self.text = text
        self.notes = ""
        self.sortOrder = sortOrder
        self.routine = nil
    }
}

// ── Routine ────────────────────────────────────────────────────────
@Model public final class Routine {
    @Attribute(.unique) public var id: String
    public var title: String
    public var emoji: String = ""        // single emoji shown on the menu square
    public var notes: String
    // The routine's content as one markdown text block (replaces the old itemized
    // RoutineItem list). Existing routines migrate their items into this on launch
    // (RoutineRepository.migrateItemsToBodyIfNeeded). [option B]
    public var body: String = ""
    public var createdAt: Date
    public var updatedAt: Date
    // Legacy: kept only so old stores/backups decode and can be folded into `body`.
    // The Routines UI no longer reads or writes items.
    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
    public var items: [RoutineItem]

    public init(title: String) {
        self.id = UUID().uuidString
        self.title = title
        self.emoji = ""
        self.notes = ""
        self.body = ""
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = []
    }
}
