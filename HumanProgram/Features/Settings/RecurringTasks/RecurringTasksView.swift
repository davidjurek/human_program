import SwiftUI
import SwiftData
import DSKit

// Recurring-tasks list, mirroring the Reminders list: SettingsScreen container,
// a "+" that pushes the editor, open card-less rows with a per-item active
// toggle, a 3-line title, a summary line, and the S M T W T F S strip.

struct RecurringTasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringTaskTemplate.createdAt, order: .forward)
    private var templates: [RecurringTaskTemplate]

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            NavigationLink {
                RecurringTaskEditorView(template: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
        }) {
            if templates.isEmpty {
                DSText("No recurring tasks yet")
                    .dsTextStyle(.title3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
            } else {
                ForEach(templates) { template in
                    RecurringTaskRow(template: template, onToggle: { toggle(template) })
                }
            }
        }
    }

    private func toggle(_ template: RecurringTaskTemplate) {
        do {
            try RecurringTaskRepository(context: context).update(template, active: !template.active)
            try PageRefreshService.refresh(context: context)
        } catch { print("[RecurringTasks] toggle error: \(error)") }
    }
}

private struct RecurringTaskRow: View {
    let template: RecurringTaskTemplate
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                RecurringTaskEditorView(template: template)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    DSText(template.title).dsTextStyle(.title3)
                        .lineLimit(3)
                    DSText(summary).dsTextStyle(.subheadline)
                    WeekdayStrip(days: Self.weekdays(from: template.recurrenceRule))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { template.active }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(appToggleTint)
        }
        .frame(minHeight: 52)
    }

    private var summary: String {
        let rule = template.recurrenceRule
        if let start = rule.startDate, let end = rule.endDate {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        return "Weekly"
    }

    /// Best-effort weekday set from any stored rule (handles legacy frequencies).
    private static func weekdays(from rule: RecurrenceRule) -> Set<Int> {
        switch rule.frequency {
        case .everyDay: return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekends: return [1, 7]
        default: return Set(rule.weekdays)
        }
    }
}
