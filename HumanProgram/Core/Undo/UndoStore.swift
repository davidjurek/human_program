import Foundation
import SwiftData
import Observation

// App-wide undo/redo, triggered by a phone shake. ONE global stack across every
// in-scope screen (Today, Backlog, Recurring, Reminders, Schedule, Exercise,
// Routines). In-memory only — it starts empty on every cold launch and is never
// persisted. Calendar-sourced Today tasks ARE in scope (owner-approved 2026-07-12):
// a rename, note edit, completion toggle, or delete of a calendar task on Today is
// recorded, as is reverting one from the differences page. App-lock and every
// Settings category (customization, format, accessibility, security, calendar
// SOURCE selection, import/export/reset/restore) remain OUT of scope. EventKit
// events themselves are never mutated by undo — only the app's local overrides.
//
// Granularity matches the user's intent: an edit committed with one Save is ONE
// action; a delete is ONE action; a create is ONE action. Multi-select delete /
// multi-move are also one action (one transaction with several ops).

/// Quote a user-facing title for an undo label ("Add task “poop”"); falls back to
/// "Untitled" when blank, so a label is always specific.
func undoTitle(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "Untitled" : "\u{201C}\(t)\u{201D}"
}

// MARK: - Post-apply side effect

/// What to re-run after an undo or a redo so the rest of the app stays consistent —
/// exactly what the original action's call site did.
enum UndoPost {
    case none
    case pageRefresh          // recurring / schedule changes feed today+future pages
    case rescheduleReminders  // reminder changes re-arm notifications

    @MainActor func run(_ context: ModelContext) {
        switch self {
        case .none:
            break
        case .pageRefresh:
            try? PageRefreshService.refresh(context: context)
        case .rescheduleReminders:
            let all = (try? NotificationReminderRepository(context: context).fetchAll()) ?? []
            Task { await RollingReminderScheduler().reschedule(reminders: all) }
        }
    }
}

// MARK: - Transaction

struct UndoTransaction {
    let description: String     // pithy, specific: "Delete task", "Add project"
    let undoOps: [UndoOp]
    let redoOps: [UndoOp]
    let post: UndoPost
    /// When set, a rapid burst of same-key records (e.g. each step of one drag-
    /// reorder) collapses into ONE action: the first record's `undoOps` (pre-burst
    /// state) is kept, later records only refresh `redoOps`/description.
    var coalesceKey: String? = nil
}

// MARK: - Store

@Observable
@MainActor
final class UndoStore {
    static let shared = UndoStore()

    private(set) var undoStack: [UndoTransaction] = []
    private(set) var redoStack: [UndoTransaction] = []

    /// Bumped every time an undo/redo is APPLIED. Screens that drive their own data
    /// imperatively (the Today screen loads a page via a view model rather than an
    /// auto-updating @Query) can observe this to reload after an undo/redo mutates the
    /// store out from under them — otherwise the change only shows after a manual
    /// reload (navigate away and back). [today-undo-refresh]
    private(set) var revision = 0

    /// Cap so a long session can't grow the stacks without bound.
    private let maxDepth = 50

    /// True while applying an undo/redo, so a mutation made by the apply path can
    /// never record a new transaction (defense in depth — the apply primitives
    /// don't go through the instrumented call sites anyway).
    private(set) var isApplying = false

    /// Coalescing window: same-key records closer together than this merge into one.
    private let coalesceWindow: TimeInterval = 0.6
    private var lastRecordTime = Date.distantPast

    private init() {}

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    /// Description of the action a shake-Undo would reverse (nil if none).
    var undoDescription: String? { undoStack.last?.description }
    /// Description of the action a shake-Redo would reapply (nil if none).
    var redoDescription: String? { redoStack.last?.description }

    func record(_ transaction: UndoTransaction) {
        guard !isApplying else { return }
        let now = Date()
        // Coalesce a rapid burst of same-key records (one drag-reorder) into one.
        if let key = transaction.coalesceKey, let last = undoStack.last,
           last.coalesceKey == key, now.timeIntervalSince(lastRecordTime) < coalesceWindow {
            undoStack[undoStack.count - 1] = UndoTransaction(
                description: transaction.description, undoOps: last.undoOps,
                redoOps: transaction.redoOps, post: transaction.post, coalesceKey: key)
            lastRecordTime = now
            redoStack.removeAll()
            return
        }
        undoStack.append(transaction)
        if undoStack.count > maxDepth { undoStack.removeFirst(undoStack.count - maxDepth) }
        // A brand-new action invalidates the redo history.
        redoStack.removeAll()
        lastRecordTime = now
    }

    func undo(context: ModelContext) {
        guard let t = undoStack.popLast() else { return }
        apply(t.undoOps, context)
        t.post.run(context)
        redoStack.append(t)
        revision &+= 1
    }

    func redo(context: ModelContext) {
        guard let t = redoStack.popLast() else { return }
        apply(t.redoOps, context)
        t.post.run(context)
        undoStack.append(t)
        revision &+= 1
    }

    /// Drop the whole history (e.g. a full restore replaced all data, so the old
    /// snapshots no longer refer to anything meaningful).
    func clear() { undoStack.removeAll(); redoStack.removeAll() }

    private func apply(_ ops: [UndoOp], _ context: ModelContext) {
        isApplying = true
        defer { isApplying = false }
        for op in ops {
            do { try op.run(context) }
            catch { print("[Undo] apply error: \(error)") }
        }
    }
}

// MARK: - Recorder façade (what the call sites use)

/// Thin helpers so a call site records an action in one line. They build the
/// inverse/forward op lists from value snapshots captured at the call site.
@MainActor
enum Undo {
    /// An object was just CREATED. Pass a snapshot of it AFTER creation.
    static func created<S: UndoSnapshot>(_ description: String, _ after: S, post: UndoPost = .none) {
        UndoStore.shared.record(UndoTransaction(
            description: description,
            undoOps: [.remove(S.self, after.id)],
            redoOps: [.upsert(after)],
            post: post))
    }

    /// An object is about to be DELETED. Pass a snapshot captured BEFORE deletion.
    static func deleted<S: UndoSnapshot>(_ description: String, _ before: S, post: UndoPost = .none) {
        UndoStore.shared.record(UndoTransaction(
            description: description,
            undoOps: [.upsert(before)],
            redoOps: [.remove(S.self, before.id)],
            post: post))
    }

    /// An object was EDITED. Pass snapshots from before AND after the edit.
    static func edited<S: UndoSnapshot>(_ description: String, before: S, after: S, post: UndoPost = .none) {
        UndoStore.shared.record(UndoTransaction(
            description: description,
            undoOps: [.upsert(before)],
            redoOps: [.upsert(after)],
            post: post))
    }

    /// General form for multi-object actions (reorder, multi-delete, multi-move,
    /// delete-project-and-its-tasks). `undoOps` are applied in order to reverse the
    /// action; `redoOps` in order to reapply it. `coalesceKey` merges a rapid burst
    /// (one drag-reorder) into a single action.
    static func record(_ description: String, undoOps: [UndoOp], redoOps: [UndoOp],
                       post: UndoPost = .none, coalesceKey: String? = nil) {
        UndoStore.shared.record(UndoTransaction(
            description: description, undoOps: undoOps, redoOps: redoOps,
            post: post, coalesceKey: coalesceKey))
    }

    /// Record a whole editor session that changed a parent and its children as ONE
    /// action, by diffing the parent+children captured at open against commit. Used
    /// by the lazy-create / commit-on-leave editors (Routines), where per-call
    /// recording would be noisy. nil parent = absent (created or deleted).
    static func recordContainer<P: UndoSnapshot, Ch: UndoSnapshot>(
        _ description: String,
        beforeParent: P?, beforeChildren: [Ch],
        afterParent: P?, afterChildren: [Ch],
        post: UndoPost = .none
    ) {
        let beforeIds = Set(beforeChildren.map { $0.id })
        let afterIds = Set(afterChildren.map { $0.id })

        var undoOps: [UndoOp] = []        // turn the after-state back into before
        if let bp = beforeParent {
            undoOps.append(.upsert(bp))
            undoOps.append(contentsOf: beforeChildren.map { .upsert($0) })
            undoOps.append(contentsOf: afterChildren.filter { !beforeIds.contains($0.id) }
                                                    .map { .remove(Ch.self, $0.id) })
        } else if let ap = afterParent {
            undoOps.append(.remove(P.self, ap.id))   // was created → remove (cascades children)
        }

        var redoOps: [UndoOp] = []        // turn the before-state into after
        if let ap = afterParent {
            redoOps.append(.upsert(ap))
            redoOps.append(contentsOf: afterChildren.map { .upsert($0) })
            redoOps.append(contentsOf: beforeChildren.filter { !afterIds.contains($0.id) }
                                                     .map { .remove(Ch.self, $0.id) })
        } else if let bp = beforeParent {
            redoOps.append(.remove(P.self, bp.id))   // was deleted → remove
        }

        UndoStore.shared.record(UndoTransaction(
            description: description, undoOps: undoOps, redoOps: redoOps, post: post))
    }
}
