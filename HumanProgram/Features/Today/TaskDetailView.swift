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

    @State private var editing = false
    @State private var title = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        SettingsScreen(centered: true, trailing: { editButton }) {
            SettingsSectionLabel(title: "Task")
            if editing {
                AppTextField(text: $title, placeholder: "Title", fontSize: 20)
            } else {
                DSText(title.isEmpty ? "Untitled" : title).dsTextStyle(.title3)
                    .frame(minHeight: 34, alignment: .leading)
            }

            SettingsGroup(title: "Details") {
                detailRow("Source", sourceLabel)
                detailRow("Project", projectName)
            }

            SettingsSectionLabel(title: "Note")
            if editing {
                AppTextField(text: $notes, placeholder: "Note", fontSize: 18, multiline: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                DSText(notes.isEmpty ? "—" : notes).dsTextStyle(.body)
                    .frame(minHeight: 34, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            title = task.title
            notes = task.notes
            didLoad = true
        }
    }

    private var editButton: some View {
        Button {
            if editing { onSave(title.trimmingCharacters(in: .whitespaces).isEmpty ? task.title : title, notes) }
            editing.toggle()
        } label: {
            Text(editing ? "Done" : "Edit").font(appFont(18))
                .foregroundStyle(.primary).frame(height: 44).padding(.horizontal, 6)
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
