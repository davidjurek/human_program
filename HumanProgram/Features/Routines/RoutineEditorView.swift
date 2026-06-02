import SwiftUI
import SwiftData
import DSKit
import UIKit

// Routine editor — same setup as the Exercise editor (pushed page, inline rows
// with rename / hold-reorder / swipe-delete / add, shared interaction infra) plus
// a name field and a single-emoji picker. Opens in READ mode; Edit/Done toggles
// (top-right). A trash appears in the toolbar in edit mode to delete the routine.
struct RoutineEditorView: View {
    let routine: Routine?              // nil = new
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var working: Routine?
    @State private var editing = false
    @State private var name = ""
    @State private var emoji = ""
    @State private var items: [DraftRoutineItem] = []
    @State private var newText = ""
    // Hold-to-reorder + swipe-to-delete: the SAME shared gesture engine the Schedule,
    // Exercise and Today lists use (see EditableRowList). Wired in `body`. This was
    // the last screen still re-deriving the gesture combo by hand — which is why its
    // reorder lacked the smooth animation and a small swipe could mis-fire.
    @State private var rows = RowGestureCoordinator<UUID>(rowHeight: 56)
    @State private var editingTitleId: UUID?
    @FocusState private var titleFocused: Bool
    @State private var keyboardSpacer: CGFloat = 0
    @State private var didLoad = false
    @State private var showDiscard = false
    @State private var discarded = false

    private var repo: RoutineRepository { RoutineRepository(context: context) }

    private var isDirty: Bool {
        guard editing else { return false }
        if let r = routine { return name != r.title || emoji != r.emoji }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty || !emoji.isEmpty || !items.isEmpty
    }
    private func handleBack() {
        if isDirty { showDiscard = true } else { dismiss() }
    }
    private func discardAndDismiss() {
        showDiscard = false
        discarded = true                                             // skip commitOnLeave
        if routine == nil, let r = working { try? repo.delete(r) }   // new → delete if materialized
        working = nil
        dismiss()
    }

    var body: some View {
        // Point the shared gesture engine at the current item array + edit state.
        // Reorder/swipe are gated to edit mode via canInteract.
        rows.orderedIds = { items.map(\.id) }
        rows.moveRow = { from, to in
            let moved = items.remove(at: from); items.insert(moved, at: to)
            if let r = working { try? repo.reorderItems(items.map { $0.item }, in: r) }
        }
        rows.deleteRow = { id in
            if let it = items.first(where: { $0.id == id }) { deleteItem(it) }
        }
        rows.beginEditGesture = { commitTitleEditing(); editingTitleId = nil; titleFocused = false }
        rows.canInteract = { editing }

        return SettingsScreen(centered: true,
                       onBack: handleBack,
                       swipeBackBlocked: { isDirty },
                       scrollDisabled: rows.isInteracting,
                       manualKeyboardAvoidance: true,
                       trailing: { trailing }) {
            // Title + emoji share ONE line (emoji trailing); no separate "Emoji" row.
            // Edit and read modes use the same layout/sizes so nothing reflows. [owner]
            HStack(spacing: 8) {
                Group {
                    if editing {
                        // appScaledSize(22) matches read mode's .title2 — no size jump.
                        AppTextField(text: $name, placeholder: "Routine name", fontSize: appScaledSize(22))
                    } else {
                        DSText(name.isEmpty ? "Untitled" : name).dsTextStyle(.title2).longTitle()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if editing {
                    EmojiField(emoji: $emoji)
                } else if !emoji.isEmpty {
                    Text(emoji).font(.system(size: 28))
                }
            }

            SettingsSectionLabel(title: "Items")
            stepsList
            if editing { addRow }
            Color.clear.frame(height: keyboardSpacer)
        }
        .overlay {
            if showDiscard {
                ConfirmPopup(message: "Discard Changes?", confirmTitle: "Discard",
                             onConfirm: { discardAndDismiss() },
                             onCancel: { showDiscard = false })
            }
        }
        .onChange(of: titleFocused) { _, f in if !f { commitTitleEditing(); editingTitleId = nil } }
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
            if editing { commitNameEmoji() }
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

    // MARK: - Steps list

    private var stepsList: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                EmptyView()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, it in
                    EditableRow(coordinator: rows, id: it.id, index: index) {
                        rowFace(it: it)
                    }
                }
            }
        }
        .rowGestures(rows)
        .background(KeyboardScrollNudge())
        .keyboardSpacer($keyboardSpacer)
    }

    private func rowFace(it: DraftRoutineItem) -> some View {
        HStack(spacing: 12) {
            DSText("•").dsTextStyle(.body)
            if editing && editingTitleId == it.id {
                TextField("Item", text: textBinding(it.id))
                    .font(appFont(17)).focused($titleFocused).submitLabel(.done)
                    .onSubmit { commitTitleEditing(); editingTitleId = nil }
            } else {
                DSText(it.text.isEmpty ? "Untitled" : it.text).dsTextStyle(.body).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8).frame(height: rows.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if editing { tapText(it) } }
    }

    private var addRow: some View {
        HStack(spacing: 0) {
            TextField("Item", text: $newText).font(appFont(17)).submitLabel(.done).onSubmit(addStep)
            Spacer(minLength: 8)
            Button(action: addStep) {
                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(newText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .primary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }.buttonStyle(.plain).disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(height: 44)
    }

    // MARK: - Bindings / helpers

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { items.first(where: { $0.id == id })?.text ?? "" },
                set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = v } })
    }

    private func tapText(_ it: DraftRoutineItem) {
        guard rows.consumeTap() else { return }
        editingTitleId = it.id
        DispatchQueue.main.async { titleFocused = true }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let routine {
            working = routine
            name = routine.title; emoji = routine.emoji
            editing = false
        } else {
            // New routine: do NOT create yet. Materialize only when there's real
            // content (a name/emoji or the first item) so a blank-then-leave never
            // flashes an "Untitled" routine in the list. [#routines]
            editing = true
        }
        reloadItems()
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

    private func reloadItems() {
        guard let r = working else { items = []; return }
        items = r.items.sorted { $0.sortOrder < $1.sortOrder }
            .map { DraftRoutineItem(item: $0, text: $0.text) }
    }

    private func commitNameEmoji() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Don't materialize a routine for nothing: if there's no working routine
        // yet AND nothing was typed, there's nothing to save.
        guard working != nil || !trimmed.isEmpty || !emoji.isEmpty else { return }
        guard let r = ensureWorking() else { return }
        try? repo.update(r, title: trimmed, emoji: emoji)
    }
    private func commitTitleEditing() {
        guard let id = editingTitleId, let it = items.first(where: { $0.id == id }) else { return }
        let t = it.text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = it.item.text }; return }
        guard it.item.text != t else { return }
        try? repo.updateItem(it.item, text: t)
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = t }
    }
    private func addStep() {
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let r = ensureWorking() else { return }
        if let item = try? repo.addItem(to: r, text: t) {
            items.append(DraftRoutineItem(item: item, text: t))
        }
        newText = ""
    }
    private func deleteItem(_ it: DraftRoutineItem) {
        withAnimation(.snappy(duration: 0.2)) { items.removeAll { $0.id == it.id } }
        if let r = working { try? repo.deleteItem(it.item, from: r) }
    }
    private func deleteRoutine() {
        discarded = true                       // don't let commitOnLeave re-create it
        if let r = working { try? repo.delete(r) }
        working = nil
        dismiss()
    }
    private func commitOnLeave() {
        guard !discarded else { return }       // discarded — nothing to commit
        commitTitleEditing()
        commitNameEmoji()
        // Never persist a titleless routine (no blank "Untitled"). If nothing was
        // ever materialized (working == nil), there's nothing to delete. [#routines]
        if let r = working, r.title.trimmingCharacters(in: .whitespaces).isEmpty {
            try? repo.delete(r)
        }
    }
}

struct DraftRoutineItem: Identifiable, Equatable {
    let id = UUID()
    let item: RoutineItem
    var text: String
    static func == (l: DraftRoutineItem, r: DraftRoutineItem) -> Bool { l.id == r.id && l.text == r.text }
}
