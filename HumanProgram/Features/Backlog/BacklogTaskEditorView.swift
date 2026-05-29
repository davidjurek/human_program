import SwiftUI
import SwiftData

struct BacklogTaskEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// If provided, the new item will be assigned to this project by default.
    let defaultProject: ProjectBucket?

    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var selectedProjectID: String = ""    // "" = no project
    @State private var hasDate: Bool = false
    @State private var assignedDate: Date = Date()

    @FocusState private var titleFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(AppTypography.sectionHeader())
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)
                            TextField("What needs to be done?", text: $title)
                                .font(AppTypography.taskTitle())
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($titleFocused)
                                .padding(12)
                                .background(AppColors.surfaceSunken)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes (optional)")
                                .font(AppTypography.sectionHeader())
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)
                            TextField("Add notes", text: $notes)
                                .font(AppTypography.bodyText())
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(12)
                                .background(AppColors.surfaceSunken)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Project
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Project (optional)")
                                .font(AppTypography.sectionHeader())
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)
                            Picker("Project", selection: $selectedProjectID) {
                                Text("No Project").tag("")
                                ForEach(projects) { project in
                                    Text(project.name).tag(project.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.surfaceSunken)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Assigned Date
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Assigned Date (optional)")
                                .font(AppTypography.sectionHeader())
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)

                            Toggle(hasDate ? "Remove date" : "Add date", isOn: $hasDate)
                                .font(AppTypography.taskTitle())
                                .foregroundStyle(AppColors.textPrimary)
                                .tint(AppColors.accent)

                            if hasDate {
                                DatePicker("Date", selection: $assignedDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .tint(AppColors.accent)
                                    .font(AppTypography.taskTitle())
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createItem()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .font(AppTypography.buttonLabel())
                }
            }
            .onAppear {
                if let proj = defaultProject {
                    selectedProjectID = proj.id
                }
                // Delay focus slightly to allow sheet presentation to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    titleFocused = true
                }
            }
        }
    }

    // MARK: - Create

    private func createItem() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let repo = BacklogRepository(context: context)
        let project = projects.first(where: { $0.id == selectedProjectID })
        let date = hasDate ? assignedDate : nil

        try? repo.create(
            title: trimmed,
            notes: notes,
            project: project,
            assignedDate: date
        )
        try? PageRefreshService.refresh(context: context)
        dismiss()
    }
}
