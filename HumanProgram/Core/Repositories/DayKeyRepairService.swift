import Foundation
import SwiftData

/// One-pass repair that re-files every per-day record onto its timezone-independent
/// `dayKey`, re-anchors its `date` to local midnight in the CURRENT timezone, merges
/// any duplicate records the old instant-matching lookup created, and locks days that
/// are now in the past.
///
/// Runs at every launch (`AppStartup`) and is a no-op once everything already lines up,
/// so it also self-heals the next time the device changes timezone. It never deletes a
/// user's work: when two pages exist for one day the richer one survives and any
/// completed or hand-typed task from the other is moved onto it first. [tz-daykey]
@MainActor
public enum DayKeyRepairService {

    public struct Report: Sendable {
        public var pagesRefiled = 0      // dayKey backfilled and/or date re-anchored
        public var pagesMerged = 0       // duplicate pages folded into their survivor
        public var tasksRecovered = 0    // tasks moved off a duplicate onto the survivor
        public var pagesLocked = 0       // past pages that were missing their lock flag
        public var statesRefiled = 0
        public var statesMerged = 0

        public var didChangeAnything: Bool {
            pagesRefiled + pagesMerged + tasksRecovered + pagesLocked + statesRefiled + statesMerged > 0
        }
    }

    @discardableResult
    public static func run(
        context: ModelContext,
        today: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Report {
        var report = Report()
        try repairPages(context: context, today: today, calendar: calendar, report: &report)
        try repairCalendarStates(context: context, calendar: calendar, report: &report)
        if report.didChangeAnything {
            try context.save()
            print("[DayKeyRepair] refiled \(report.pagesRefiled) pages, merged \(report.pagesMerged) "
                + "(recovered \(report.tasksRecovered) tasks), locked \(report.pagesLocked); "
                + "calendar state refiled \(report.statesRefiled), merged \(report.statesMerged)")
        }
        return report
    }

    // MARK: - Daily pages

    private static func repairPages(
        context: ModelContext, today: Date, calendar: Calendar, report: inout Report
    ) throws {
        let pages = try context.fetch(
            FetchDescriptor<DailyPage>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )
        guard !pages.isEmpty else { return }

        var byKey: [Int: [DailyPage]] = [:]
        for page in pages {
            byKey[DayKey.resolve(storedKey: page.dayKey, storedDate: page.date), default: []].append(page)
        }

        let todayKey = DayKey.make(today, calendar: calendar)
        for (key, group) in byKey {
            let survivor = merge(group, key: key, today: today, context: context, report: &report)

            let anchor = DayKey.startOfDay(key, calendar: calendar)
            if survivor.dayKey != key || survivor.date != anchor {
                survivor.dayKey = key
                survivor.date = anchor
                report.pagesRefiled += 1
            }
            // A day that is now in the past is a historical snapshot. The flag used to
            // be set only when the page was CREATED in the past or re-visited later, so
            // most real history sat unlocked and was protected by date arithmetic alone
            // — one wrong "today" away from being regenerated. Lock it for real. [tz-daykey]
            if key < todayKey && !survivor.isPastLocked {
                survivor.isPastLocked = true
                report.pagesLocked += 1
            }
        }
    }

    /// Fold duplicates for one day into a single page and return it. The survivor is the
    /// page with the most COMPLETED tasks (then the most tasks, then the oldest) — i.e.
    /// the real day, not the empty one a missed lookup generated.
    private static func merge(
        _ group: [DailyPage], key: Int, today: Date, context: ModelContext, report: inout Report
    ) -> DailyPage {
        guard group.count > 1, let survivor = group.max(by: { rank($0) < rank($1) }) else {
            return group[0]
        }

        var titles = Set(survivor.tasks.map { $0.title })
        var nextSortOrder = (survivor.tasks.map { $0.sortOrder }.max() ?? -1) + 1
        var movedAny = false

        for loser in group where loser !== survivor {
            // Only rescue work that would otherwise be lost: a task that is checked off,
            // or one the user typed themselves. Template-generated leftovers on a
            // duplicate are re-derivable and would wrongly un-complete the day.
            let keepers = loser.tasks.filter {
                ($0.completed || $0.sourceType == .manual) && !titles.contains($0.title)
            }
            for task in keepers {
                loser.tasks.removeAll { $0.id == task.id }
                task.page = survivor
                task.sortOrder = nextSortOrder
                nextSortOrder += 1
                if !survivor.tasks.contains(where: { $0.id == task.id }) {
                    survivor.tasks.append(task)
                }
                titles.insert(task.title)
                movedAny = true
                report.tasksRecovered += 1
            }
            // Per-day deletions are the user's intent too — keep them.
            survivor.hiddenRecurringTaskIds = union(survivor.hiddenRecurringTaskIds, loser.hiddenRecurringTaskIds)
            survivor.hiddenBacklogTaskIds = union(survivor.hiddenBacklogTaskIds, loser.hiddenBacklogTaskIds)
            context.delete(loser)
            report.pagesMerged += 1
        }

        // Only re-derive completion when the task list actually changed — a past day's
        // stored result is history and must not be recomputed for its own sake.
        if movedAny {
            CompletionService().recalculate(page: survivor, today: today)
            survivor.updatedAt = Date()
        }
        return survivor
    }

    private static func rank(_ page: DailyPage) -> (Int, Int, TimeInterval) {
        (page.tasks.filter { $0.completed }.count,
         page.tasks.count,
         -page.createdAt.timeIntervalSinceReferenceDate)
    }

    private static func union(_ a: [String]?, _ b: [String]?) -> [String] {
        var out = a ?? []
        for id in b ?? [] where !out.contains(id) { out.append(id) }
        return out
    }

    // MARK: - Calendar local state

    private static func repairCalendarStates(
        context: ModelContext, calendar: Calendar, report: inout Report
    ) throws {
        let states = try context.fetch(
            FetchDescriptor<CalendarEventLocalState>(sortBy: [SortDescriptor(\.updatedAt, order: .forward)])
        )
        guard !states.isEmpty else { return }

        var byKey: [String: [CalendarEventLocalState]] = [:]
        for state in states {
            let key = DayKey.resolve(storedKey: state.dayKey, storedDate: state.date)
            byKey["\(key)|\(state.eventId)", default: []].append(state)
        }

        for (_, group) in byKey {
            // Most-recently-updated row wins, matching the existing dedupe policy, but a
            // row carrying an actual override/hide beats an empty one.
            let survivor = group.max { a, b in
                (carriesState(a) ? 1 : 0, a.updatedAt.timeIntervalSinceReferenceDate)
                    < (carriesState(b) ? 1 : 0, b.updatedAt.timeIntervalSinceReferenceDate)
            } ?? group[0]

            for loser in group where loser !== survivor {
                context.delete(loser)
                report.statesMerged += 1
            }

            let key = DayKey.resolve(storedKey: survivor.dayKey, storedDate: survivor.date)
            let anchor = DayKey.startOfDay(key, calendar: calendar)
            if survivor.dayKey != key || survivor.date != anchor {
                survivor.dayKey = key
                survivor.date = anchor
                report.statesRefiled += 1
            }
        }
    }

    private static func carriesState(_ s: CalendarEventLocalState) -> Bool {
        s.hidden || s.completed || s.titleOverride != nil || s.notesOverride != nil
    }
}
