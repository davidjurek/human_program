import SwiftUI
import SwiftData

// MARK: - RecurringTaskEditorView

struct RecurringTaskEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new template; non-nil = editing an existing one
    let template: RecurringTaskTemplate?

    // Form state
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var active: Bool = true
    @State private var rule: RecurrenceRule = .daily()

    // UX state
    @State private var showUnsavedAlert = false
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    private var isNew: Bool { template == nil }
    private var isTitleValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // Dirty check — compare against original values
    private var isDirty: Bool {
        guard let t = template else {
            // New item: dirty if any non-default value has been entered
            return !title.isEmpty || !notes.isEmpty || !active == false || rule != .daily()
        }
        return title != t.title
            || notes != t.notes
            || active != t.active
            || rule != t.recurrenceRule
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleField
                        Divider().padding(.horizontal, 16)
                        notesField
                        Divider().padding(.horizontal, 16)
                        activeToggle
                        Divider().padding(.horizontal, 16)
                        recurrenceSection
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(isNew ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showUnsavedAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .font(AppTypography.bodyMediumText())
                    .foregroundStyle(isTitleValid ? AppColors.accent : AppColors.textTertiary)
                    .disabled(!isTitleValid)
                }
            }
            .alert("Discard Changes?", isPresented: $showUnsavedAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Discard them?")
            }
            .alert("Save Error", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveError ?? "An unknown error occurred.")
            }
        }
        .onAppear {
            if let t = template {
                title = t.title
                notes = t.notes
                active = t.active
                rule = t.recurrenceRule
            }
            titleFocused = isNew
        }
    }

    // MARK: - Title field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TITLE")
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.4)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            TextField("Task name", text: $title)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .focused($titleFocused)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .submitLabel(.next)
        }
    }

    // MARK: - Notes field

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOTES")
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.4)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            TextField("Optional notes", text: $notes, axis: .vertical)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(3...6)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    // MARK: - Active toggle

    private var activeToggle: some View {
        Toggle(isOn: $active) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active")
                    .font(AppTypography.bodyText())
                    .foregroundStyle(AppColors.textPrimary)
                Text(active ? "Appears on scheduled days" : "Won't appear on any day")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: AppColors.accentGreen))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Recurrence section

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECURRENCE")
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.4)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

            RecurrenceRuleEditorView(rule: $rule)
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        do {
            let repo = RecurringTaskRepository(context: context)
            if let existing = template {
                try repo.update(
                    existing,
                    title: trimmedTitle,
                    notes: notes,
                    rule: rule,
                    active: active
                )
            } else {
                try repo.create(
                    title: trimmedTitle,
                    rule: rule,
                    notes: notes,
                    active: active
                )
            }
            try PageRefreshService.refresh(context: context)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
