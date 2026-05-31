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
    @State private var dragInfo: RDrag?
    @State private var reorderRowFrames: [UUID: CGRect] = [:]
    @State private var swipeOpenId: UUID?
    @State private var swipeDragX: CGFloat = 0
    @State private var swipeDragId: UUID?
    @State private var editingTitleId: UUID?
    @FocusState private var titleFocused: Bool
    @State private var keyboardSpacer: CGFloat = 0
    @State private var didLoad = false

    private let rowHeight: CGFloat = 56
    private let trashWidth: CGFloat = 68
    private var repo: RoutineRepository { RoutineRepository(context: context) }

    var body: some View {
        SettingsScreen(centered: true,
                       scrollDisabled: dragInfo != nil || swipeDragId != nil,
                       manualKeyboardAvoidance: true,
                       trailing: { trailing }) {
            if editing {
                AppTextField(text: $name, placeholder: "Routine name", fontSize: 20)
                HStack {
                    DSText("Emoji").dsTextStyle(.title3)
                    Spacer()
                    EmojiField(emoji: $emoji)
                }
            } else {
                DSText(name.isEmpty ? "Untitled" : name).dsTextStyle(.title2)
                HStack {
                    DSText("Emoji").dsTextStyle(.title3)
                    Spacer()
                    Text(emoji.isEmpty ? "—" : emoji).font(.system(size: 28))
                }
            }

            SettingsSectionLabel(title: "Steps")
            stepsList
            if editing { addRow }
            Color.clear.frame(height: keyboardSpacer)
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
            }
        }
        Button {
            if editing { commitNameEmoji() }
            editing.toggle()
        } label: {
            Text(editing ? "Done" : "Edit").font(appFont(18)).foregroundStyle(.primary)
                .frame(height: 44).padding(.horizontal, 6)
        }
    }

    // MARK: - Steps list

    private var stepsList: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                DSText("No steps yet").dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 44)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, it in
                    row(it: it, index: index)
                        .background(GeometryReader { p in
                            Color.clear.preference(key: RowFrameKey<UUID>.self, value: [it.id: p.frame(in: .global)])
                        })
                }
            }
        }
        .onPreferenceChange(RowFrameKey<UUID>.self) { reorderRowFrames = $0 }
        .background(editing ? AnyView(reorderAndSwipe) : AnyView(Color.clear))
        .background(KeyboardScrollNudge())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            if let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) { keyboardSpacer = f.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardSpacer = 0 }
        }
    }

    private var reorderAndSwipe: some View {
        ZStack {
            ReorderRecognizer(rowFrames: reorderRowFrames, onBegan: beginReorder,
                              onChanged: { dy in dragInfo?.dy = dy }, onEnded: endReorder,
                              onCancelled: { dragInfo = nil })
            SwipePanRecognizer(rowFrames: reorderRowFrames, canStart: { dragInfo == nil },
                               onBegan: swipeBegan, onChanged: { swipeDragX = $0 }, onEnded: swipeEnded)
        }
    }

    private func row(it: DraftRoutineItem, index: Int) -> some View {
        let dragging = dragInfo?.id == it.id
        return GeometryReader { geo in
            HStack(spacing: 0) {
                rowFace(it: it).frame(width: geo.size.width, height: rowHeight)
                Button { deleteItem(it) } label: {
                    ZStack { Circle().fill(Color.red).frame(width: 38, height: 38)
                        Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(.white) }
                        .frame(width: trashWidth, height: rowHeight).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .offset(x: swipeOffset(it.id))
            .frame(width: geo.size.width, height: rowHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight)
        .offset(y: dragging ? (dragInfo?.dy ?? 0) : shiftOffset(index))
        .scaleEffect(dragging ? 1.04 : 1)
        .zIndex(dragging ? 1 : 0)
    }

    private func rowFace(it: DraftRoutineItem) -> some View {
        HStack(spacing: 12) {
            DSText("•").dsTextStyle(.body)
            if editing && editingTitleId == it.id {
                TextField("Step", text: textBinding(it.id))
                    .font(appFont(17)).focused($titleFocused).submitLabel(.done)
                    .onSubmit { commitTitleEditing(); editingTitleId = nil }
            } else {
                DSText(it.text.isEmpty ? "Untitled" : it.text).dsTextStyle(.body).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8).frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if editing { tapText(it) } }
    }

    private var addRow: some View {
        HStack(spacing: 0) {
            TextField("Add step", text: $newText).font(appFont(17)).submitLabel(.done).onSubmit(addStep)
            Spacer(minLength: 8)
            Button(action: addStep) {
                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(newText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .primary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
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
        if swipeOpenId != nil { withAnimation { swipeOpenId = nil }; return }
        editingTitleId = it.id
        DispatchQueue.main.async { titleFocused = true }
    }

    private func swipeOffset(_ id: UUID) -> CGFloat {
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let raw = base + ((swipeDragId == id) ? swipeDragX : 0)
        return raw < -trashWidth ? -trashWidth - (-trashWidth - raw) * 0.2 : min(0, raw)
    }
    private func shiftOffset(_ i: Int) -> CGFloat {
        guard let info = dragInfo, let base = items.firstIndex(where: { $0.id == info.id }), base != i else { return 0 }
        let proj = projected(base, info.dy)
        if base < proj, (base + 1 ... proj).contains(i) { return -rowHeight }
        if proj < base, (proj ..< base).contains(i) { return rowHeight }
        return 0
    }
    private func projected(_ base: Int, _ dy: CGFloat) -> Int {
        max(0, min(items.count - 1, base + Int((dy / rowHeight).rounded())))
    }

    private func beginReorder(_ id: UUID) {
        swipeOpenId = nil; commitTitleEditing(); editingTitleId = nil; titleFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy(duration: 0.18)) { dragInfo = RDrag(id: id, dy: 0) }
    }
    private func endReorder(_ dy: CGFloat) {
        guard let info = dragInfo, let base = items.firstIndex(where: { $0.id == info.id }) else { dragInfo = nil; return }
        let proj = projected(base, dy)
        withAnimation(.snappy(duration: 0.22)) {
            if proj != base { let m = items.remove(at: base); items.insert(m, at: proj) }
            dragInfo = nil
        }
        if proj != base, let r = working { try? repo.reorderItems(items.map { $0.item }, in: r) }
    }
    private func swipeBegan(_ id: UUID) {
        if swipeOpenId != id { withAnimation { swipeOpenId = nil } }
        commitTitleEditing(); editingTitleId = nil; titleFocused = false
        swipeDragId = id; swipeDragX = 0
    }
    private func swipeEnded(_ tx: CGFloat, _ vx: CGFloat) {
        guard let id = swipeDragId else { return }
        let total = ((swipeOpenId == id) ? -trashWidth : 0) + tx
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            swipeOpenId = total < -trashWidth / 2 ? id : nil; swipeDragId = nil; swipeDragX = 0
        }
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
            // New routine: create immediately so steps can attach; start editing.
            working = try? repo.create(title: "")
            editing = true
        }
        reloadItems()
    }

    private func reloadItems() {
        guard let r = working else { items = []; return }
        items = r.items.sorted { $0.sortOrder < $1.sortOrder }
            .map { DraftRoutineItem(item: $0, text: $0.text) }
    }

    private func commitNameEmoji() {
        guard let r = working else { return }
        try? repo.update(r, title: name.trimmingCharacters(in: .whitespaces), emoji: emoji)
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
        guard !t.isEmpty, let r = working else { return }
        if let item = try? repo.addItem(to: r, text: t) {
            items.append(DraftRoutineItem(item: item, text: t))
        }
        newText = ""
    }
    private func deleteItem(_ it: DraftRoutineItem) {
        withAnimation(.snappy(duration: 0.2)) { items.removeAll { $0.id == it.id }; swipeOpenId = nil }
        if let r = working { try? repo.deleteItem(it.item, from: r) }
    }
    private func deleteRoutine() {
        if let r = working { try? repo.delete(r) }
        working = nil
        dismiss()
    }
    private func commitOnLeave() {
        commitTitleEditing()
        commitNameEmoji()
        // Clean up a brand-new routine left completely empty.
        if let r = working, r.title.trimmingCharacters(in: .whitespaces).isEmpty, r.items.isEmpty, r.emoji.isEmpty {
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

struct RDrag: Equatable { var id: UUID; var dy: CGFloat }
