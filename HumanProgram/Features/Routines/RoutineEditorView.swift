import SwiftUI
import SwiftData
import DSKit
import UIKit

// Routine editor. Title + emoji on one row (unchanged); the body is now a single
// markdown text block — a TextEditor in edit mode, rendered by MarkdownText in
// read mode (no itemized list anymore). Opens in READ mode for an existing
// routine, EDIT mode for a new/imported one. Edit/Save toggles top-right; a trash
// appears in edit mode to delete the routine.
struct RoutineEditorView: View {
    let routine: Routine?              // nil = new
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var working: Routine?
    @State private var editing = false
    @State private var name = ""
    @State private var emoji = ""
    @State private var bodyText = ""
    @State private var didLoad = false
    @State private var showDiscard = false
    @State private var discarded = false

    // Undo is recorded once per editor visit: the routine at open is diffed against
    // the persisted state on exit. See recordSession().
    @State private var beforeRoutineSnap: RoutineSnapshot?
    @State private var sessionRecorded = false

    private var repo: RoutineRepository { RoutineRepository(context: context) }

    private var isDirty: Bool {
        guard editing else { return false }
        if let r = routine { return name != r.title || emoji != r.emoji || bodyText != r.body }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty || !emoji.isEmpty
            || !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private func handleBack() {
        if isDirty { showDiscard = true } else { dismiss() }
    }
    private func discardAndDismiss() {
        showDiscard = false
        discarded = true                                             // skip commitOnLeave
        if routine == nil, let r = working { try? repo.delete(r) }   // new → delete if materialized
        recordSession()
        working = nil
        dismiss()
    }

    var body: some View {
        SettingsScreen(centered: true,
                       onBack: handleBack,
                       swipeBackBlocked: { isDirty },
                       trailing: { trailing }) {
            // Title + emoji share ONE line (emoji trailing). Edit and read modes use
            // the same layout/sizes so nothing reflows. [owner]
            HStack(spacing: 8) {
                Group {
                    if editing {
                        // appScaledSize(22) matches read mode's .title2 — no size jump.
                        AppTextField(text: $name, placeholder: "Routine name", fontSize: appScaledSize(22))
                    } else {
                        DSText(RoutineDisplay.title(name)).dsTextStyle(.title2).longTitle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if editing {
                    EmojiField(emoji: $emoji)
                } else if !emoji.isEmpty {
                    Text(emoji).font(.system(size: 28))
                }
            }

            if editing {
                TextEditor(text: $bodyText)
                    .font(appFont(17))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 320)
                    .padding(8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            } else {
                MarkdownText(bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .overlay {
            if showDiscard {
                ConfirmPopup(message: "Discard Changes?", confirmTitle: "Discard",
                             onConfirm: { discardAndDismiss() },
                             onCancel: { showDiscard = false })
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: commitOnLeave)
    }

    @ViewBuilder
    private var trailing: some View {
        if editing && working != nil {
            Button { deleteRoutine() } label: {
                Image(systemName: "trash").font(.system(size: 18)).foregroundStyle(.red)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }
        }
        // Save is disabled until there's a non-empty title. [#routines]
        let titleEmpty = name.trimmingCharacters(in: .whitespaces).isEmpty
        Button {
            if editing { commitContent() }
            editing.toggle()
        } label: {
            Text(editing ? "Save" : "Edit").font(appFont(18))
                .foregroundStyle(editing && titleEmpty ? .secondary : .primary)
                .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                .contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }
        .disabled(editing && titleEmpty)
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let routine {
            working = routine
            name = routine.title; emoji = routine.emoji; bodyText = routine.body
            editing = false
            beforeRoutineSnap = RoutineSnapshot(routine)
        } else {
            // New routine: do NOT create yet. Materialize only when there's real
            // content (a name/emoji or some body) so a blank-then-leave never flashes
            // an "Untitled" routine in the list. [#routines]
            editing = true
        }
    }

    /// Returns the working routine, creating it lazily the first time real content
    /// needs a home. For an existing routine it's already set in loadIfNeeded.
    @discardableResult
    private func ensureWorking() -> Routine? {
        if let working { return working }
        let created = try? repo.create(title: "")
        working = created
        return created
    }

    private func commitContent() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Don't materialize a routine for nothing.
        guard working != nil || !trimmed.isEmpty || !emoji.isEmpty
            || !bodyText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let r = ensureWorking() else { return }
        try? repo.update(r, title: trimmed, emoji: emoji, body: bodyText)
    }

    private func deleteRoutine() {
        discarded = true                       // don't let commitOnLeave re-create it
        if let r = working { try? repo.delete(r) }
        recordSession()                        // before = existing routine, after = gone → "Delete routine"
        working = nil
        dismiss()
    }

    private func commitOnLeave() {
        guard !discarded else { return }       // discarded — nothing to commit
        commitContent()
        // Never persist a titleless routine (no blank "Untitled"). If nothing was
        // ever materialized (working == nil), there's nothing to delete. [#routines]
        if let r = working, r.title.trimmingCharacters(in: .whitespaces).isEmpty {
            try? repo.delete(r)
        }
        recordSession()
    }

    // MARK: - Undo (one action per editor visit)

    /// Diff the routine captured at open against the persisted state now, and record
    /// it as a single Add / Edit / Delete routine action. Runs at most once per visit.
    private func recordSession() {
        guard !sessionRecorded else { return }
        sessionRecorded = true
        let rid = beforeRoutineSnap?.id ?? working?.id
        let afterRoutine: Routine? = rid.flatMap { id in
            var d = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return (try? context.fetch(d))?.first
        }
        let afterParent = afterRoutine.map { RoutineSnapshot($0) }
        guard sessionChanged(afterParent: afterParent) else { return }
        let desc: String
        if beforeRoutineSnap == nil {
            desc = "Add routine " + undoTitle(afterParent?.title ?? "")
        } else if afterParent == nil {
            desc = "Delete routine " + undoTitle(beforeRoutineSnap?.title ?? "")
        } else {
            desc = "Edit routine " + undoTitle(afterParent?.title ?? "")
        }
        Undo.recordContainer(desc,
            beforeParent: beforeRoutineSnap, beforeChildren: [RoutineItemSnapshot](),
            afterParent: afterParent, afterChildren: [RoutineItemSnapshot]())
    }

    private func sessionChanged(afterParent: RoutineSnapshot?) -> Bool {
        if (beforeRoutineSnap == nil) != (afterParent == nil) { return true }
        if let b = beforeRoutineSnap, let a = afterParent {
            return b.title != a.title || b.emoji != a.emoji || b.notes != a.notes || b.body != a.body
        }
        return false
    }
}
