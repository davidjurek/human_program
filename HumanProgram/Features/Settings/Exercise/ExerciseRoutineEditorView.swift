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

    // Tap a sets/reps wheel value → numeric keypad entry (max 30). [owner]
    @State private var countKeypad: CountTarget?
    @State private var countTyped = ""
    private struct CountTarget: Equatable { let id: UUID; let isSets: Bool }
    private let maxCount = 30

    // Hold-to-reorder + swipe-to-delete: the shared gesture engine (see
    // EditableRowList) — same state/geometry/animations as Schedule and Today.
    // Wired to the item array in `body`.
    @State private var rows = RowGestureCoordinator<UUID>(rowHeight: 56)

    // Inline title editing.
    @State private var editingTitleId: UUID?
    @FocusState private var titleFieldFocused: Bool

    @State private var keyboardSpacer: CGFloat = 0
    @State private var didLoad = false

    private let anchorSpace = "exerciseAnchorSpace"

    private enum ActivePopup: Equatable { case counts(UUID) }

    private var weekdayTitle: String {
        let weekday = routine.recurrenceRule.weekdays.first ?? 0
        return Weekday.fullName(weekday) ?? "Exercise"
    }

    // MARK: - Body

    var body: some View {
        // Point the shared gesture engine at the current item array + edit state.
        rows.orderedIds = { items.map(\.id) }
        rows.moveRow = { from, to in
            let moved = items.remove(at: from); items.insert(moved, at: to)
            // Persist AFTER the drop animation runs — PageRefreshService.refresh is
            // heavy and, run synchronously inside the reorder animation, made the
            // settle abrupt (Schedule/Today don't refresh on reorder, so they're
            // smooth). The local `items` array already reflects the new order.
            DispatchQueue.main.async { persistOrder() }
        }
        rows.deleteRow = { deleteExercise(id: $0) }
        rows.beginEditGesture = {
            commitTitleEditing(); editingTitleId = nil; titleFieldFocused = false
        }

        return SettingsScreen(centered: true,
                       scrollDisabled: rows.isInteracting,
                       manualKeyboardAvoidance: true) {
            DSText(weekdayTitle)
                .dsTextStyle(.title2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

            AppTextField(text: $name, placeholder: "Routine name", fontSize: appScaledSize(20))

            SettingsSectionLabel(title: "Exercises")
            exerciseList
            addRow

            // Room for the keyboard-avoidance nudge to lift bottom fields.
            Color.clear.frame(height: keyboardSpacer)
        }
        .onPreferenceChange(AnchorFrameKey.self) { anchorFrames = $0 }
        .overlay { anchoredPopup }
        .overlay(alignment: .bottom) {
            if countKeypad != nil {
                GlassKeypad(
                    onDigit: { d in
                        countTyped = String((countTyped + d).filter(\.isNumber).suffix(2))
                        applyCountTyped()
                    },
                    onBackspace: { countTyped = String(countTyped.dropLast()); applyCountTyped() },
                    onDone: { countKeypad = nil; countTyped = "" }
                )
                .transition(.move(edge: .bottom))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .coordinateSpace(.named(anchorSpace))
        .onChange(of: activePopup) { old, new in
            if case .counts(let id)? = old, new == nil { commitCounts(id) }
            if new != nil { rows.closeSwipeIfOpen() }
            // Closing the wheel popup also dismisses the keypad.
            if new == nil { countKeypad = nil; countTyped = "" }
        }
        .onChange(of: editingTitleId) { _, v in if v != nil { rows.closeSwipeIfOpen() } }
        .onChange(of: name) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: newText) { _, _ in rows.closeSwipeIfOpen() }
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
                    EditableRow(coordinator: rows, id: ex.id, index: index) {
                        exerciseRowContent(ex: ex)
                    }
                }
            }
        }
        .rowGestures(rows)
        .onChange(of: titleFieldFocused) { _, focused in
            if !focused { commitTitleEditing(); editingTitleId = nil }
        }
        .background(KeyboardScrollNudge())
        .keyboardSpacer($keyboardSpacer)
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
        .frame(height: rows.rowHeight)
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

    /// Clean tap on the exercise text → edit it inline. `consumeTap()` absorbs the
    /// tap if a swipe engaged or an open row needs closing first.
    private func tapText(_ ex: DraftExercise) {
        guard rows.consumeTap() else { return }
        if editingTitleId != ex.id, dismissOpenInputIfAny() { return }
        editingTitleId = ex.id
        DispatchQueue.main.async { titleFieldFocused = true }
    }

    /// Clean tap on the counts value → open the sets/reps wheel popup.
    private func tapCounts(_ ex: DraftExercise) {
        guard rows.consumeTap() else { return }
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
                    .a11yTapBorder(Rectangle())
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
        // Sets × Reps, sat close together with the × sign between (max 30 each). Tapping
        // a wheel's value opens the numeric keypad for direct entry. [owner]
        HStack(spacing: 4) {
            VStack(spacing: 0) {
                DSText("Sets").dsTextStyle(.caption1)
                CountWheel(value: setsBinding(for: id), range: 0...maxCount,
                           onRequestKeypad: { openCountKeypad(id: id, isSets: true) })
            }
            DSText("×").dsTextStyle(.title3)
            VStack(spacing: 0) {
                DSText("Reps").dsTextStyle(.caption1)
                CountWheel(value: repsBinding(for: id), range: 0...maxCount,
                           onRequestKeypad: { openCountKeypad(id: id, isSets: false) })
            }
        }
        .padding(.vertical, 4)
    }

    private func openCountKeypad(id: UUID, isSets: Bool) {
        countKeypad = CountTarget(id: id, isSets: isSets)
        countTyped = ""
    }

    private func applyCountTyped() {
        guard let t = countKeypad else { return }
        let v = min(maxCount, Int(countTyped) ?? 0)
        if t.isSets { setsBinding(for: t.id).wrappedValue = v }
        else { repsBinding(for: t.id).wrappedValue = v }
    }

    // MARK: - Bindings

    private func textBinding(for id: UUID) -> Binding<String> {
        arrayFieldBinding($items, id: id, fallback: "",
                          get: { $0.text }, set: { $0.text = $1 })
    }
    private func setsBinding(for id: UUID) -> Binding<Int> {
        arrayFieldBinding($items, id: id, fallback: 0,
                          get: { $0.sets ?? 0 }, set: { $0.sets = $1 == 0 ? nil : $1 })
    }
    private func repsBinding(for id: UUID) -> Binding<Int> {
        arrayFieldBinding($items, id: id, fallback: 0,
                          get: { $0.reps ?? 0 }, set: { $0.reps = $1 == 0 ? nil : $1 })
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
