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

    private var repo: BacklogRepository { BacklogRepository(context: context) }
    private var isNew: Bool { item == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SettingsScreen(centered: true, trailing: { trailingButton }) {
            SettingsSectionLabel(title: "Task")
            if editing {
                AppTextField(text: $title, placeholder: "Title", fontSize: 20)
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
                DSText(notes.isEmpty ? "—" : notes).dsTextStyle(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: loadIfNeeded)
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
                    if editing { save() }
                    editing.toggle()
                } label: {
                    Text(editing ? "Done" : "Edit").font(appFont(18))
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
        let assigned = hasDate ? date : nil
        if let item {
            try? repo.update(item, title: trimmed, notes: notes, project: project, assignedDate: assigned)
            // Clearing project/date isn't covered by update's non-nil contract; set directly.
            item.project = project
            item.assignedDate = assigned.map { Calendar.current.startOfDay(for: $0) }
            try? context.save()
        } else {
            try? repo.create(title: trimmed, notes: notes, project: project, assignedDate: assigned)
            dismiss()
        }
    }
}
