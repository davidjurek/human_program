import SwiftUI
import SwiftData
import DSKit

// Backlog task detail/editor — a full page with read + edit modes (Edit/Done
// top-right; new items start in edit with Save). Field order: Title, Project,
// Assigned Date (+toggle), Notes. No "Mark as Done"; no creation/modified dates.
struct BacklogTaskDetailView: View {
    let item: BacklogItem?              // nil = new
    var startInEdit: Bool = false
    var defaultProject: ProjectBucket? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProjectBucket.name) private var projects: [ProjectBucket]

    @State private var editing = false
    @State private var title = ""
    @State private var notes = ""
    @State private var projectId: String?
    @State private var hasDate = false
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var didLoad = false
    /// The item created in this session (so a brand-new task, after Save, behaves
    /// like an existing one — read mode, Edit/Save — instead of popping). [#28]
    @State private var savedItem: BacklogItem?
    @State private var showDiscard = false

    private var repo: BacklogRepository { BacklogRepository(context: context) }
    private var effectiveItem: BacklogItem? { item ?? savedItem }
    private var isNew: Bool { effectiveItem == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Unsaved edits relative to the persisted item (or any input for a new one).
    private var isDirty: Bool {
        let assigned = hasDate ? Calendar.current.startOfDay(for: date) : nil
        if let it = effectiveItem {
            return title != it.title
                || notes != it.notes
                || projectId != it.project?.id
                || assigned != it.assignedDate
        }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !notes.isEmpty || projectId != nil || hasDate
    }

    var body: some View {
        SettingsScreen(centered: true,
                       onBack: handleBack,
                       swipeBackBlocked: { editing && isDirty },
                       trailing: { trailingButton }) {
            SettingsSectionLabel(title: "Task")
            if editing {
                // Match read mode's .title3 size so the title doesn't reflow. [#25]
                AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20))
            } else {
                DSText(title.isEmpty ? "Untitled" : title).dsTextStyle(.title3)
                    .frame(minHeight: 34, alignment: .leading)
            }

            SettingsGroup(title: "Details") {
                // Project
                HStack {
                    DSText("Project").dsTextStyle(.body)
                    Spacer(minLength: 8)
                    if editing {
                        Menu {
                            Button("None") { projectId = nil }
                            ForEach(projects, id: \.id) { p in
                                Button(p.name) { projectId = p.id }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(projectName).font(appFont(18)).foregroundStyle(.primary)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        DSText(projectName).dsTextStyle(.subheadline)
                    }
                }
                .frame(height: 34)

                // Assigned date + toggle
                HStack {
                    DSText("Assigned Date").dsTextStyle(.body)
                    Spacer(minLength: 8)
                    if hasDate {
                        if editing {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden().tint(weekdaySelectedColor)
                        } else {
                            DSText(dateString).dsTextStyle(.subheadline)
                        }
                    } else if !editing {
                        DSText("None").dsTextStyle(.subheadline)   // [#23]
                    }
                    if editing {
                        Toggle("", isOn: $hasDate).labelsHidden().tint(appToggleTint)
                    }
                }
                .frame(height: 34)
            }

            SettingsSectionLabel(title: "Note")
            if editing {
                AppTextField(text: $notes, placeholder: "Note", fontSize: 18, multiline: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                DSText(notes).dsTextStyle(.body)   // blank when empty [#24]
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay {
            if showDiscard {
                ConfirmPopup(message: "Discard changes?",
                             confirmTitle: "Discard",
                             onConfirm: { showDiscard = false; dismiss() },
                             onCancel: { showDiscard = false })
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func handleBack() {
        if editing && isDirty { showDiscard = true } else { dismiss() }
    }

    private var trailingButton: some View {
        Group {
            if isNew {
                Button { save() } label: {
                    Text("Save").font(appFont(18))
                        .foregroundStyle(canSave ? .primary : .secondary)
                        .frame(height: 44).padding(.horizontal, 6)
                }.disabled(!canSave)
            } else {
                Button {
                    if editing { save(); editing = false } else { editing = true }
                } label: {
                    Text(editing ? "Save" : "Edit").font(appFont(18))   // [#29]
                        .foregroundStyle(.primary).frame(height: 44).padding(.horizontal, 6)
                }
            }
        }
    }

    private var projectName: String {
        guard let pid = projectId else { return "None" }
        return projects.first(where: { $0.id == pid })?.name ?? "None"
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        editing = startInEdit
        if let item {
            title = item.title
            notes = item.notes
            projectId = item.project?.id
            if let d = item.assignedDate { hasDate = true; date = d }
        } else {
            projectId = defaultProject?.id
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let project = projectId.flatMap { pid in projects.first(where: { $0.id == pid }) }
        let assigned = hasDate ? Calendar.current.startOfDay(for: date) : nil
        if let existing = effectiveItem {
            try? repo.update(existing, title: trimmed, notes: notes, project: project, assignedDate: assigned)
            // Clearing project/date isn't covered by update's non-nil contract; set directly.
            existing.project = project
            existing.assignedDate = assigned
            try? context.save()
        } else {
            // New task: create, then stay on the page in read mode. [#28]
            savedItem = try? repo.create(title: trimmed, notes: notes, project: project, assignedDate: assigned)
            editing = false
        }
    }
}
