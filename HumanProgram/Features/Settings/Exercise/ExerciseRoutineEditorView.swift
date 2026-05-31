import SwiftUI
import SwiftData
import DSKit
import UIKit

// Exercise routine editor, rebuilt on the planning-editor pattern (Schedule /
// Reminder / Recurring): a pushed SettingsScreen with the weekday as the header,
// an editable routine name, and an inline exercise list where each row can be
// renamed (tap), have its sets/reps edited (tap the value → wheel popup),
// hold-to-reorder, and swipe-left to reveal a trash. An add row sits at the
// bottom. Edits persist live through ExerciseRepository (no Save button — these
// seven weekday routines always exist and are edited in place).

struct ExerciseRoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let routine: ExerciseRoutine

    @State private var name = ""
    @State private var items: [DraftExercise] = []
    @State private var newText = ""

    @State private var activePopup: ActivePopup?
    @State private var anchorFrames: [String: CGRect] = [:]

    // Drag-to-reorder (vertical) — UIKit long-press, shared recognizer.
    @State private var dragInfo: ExDragInfo?
    @State private var reorderRowFrames: [UUID: CGRect] = [:]

    // Swipe-to-delete (horizontal) — UIKit pan, shared recognizer.
    @State private var swipeOpenId: UUID?
    @State private var swipeDragId: UUID?
    @State private var swipeDragX: CGFloat = 0

    // Inline title editing.
    @State private var editingTitleId: UUID?
    @FocusState private var titleFieldFocused: Bool

    @State private var keyboardSpacer: CGFloat = 0
    @State private var didLoad = false

    private let rowHeight: CGFloat = 56
    private let trashWidth: CGFloat = 72
    private let anchorSpace = "exerciseAnchorSpace"

    private enum ActivePopup: Equatable { case counts(UUID) }

    private static let fullWeekdayName: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]
    private var weekdayTitle: String {
        let weekday = routine.recurrenceRule.weekdays.first ?? 0
        return Self.fullWeekdayName[weekday] ?? "Exercise"
    }

    // MARK: - Body

    var body: some View {
        SettingsScreen(centered: true,
                       scrollDisabled: dragInfo != nil || swipeDragId != nil,
                       manualKeyboardAvoidance: true) {
            DSText(weekdayTitle)
                .dsTextStyle(.title2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

            AppTextField(text: $name, placeholder: "Routine name", fontSize: 20)

            SettingsSectionLabel(title: "Exercises")
            exerciseList
            addRow

            // Room for the keyboard-avoidance nudge to lift bottom fields.
            Color.clear.frame(height: keyboardSpacer)
        }
        .onPreferenceChange(AnchorFrameKey.self) { anchorFrames = $0 }
        .overlay { anchoredPopup }
        .coordinateSpace(.named(anchorSpace))
        .onChange(of: activePopup) { old, new in
            if case .counts(let id)? = old, new == nil { commitCounts(id) }
            if new != nil { closeSwipeIfOpen() }
        }
        .onChange(of: editingTitleId) { _, v in if v != nil { closeSwipeIfOpen() } }
        .onChange(of: name) { _, _ in closeSwipeIfOpen() }
        .onChange(of: newText) { _, _ in closeSwipeIfOpen() }
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: commitOnLeave)
    }

    // MARK: - Exercise list

    private var exerciseList: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                DSText("No exercises yet")
                    .dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 44)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, ex in
                    exerciseRow(ex: ex, index: index)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: RowFrameKey<UUID>.self,
                                                       value: [ex.id: proxy.frame(in: .global)])
                            }
                        )
                }
            }
        }
        .onPreferenceChange(RowFrameKey<UUID>.self) { reorderRowFrames = $0 }
        .background(
            ReorderRecognizer(
                rowFrames: reorderRowFrames,
                onBegan: beginReorder,
                onChanged: { dy in dragInfo?.dy = dy },
                onEnded: endReorder,
                onCancelled: { dragInfo = nil }
            )
        )
        .background(
            SwipePanRecognizer(
                rowFrames: reorderRowFrames,
                canStart: { dragInfo == nil },
                onBegan: swipeBegan,
                onChanged: swipeChanged,
                onEnded: swipeEnded
            )
        )
        .onChange(of: titleFieldFocused) { _, focused in
            if !focused { commitTitleEditing(); editingTitleId = nil }
        }
        .background(KeyboardScrollNudge())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let f = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) { keyboardSpacer = f.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardSpacer = 0 }
        }
    }

    private func exerciseRow(ex: DraftExercise, index: Int) -> some View {
        let isDragging = dragInfo?.id == ex.id
        let shiftY = shiftOffset(forIndex: index)

        return GeometryReader { geo in
            HStack(spacing: 0) {
                exerciseRowContent(ex: ex)
                    .frame(width: geo.size.width, height: rowHeight)
                Button { deleteExercise(id: ex.id) } label: {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 40, height: 40)
                        Image(systemName: "trash")
                            .font(.system(size: 17)).foregroundStyle(.white)
                    }
                    .frame(width: trashWidth, height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .offset(x: swipeOffset(for: ex.id))
            .frame(width: geo.size.width, height: rowHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight)
        .offset(y: isDragging ? (dragInfo?.dy ?? 0) : shiftY)
        .animation(.snappy(duration: 0.2), value: isDragging)
        .animation(isDragging ? nil : .snappy(duration: 0.2), value: shiftY)
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 8, y: 4)
        .zIndex(isDragging ? 1 : 0)
    }

    private func exerciseRowContent(ex: DraftExercise) -> some View {
        let isEditing = editingTitleId == ex.id
        return HStack(spacing: 12) {
            Group {
                if isEditing {
                    TextField("Exercise", text: textBinding(for: ex.id))
                        .font(appFont(17))
                        .focused($titleFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { commitTitleEditing(); editingTitleId = nil }
                } else {
                    DSText(ex.text.isEmpty ? "Untitled" : ex.text)
                        .dsTextStyle(.body).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { tapText(ex) }

            Text(countsLabel(ex))
                .font(appFont(15)).foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture { tapCounts(ex) }
                .anchorFrame("counts-\(ex.id)", in: .named(anchorSpace))
        }
        .padding(.vertical, 8)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    private func countsLabel(_ ex: DraftExercise) -> String {
        switch (ex.sets, ex.reps) {
        case let (s?, r?): return "\(s) × \(r)"
        case let (s?, nil): return s == 1 ? "1 set" : "\(s) sets"
        case let (nil, r?): return r == 1 ? "1 rep" : "\(r) reps"
        case (nil, nil): return "add"
        }
    }

    /// Clean tap on the exercise text → edit it inline (or close an open swipe).
    private func tapText(_ ex: DraftExercise) {
        if swipeOpenId != nil { closeSwipe(); return }
        if editingTitleId != ex.id, dismissOpenInputIfAny() { return }
        editingTitleId = ex.id
        DispatchQueue.main.async { titleFieldFocused = true }
    }

    /// Clean tap on the counts value → open the sets/reps wheel popup.
    private func tapCounts(_ ex: DraftExercise) {
        if swipeOpenId != nil { closeSwipe(); return }
        if dismissOpenInputIfAny() { return }
        activePopup = .counts(ex.id)
    }

    // MARK: - Add row

    private var addRow: some View {
        HStack(spacing: 0) {
            TextField("Add exercise", text: $newText)
                .font(appFont(17))
                .submitLabel(.done)
                .onSubmit(addExercise)
                .frame(minHeight: 34)
            Spacer(minLength: 8)
            Button { addExercise() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(canAdd ? Color.primary : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .frame(height: 44)
    }

    private var canAdd: Bool { !newText.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Sets/reps popup

    @ViewBuilder
    private var anchoredPopup: some View {
        if case .counts(let id)? = activePopup, let rect = anchorFrames["counts-\(id)"] {
            AnchoredPopup(anchor: rect, width: 280, estimatedHeight: 200,
                          alignment: .trailing, space: .named(anchorSpace),
                          onClose: { activePopup = nil }) {
                countsEditor(id: id)
            }
        }
    }

    private func countsEditor(id: UUID) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                DSText("Sets").dsTextStyle(.caption1)
                CountWheel(value: setsBinding(for: id), range: 0...99, onRequestKeypad: {})
            }
            VStack(spacing: 0) {
                DSText("Reps").dsTextStyle(.caption1)
                CountWheel(value: repsBinding(for: id), range: 0...999, onRequestKeypad: {})
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { items.first(where: { $0.id == id })?.text ?? "" },
            set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = v } }
        )
    }
    private func setsBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { items.first(where: { $0.id == id })?.sets ?? 0 },
            set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i].sets = v == 0 ? nil : v } }
        )
    }
    private func repsBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { items.first(where: { $0.id == id })?.reps ?? 0 },
            set: { v in if let i = items.firstIndex(where: { $0.id == id }) { items[i].reps = v == 0 ? nil : v } }
        )
    }

    /// If a popup or title edit is open, dismiss it and return true — so a tap on
    /// a value/text while something is open just CLOSES it instead of opening a
    /// new editor.
    private func dismissOpenInputIfAny() -> Bool {
        if activePopup != nil { activePopup = nil; return true }
        if editingTitleId != nil {
            commitTitleEditing()
            editingTitleId = nil
            titleFieldFocused = false
            return true
        }
        return false
    }

    // MARK: - Reorder

    private func beginReorder(_ id: UUID) {
        swipeOpenId = nil
        commitTitleEditing()
        editingTitleId = nil
        titleFieldFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy(duration: 0.18)) { dragInfo = ExDragInfo(id: id, dy: 0) }
    }

    private func endReorder(_ dy: CGFloat) {
        guard let info = dragInfo, let base = items.firstIndex(where: { $0.id == info.id }) else {
            dragInfo = nil; return
        }
        let proj = projectedIndex(from: base, dy: dy)
        withAnimation(.snappy(duration: 0.22)) {
            if proj != base {
                let moved = items.remove(at: base)
                items.insert(moved, at: proj)
            }
            dragInfo = nil
        }
        if proj != base { persistOrder() }
    }

    private func projectedIndex(from base: Int, dy: CGFloat) -> Int {
        let shift = Int((dy / rowHeight).rounded())
        return max(0, min(items.count - 1, base + shift))
    }

    private func shiftOffset(forIndex i: Int) -> CGFloat {
        guard let info = dragInfo,
              let base = items.firstIndex(where: { $0.id == info.id }),
              base != i else { return 0 }
        let proj = projectedIndex(from: base, dy: info.dy)
        if base < proj, (base + 1 ... proj).contains(i) { return -rowHeight }
        if proj < base, (proj ..< base).contains(i) { return rowHeight }
        return 0
    }

    // MARK: - Swipe

    private func swipeBegan(_ id: UUID) {
        if swipeOpenId != id, swipeOpenId != nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
        }
        commitTitleEditing()
        editingTitleId = nil
        titleFieldFocused = false
        swipeDragId = id
        swipeDragX = 0
    }

    private func swipeChanged(_ tx: CGFloat) {
        guard swipeDragId != nil else { return }
        swipeDragX = tx
    }

    private func swipeEnded(_ tx: CGFloat, _ vx: CGFloat) {
        guard let id = swipeDragId else { return }
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let total = base + tx
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            swipeOpenId = (total < -trashWidth / 2) ? id : nil
            swipeDragId = nil
            swipeDragX = 0
        }
    }

    private func swipeOffset(for id: UUID) -> CGFloat {
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let raw = base + ((swipeDragId == id) ? swipeDragX : 0)
        if raw < -trashWidth {
            return -trashWidth - (-trashWidth - raw) * 0.2
        }
        return min(0, raw)
    }

    private func closeSwipe() {
        withAnimation(.snappy(duration: 0.2)) { swipeOpenId = nil }
    }
    private func closeSwipeIfOpen() {
        guard swipeOpenId != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
    }

    // MARK: - Load / persist

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        // A name equal to the weekday default shows as blank (placeholder only).
        let raw = routine.name.trimmingCharacters(in: .whitespaces)
        name = (raw == weekdayTitle) ? "" : routine.name
        items = routine.items
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { DraftExercise(item: $0, text: $0.text, sets: $0.sets, reps: $0.reps) }
    }

    private func commitOnLeave() {
        commitTitleEditing()
        if case .counts(let id)? = activePopup { commitCounts(id) }
        commitNameIfChanged()
    }

    private func commitNameIfChanged() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != routine.name else { return }
        try? ExerciseRepository(context: context).update(routine, name: trimmed)
        try? PageRefreshService.refresh(context: context)
    }

    private func commitTitleEditing() {
        guard let id = editingTitleId, let ex = items.first(where: { $0.id == id }) else { return }
        let trimmed = ex.text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            // Don't persist an empty name — revert the draft to the stored text.
            if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = ex.item.text }
            return
        }
        guard ex.item.text != trimmed else { return }
        try? ExerciseRepository(context: context).updateItem(ex.item, text: trimmed)
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = trimmed }
        try? PageRefreshService.refresh(context: context)
    }

    private func commitCounts(_ id: UUID) {
        guard let ex = items.first(where: { $0.id == id }) else { return }
        guard ex.item.sets != ex.sets || ex.item.reps != ex.reps else { return }
        try? ExerciseRepository(context: context).setItemCounts(ex.item, sets: ex.sets, reps: ex.reps)
        try? PageRefreshService.refresh(context: context)
    }

    private func addExercise() {
        let trimmed = newText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let repo = ExerciseRepository(context: context)
        if let item = try? repo.addItem(to: routine, text: trimmed) {
            items.append(DraftExercise(item: item, text: trimmed, sets: nil, reps: nil))
            try? PageRefreshService.refresh(context: context)
        }
        newText = ""
    }

    private func persistOrder() {
        try? ExerciseRepository(context: context).reorderItems(items.map { $0.item }, in: routine)
        try? PageRefreshService.refresh(context: context)
    }

    private func deleteExercise(id: UUID) {
        guard let ex = items.first(where: { $0.id == id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            items.removeAll { $0.id == id }
            swipeOpenId = nil
        }
        try? ExerciseRepository(context: context).deleteItem(ex.item, from: routine)
        try? PageRefreshService.refresh(context: context)
    }
}

/// One exercise while editing: the editor works on this plain-value draft (so
/// reorder/inline-edit stay smooth) and persists changes to the backing model.
struct DraftExercise: Identifiable, Equatable {
    let id = UUID()
    let item: ExerciseRoutineItem
    var text: String
    var sets: Int?
    var reps: Int?

    static func == (lhs: DraftExercise, rhs: DraftExercise) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.sets == rhs.sets && lhs.reps == rhs.reps
    }
}

/// Transient drag-reorder state for the exercise list.
struct ExDragInfo: Equatable {
    var id: UUID
    var dy: CGFloat
}
