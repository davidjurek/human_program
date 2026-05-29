import SwiftUI
import SwiftData

struct BacklogDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: BacklogItem

    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var isEditMode: Bool = false

    // Edit state mirrors
    @State private var editTitle: String = ""
    @State private var editNotes: String = ""
    @State private var editProjectID: String = ""      // "" = no project
    @State private var editHasDate: Bool = false
    @State private var editDate: Date = Date()

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if isEditMode {
                editForm
            } else {
                readView
            }
        }
        .navigationTitle(isEditMode ? "Edit Task" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditMode)
        .toolbar { toolbarContent }
    }

    // MARK: - Read View

    private var readView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Badges row
                HStack(spacing: 8) {
                    statusBadge

                    if let project = item.project {
                        Text(project.name)
                            .font(AppTypography.taskMeta())
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Assigned date
                if let date = item.assignedDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(AppTypography.bodySmallText())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                // Notes
                if !item.notes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(AppTypography.sectionHeader())
                            .foregroundStyle(AppColors.textTertiary)
                            .textCase(.uppercase)
                        Text(item.notes)
                            .font(AppTypography.bodyText())
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 6) {
                    metaRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    metaRow(label: "Updated", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let isDone = item.status == .done
        Text(isDone ? "DONE" : "BACKLOG")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isDone ? AppColors.accentGreen : AppColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isDone ? AppColors.accentGreen : AppColors.textSecondary).opacity(0.12))
            .clipShape(Capsule())
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.taskMeta())
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.taskMeta())
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Edit Form

    private var editForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(AppTypography.sectionHeader())
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                    TextField("Task title", text: $editTitle)
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(12)
                        .background(AppColors.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(AppTypography.sectionHeader())
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                    TextEditor(text: $editNotes)
                        .font(AppTypography.bodyText())
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(AppColors.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .scrollContentBackground(.hidden)
                }

                // Project
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project")
                        .font(AppTypography.sectionHeader())
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                    Picker("Project", selection: $editProjectID) {
                        Text("No Project").tag("")
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Assigned Date
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assigned Date")
                        .font(AppTypography.sectionHeader())
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)

                    Toggle(editHasDate ? "Remove date" : "Add date", isOn: $editHasDate)
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.accent)

                    if editHasDate {
                        DatePicker("Date", selection: $editDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(AppColors.accent)
                            .font(AppTypography.taskTitle())
                    }
                }

                Divider()

                // Mark done / active
                Button {
                    toggleStatus()
                } label: {
                    HStack {
                        Image(systemName: item.status == .done ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        Text(item.status == .done ? "Mark as Active" : "Mark as Done")
                    }
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(item.status == .done ? AppColors.accent : AppColors.accentGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background((item.status == .done ? AppColors.accent : AppColors.accentGreen).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditMode {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    isEditMode = false
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                .font(AppTypography.buttonLabel())
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    populateEditState()
                    isEditMode = true
                }
                .foregroundStyle(AppColors.accent)
            }
        }
    }

    // MARK: - Helpers

    private func populateEditState() {
        editTitle = item.title
        editNotes = item.notes
        editProjectID = item.project?.id ?? ""
        if let date = item.assignedDate {
            editHasDate = true
            editDate = date
        } else {
            editHasDate = false
            editDate = Date()
        }
    }

    private func saveChanges() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        item.title = trimmed
        item.notes = editNotes
        item.assignedDate = editHasDate ? Calendar.current.startOfDay(for: editDate) : nil
        item.project = editProjectID.isEmpty ? nil : projects.first(where: { $0.id == editProjectID })
        item.updatedAt = Date()

        try? context.save()
        try? PageRefreshService.refresh(context: context)
        isEditMode = false
    }

    private func toggleStatus() {
        let repo = BacklogRepository(context: context)
        if item.status == .done {
            try? repo.markBacklog(item)
        } else {
            try? repo.markDone(item)
        }
        try? PageRefreshService.refresh(context: context)
        isEditMode = false
    }
}
