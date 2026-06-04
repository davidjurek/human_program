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
    @State private var keyboardSpacer: CGFloat = 0

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
                       manualKeyboardAvoidance: true,
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
                // Project — composed from the shared settings row (one source for the
                // row height/alignment) with the read/edit trailing controls. [#128]
                SettingsRowContent(label: "Project", hasTrailingAccessory: true) {
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

                // Assigned date + toggle
                SettingsRowContent(label: "Assigned Date", hasTrailingAccessory: true) {
                    if hasDate {
                        if editing {
                            // custom DSKit calendar [#13]; value shown as 06/03/2026
                            DSDateField(date: $date, format: { AppDateFormat.numericMDY($0) })
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
            }

            SettingsSectionLabel(title: "Note")
            if editing {
                AppTextField(text: $notes, placeholder: "Note", fontSize: appScaledSize(17), multiline: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(KeyboardScrollNudge())   // lift the focused field above the keyboard
            } else {
                DSText(notes).dsTextStyle(.body)   // blank when empty [#24]
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Scroll room so the focused field can lift clear of the keyboard.
            Color.clear.frame(height: keyboardSpacer)
        }
        .keyboardSpacer($keyboardSpacer)
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
        AppDateFormat.userPreferred(date)   // matches the Date Format setting
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
            let before = BacklogItemSnapshot(existing)
            try? repo.setDetails(existing, title: trimmed, notes: notes, project: project, assignedDate: assigned)
            let desc = Self.editDescription(before: before, newTitle: trimmed, newNotes: notes,
                                            newProject: project, newDate: assigned)
            Undo.edited(desc, before: before, after: BacklogItemSnapshot(existing))
        } else {
            // New task: create, then stay on the page in read mode. [#28]
            let created = try? repo.create(title: trimmed, notes: notes, project: project, assignedDate: assigned)
            savedItem = created
            editing = false
            if let created { Undo.created("Add backlog item " + undoTitle(trimmed), BacklogItemSnapshot(created)) }
        }
    }

    /// A specific undo label for a backlog edit: states exactly WHAT changed
    /// (renamed, note added/edited/removed, moved/unfiled, date added/removed/changed).
    /// One change → a self-contained phrase; several → "Edit “Title”: a, b".
    private static func editDescription(before: BacklogItemSnapshot, newTitle: String,
                                        newNotes: String, newProject: ProjectBucket?,
                                        newDate: Date?) -> String {
        let name = undoTitle(newTitle)
        // (full self-contained phrase, terse fragment for the combined form)
        var changes: [(full: String, short: String)] = []

        if before.title != newTitle {
            changes.append(("Rename " + undoTitle(before.title) + " to " + name, "renamed"))
        }
        if before.notes != newNotes {
            if before.notes.isEmpty {
                changes.append(("Add note to " + name, "note added"))
            } else if newNotes.isEmpty {
                changes.append(("Remove note from " + name, "note removed"))
            } else {
                changes.append(("Edit note of " + name, "note edited"))
            }
        }
        if before.projectId != newProject?.id {
            if let p = newProject {
                changes.append(("Move " + name + " to " + undoTitle(p.name), "moved to " + undoTitle(p.name)))
            } else {
                changes.append(("Remove " + name + " from project", "unfiled"))
            }
        }
        if before.assignedDate != newDate {
            if before.assignedDate == nil, let d = newDate {
                let md = AppDateFormat.monthDay(d)
                changes.append(("Add date \(md) to " + name, "date added \(md)"))
            } else if newDate == nil {
                changes.append(("Remove date from " + name, "date removed"))
            } else if let d = newDate {
                let md = AppDateFormat.monthDay(d)
                changes.append(("Change date of " + name + " to \(md)", "date → \(md)"))
            }
        }

        if changes.isEmpty { return "Edit backlog item " + name }
        if changes.count == 1 { return changes[0].full }
        return "Edit " + name + ": " + changes.map(\.short).joined(separator: ", ")
    }
}
