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
    @State private var openSection: String?
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var original = RecurringTaskSnapshot()
    @State private var didLoad = false

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
        SettingsScreen(centered: true, onBack: attemptBack, trailing: { editorButtons }) {
            // Title
            AppTextField(text: $title, placeholder: "Title", fontSize: 20)

            // Repeat
            AppDropdown(
                label: "Repeat",
                options: [("weekly", "Weekly"), ("custom", "Custom range")],
                selection: $repeatMode,
                openSection: $openSection,
                id: "repeat"
            )

            // Days (always shown)
            WeekdayCircleSelector(selected: $weekdays)

            // Custom range: From/To calendar popups
            if repeatMode == "custom" {
                DateFieldRow(label: "From", date: $fromDate)
                DateFieldRow(label: "To", date: $toDate, notBefore: fromDate)
            }

            // Note — at the bottom so it can grow without moving the controls above.
            AppTextField(text: $notes, placeholder: "Note", fontSize: 20, multiline: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay {
            if showDeleteConfirm {
                ConfirmPopup(
                    message: "Delete task?",
                    confirmTitle: "Delete",
                    onConfirm: { deleteTask() },
                    onCancel: { showDeleteConfirm = false }
                )
            }
            if showDiscardConfirm {
                ConfirmPopup(
                    message: "Discard Changes?",
                    confirmTitle: "Discard",
                    onConfirm: { dismiss() },
                    onCancel: { showDiscardConfirm = false }
                )
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    @ViewBuilder
    private var editorButtons: some View {
        if template != nil {
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
            }
        }
        Button { save() } label: {
            Text("Save").font(appFont(18))
                .foregroundStyle(canSave ? .primary : .secondary)
                .frame(height: 44)
                .padding(.horizontal, 6)
        }
        .disabled(!canSave)
    }

    // MARK: - Load / Save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        defer { original = currentSnapshot }
        guard let t = template else { return }
        title = t.title
        notes = t.notes
        weekdays = Self.weekdays(from: t.recurrenceRule)
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
                try repo.update(existing, title: trimmed, notes: notes, rule: makeRule())
            } else {
                try repo.create(title: trimmed, rule: makeRule(), notes: notes, active: true)
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
            try RecurringTaskRepository(context: context).delete(template)
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[RecurringTaskEditor] delete error: \(error)")
        }
        dismiss()
    }

    /// Best-effort weekday set from any stored rule (handles legacy frequencies).
    private static func weekdays(from rule: RecurrenceRule) -> Set<Int> {
        switch rule.frequency {
        case .everyDay: return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekends: return [1, 7]
        default: return Set(rule.weekdays)
        }
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
