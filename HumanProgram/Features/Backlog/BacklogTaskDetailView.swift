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
    @State private var showProjectPicker = false

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
        // A brand-new task is "dirty" only if the user actually entered something — a
        // pre-filled default project (when adding inside a folder) does NOT count, so
        // leaving an untouched new task never triggers the discard prompt. [#3]
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
            || !notes.isEmpty || hasDate || projectId != defaultProject?.id
    }

    var body: some View {
        SettingsScreen(centered: true,
                       onBack: handleBack,
                       swipeBackBlocked: { editing && isDirty },
                       trailing: { trailingButton }) {
            SettingsSectionLabel(title: "Task")
            if editing {
                // Match read mode's .title3 size AND min-height so the title
                // doesn't change size or shift position in edit mode. [#41]
                AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20), verticallyCentered: true)
                    .frame(minHeight: 34, alignment: .leading)
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
                        // Opens the shared DSKit glass project picker (not a system Menu). [#4]
                        Button { showProjectPicker = true } label: {
                            HStack(spacing: 4) {
                                DSText(projectName).dsTextStyle(.subheadline)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .a11yTapBorder(cornerRadius: 4)
                    } else {
                        DSText(projectName).dsTextStyle(.subheadline)
                    }
                }
                .frame(height: 34)

                // Assigned date + toggle
                HStack {
                    DSText("Assigned Date").dsTextStyle(.body)
                    Spacer(minLength: 8)
                    if editing {
                        // Quick-assign to today (sets the date and turns the toggle on). [#5]
                        Button {
                            hasDate = true
                            date = Calendar.current.startOfDay(for: Date())
                        } label: {
                            DSText("Today").dsTextStyle(.subheadline)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .a11yTapBorder(Capsule())
                    }
                    if hasDate {
                        if editing {
                            DSDateField(date: $date)   // custom DSKit calendar [#13]
                        } else {
                            DSText(dateString).dsTextStyle(.subheadline)
                        }
                    } else if !editing {
                        DSText("None").dsTextStyle(.subheadline)   // [#23]
                    }
                    if editing {
                        Toggle("", isOn: $hasDate).labelsHidden().tint(appToggleTint)
                            .a11yTapBorder(Capsule())
                    }
                }
                .frame(height: 34)
            }

            SettingsSectionLabel(title: "Note")
            if editing {
                AppTextField(text: $notes, placeholder: "Note", fontSize: appScaledSize(17), multiline: true)
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
            if showProjectPicker {
                MoveToProjectPopup(projects: projects,
                                   onPick: { projectId = $0?.id; showProjectPicker = false },
                                   onCancel: { showProjectPicker = false },
                                   title: "Project", noneLabel: "None")
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
                        .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .a11yTapBorder(Rectangle())
                }.disabled(!canSave)
            } else {
                Button {
                    if editing { save(); editing = false } else { editing = true }
                } label: {
                    Text(editing ? "Save" : "Edit").font(appFont(18))   // [#29]
                        .foregroundStyle(.primary).frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .a11yTapBorder(Rectangle())
                }
            }
        }
    }

    private var projectName: String {
        guard let pid = projectId else { return "None" }
        return projects.first(where: { $0.id == pid })?.name ?? "None"
    }

    private var dateString: String {
        AppDateFormat.monthDayYear(date)
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
            try? repo.setDetails(existing, title: trimmed, notes: notes, project: project, assignedDate: assigned)
        } else {
            // New task: create, then stay on the page in read mode. [#28]
            savedItem = try? repo.create(title: trimmed, notes: notes, project: project, assignedDate: assigned)
            editing = false
        }
    }
}
