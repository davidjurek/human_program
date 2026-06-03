import SwiftUI
import DSKit

// Full-page task detail reached via the chevron on a Today task. Read + edit modes
// share one layout (Edit/Done toggle, top-right). Same page for every source
// (recurring / backlog / manual / calendar). Fields: Title, Source, Project, Note.
struct TaskDetailView: View {
    let task: DailyPageTask
    let sourceLabel: String
    let projectName: String
    /// (title, notes) — called on Done.
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var title = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var showDiscard = false

    private var isDirty: Bool { title != task.title || notes != task.notes }

    var body: some View {
        // Same read/edit layout as the Backlog task detail; the only extra is the
        // read-only Source row. [#45]
        SettingsScreen(centered: true,
                       onBack: handleBack,
                       swipeBackBlocked: { editing && isDirty },
                       trailing: { editButton }) {
            SettingsSectionLabel(title: "Task")
            if editing {
                AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20), verticallyCentered: true)
                    .frame(minHeight: 34, alignment: .leading)   // match read mode → no reflow [#41]
            } else {
                // Same AppTextField, just non-editable — so the title renders through the
                // identical glyph-layout path as edit mode and sits pixel-for-pixel the
                // same (DSText vs UITextView would drift a couple px). [#41]
                AppTextField(text: .constant(title.isEmpty ? "Untitled" : title),
                             placeholder: "Title", fontSize: appScaledSize(20),
                             verticallyCentered: true, editable: false)
                    .frame(minHeight: 34, alignment: .leading)
            }

            SettingsGroup(title: "Details") {
                detailRow("Source", sourceLabel)   // read-only, both modes
                detailRow("Project", projectName)
            }

            SettingsSectionLabel(title: "Note")
            if editing {
                AppTextField(text: $notes, placeholder: "Note", fontSize: appScaledSize(17), multiline: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                DSText(notes).dsTextStyle(.body)   // blank when empty
                    .frame(minHeight: 34, alignment: .topLeading)
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
        .onAppear {
            // Seed the editable fields once. Safe because Today presents this via
            // `.navigationDestination(item: $navTask)`, which builds a FRESH view
            // instance per task — the same instance is never reused for a different
            // task, so a one-time seed can't show a stale title/notes. [#107]
            guard !didLoad else { return }
            title = task.title
            notes = task.notes
            didLoad = true
        }
    }

    private func handleBack() {
        if editing && isDirty { showDiscard = true } else { dismiss() }
    }

    private var editButton: some View {
        Button {
            if editing { onSave(title.trimmingCharacters(in: .whitespaces).isEmpty ? task.title : title, notes) }
            editing.toggle()
        } label: {
            Text(editing ? "Save" : "Edit").font(appFont(18))
                .foregroundStyle(.primary).frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                .contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            DSText(label).dsTextStyle(.body)
            Spacer(minLength: 8)
            DSText(value).dsTextStyle(.subheadline)
        }
        .frame(height: 34)
    }
}
