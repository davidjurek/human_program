import SwiftUI
import SwiftData
import DSKit

// Schedule list, mirroring the Reminders list: SettingsScreen container, a "+"
// that pushes the editor, open card-less rows with a per-item enabled toggle,
// a 3-line title, a summary line, and the S M T W T F S strip.

struct ScheduleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleTemplate.name, order: .forward)
    private var templates: [ScheduleTemplate]

    @State private var conflictMessage: String?

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            AddNavButton { ScheduleEditorView(template: nil) }
        }) {
            if templates.isEmpty {
                DSText("No schedules yet")
                    .dsTextStyle(.title3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                ForEach(templates) { template in
                    ScheduleRow(template: template, onToggle: { toggle(template, to: $0) })
                }
            }

            if let conflictMessage {
                Text(conflictMessage)
                    .font(appFont(15)).foregroundStyle(.red)
            }
        }
    }

    private func toggle(_ template: ScheduleTemplate, to newValue: Bool) {
        template.isEnabled = newValue
        do {
            if let conflict = try ScheduleRepository(context: context).save(template) {
                template.isEnabled = !newValue   // revert
                conflictMessage = conflict.reason
            } else {
                conflictMessage = nil
                try PageRefreshService.refresh(context: context)
            }
        } catch {
            template.isEnabled = !newValue
            print("[Schedule] toggle error: \(error)")
        }
    }
}

private struct ScheduleRow: View {
    @Bindable var template: ScheduleTemplate
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ScheduleEditorView(template: template)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    DSText(template.name.isEmpty ? "Untitled" : template.name)
                        .dsTextStyle(.title3)
                        .lineLimit(3)
                    DSText(summary).dsTextStyle(.subheadline)
                    WeekdayStrip(days: Set(template.assignedWeekdays))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { template.isEnabled }, set: { onToggle($0) }))
                .labelsHidden()
                .tint(appToggleTint)
        }
        .frame(minHeight: 52)
    }

    private var summary: String {
        if let start = template.customDateStart, let end = template.customDateEnd {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        return "Weekly"
    }
}
