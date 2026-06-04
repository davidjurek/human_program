import SwiftUI
import SwiftData
import DSKit

// Recurring-task editor, built on the same pattern as the Reminder editor:
// SettingsScreen container, upper-right Save (disabled until valid), swipe-back,
// and a discard-changes guard that stays quiet when nothing was entered.
//
// Layout: Title · Repeat (Weekly | Custom range) · 7-day circles (always) ·
// From/To calendar popups (custom range only) · Note.

struct RecurringTaskEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new template; non-nil = editing an existing one.
    let template: RecurringTaskTemplate?

    @State private var title = ""
    @State private var notes = ""
    @State private var repeatMode = "weekly"          // "weekly" | "custom"
    @State private var weekdays: Set<Int> = []
    @State private var fromDate = Calendar.current.startOfDay(for: Date())
    @State private var toDate = Calendar.current.startOfDay(for: Date())
    @State private var activePicker: ActivePicker?            // drives the repeat popup
    @State private var anchorFrames: [String: CGRect] = [:]   // value frames for anchoring
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var original = RecurringTaskSnapshot()
    @State private var didLoad = false

    // One coordinate space shared by the anchor tags and the popup (matches the
    // Schedule editor's pattern). [#popup]
    private let anchorSpace = "recurringAnchorSpace"
    private enum ActivePicker: Equatable { case repeatMode }
    private let repeatOptions: [(value: String, title: String)] =
        [("weekly", "Weekly"), ("custom", "Custom range")]
    private var repeatTitle: String {
        repeatOptions.first { $0.value == repeatMode }?.title ?? ""
    }

    private var canSave: Bool {
        // Needs a title AND at least one weekday selected (both modes use weekdays).
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty
    }

    private var currentSnapshot: RecurringTaskSnapshot {
        RecurringTaskSnapshot(title: title, notes: notes, repeatMode: repeatMode,
                              weekdays: weekdays, fromDate: fromDate, toDate: toDate)
    }

    private var hasUnsavedChanges: Bool {
        // New item: only if it has enough to save. Existing: if anything changed.
        template == nil ? canSave : (currentSnapshot != original)
    }

    private func attemptBack() {
        if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() }
    }

    var body: some View {
        SettingsScreen(centered: true, onBack: attemptBack,
                       swipeBackBlocked: { hasUnsavedChanges }, trailing: { editorButtons }) {
            // Title
            AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20))

            // Repeat — tappable value that opens a shared anchored popup. [#popup]
            repeatRow

            // Days (always shown)
            WeekdayCircleSelector(selected: $weekdays)

            // Custom range: From/To calendar popups
            if repeatMode == "custom" {
                DateFieldRow(label: "From", date: $fromDate)
                DateFieldRow(label: "To", date: $toDate, notBefore: fromDate)
            }

            // Note — at the bottom so it can grow without moving the controls above.
            AppTextField(text: $notes, placeholder: "Note", fontSize: appScaledSize(18), multiline: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onPreferenceChange(AnchorFrameKey.self) { anchorFrames = $0 }
        .overlay {
            if showDeleteConfirm {
                ConfirmPopup(
                    message: "Delete task?",
                    confirmTitle: "Delete",
                    onConfirm: { deleteTask() },
                    onCancel: { showDeleteConfirm = false }
                )
            }
            anchoredPopup
        }
        .discardChangesGuard(isPresented: $showDiscardConfirm) { dismiss() }   // [#197]
        .coordinateSpace(.named(anchorSpace))
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Repeat picker (shared anchored popup)

    private var repeatRow: some View {
        HStack {
            DSText("Repeat").dsTextStyle(.title3)
            Spacer(minLength: 8)
            Button { activePicker = activePicker == .repeatMode ? nil : .repeatMode } label: {
                HStack(spacing: 4) {
                    Text(repeatTitle).font(appFont(18)).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .a11yTapBorder(cornerRadius: 4)
            .anchorFrame("repeat", in: .named(anchorSpace))
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var anchoredPopup: some View {
        if activePicker == .repeatMode, let rect = anchorFrames["repeat"] {
            AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 112,
                          alignment: .trailing, space: .named(anchorSpace),
                          onClose: { activePicker = nil }) {
                repeatOptionList
            }
        }
    }

    private var repeatOptionList: some View {
        VStack(spacing: 0) {
            ForEach(repeatOptions, id: \.value) { option in
                Button {
                    repeatMode = option.value
                    activePicker = nil
                } label: {
                    HStack(spacing: 12) {
                        Text(option.title).font(appFont(18)).foregroundStyle(.primary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        if option.value == repeatMode {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var editorButtons: some View {
        if template != nil {
            EditorDeleteButton { showDeleteConfirm = true }
        }
        EditorSaveButton(enabled: canSave) { save() }
    }

    // MARK: - Load / Save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        defer { original = currentSnapshot }
        guard let t = template else { return }
        title = t.title
        notes = t.notes
        weekdays = t.recurrenceRule.highlightedWeekdays
        if t.recurrenceRule.startDate != nil || t.recurrenceRule.endDate != nil {
            repeatMode = "custom"
            fromDate = t.recurrenceRule.startDate ?? Calendar.current.startOfDay(for: Date())
            toDate = t.recurrenceRule.endDate ?? fromDate
        } else {
            repeatMode = "weekly"
        }
    }

    private func makeRule() -> RecurrenceRule {
        let days = weekdays.sorted()
        if repeatMode == "custom" {
            return RecurrenceRule(frequency: .selectedWeekdays, weekdays: days,
                                  startDate: Calendar.current.startOfDay(for: fromDate),
                                  endDate: Calendar.current.startOfDay(for: toDate))
        }
        return RecurrenceRule(frequency: .selectedWeekdays, weekdays: days)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !weekdays.isEmpty else { return }
        let repo = RecurringTaskRepository(context: context)
        do {
            if let existing = template {
                // Leave `active` unchanged (controlled from the list toggle).
                let before = RecurringSnapshot(existing)
                try repo.update(existing, title: trimmed, notes: notes, rule: makeRule())
                Undo.edited("Edit recurring task " + undoTitle(trimmed), before: before,
                            after: RecurringSnapshot(existing), post: .pageRefresh)
            } else {
                let created = try repo.create(title: trimmed, rule: makeRule(), notes: notes, active: true)
                Undo.created("Add recurring task " + undoTitle(trimmed), RecurringSnapshot(created), post: .pageRefresh)
            }
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[RecurringTaskEditor] save error: \(error)")
        }
        dismiss()
    }

    private func deleteTask() {
        showDeleteConfirm = false
        guard let template else { return }
        do {
            let before = RecurringSnapshot(template)
            try RecurringTaskRepository(context: context).delete(template)
            Undo.deleted("Delete recurring task " + undoTitle(before.title), before, post: .pageRefresh)
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[RecurringTaskEditor] delete error: \(error)")
        }
        dismiss()
    }
}

/// Snapshot of the editable fields, to detect unsaved changes.
private struct RecurringTaskSnapshot: Equatable {
    var title = ""
    var notes = ""
    var repeatMode = "weekly"
    var weekdays: Set<Int> = []
    var fromDate = Calendar.current.startOfDay(for: Date())
    var toDate = Calendar.current.startOfDay(for: Date())
}
