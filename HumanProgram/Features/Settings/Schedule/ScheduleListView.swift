import SwiftUI
import SwiftData

// MARK: - ScheduleListView

struct ScheduleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleTemplate.name, order: .forward)
    private var templates: [ScheduleTemplate]

    @State private var isEditMode = false
    @State private var pendingNewTemplate: ScheduleTemplate? = nil
    @State private var selectedTemplate: ScheduleTemplate? = nil
    @State private var conflictAlert: ScheduleConflictAlert? = nil

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if templates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(templates) { template in
                            ScheduleTemplateRow(
                                template: template,
                                isEditMode: isEditMode,
                                onTap: {
                                    if !isEditMode {
                                        selectedTemplate = template
                                    }
                                },
                                onDelete: {
                                    deleteTemplate(template)
                                },
                                onToggleEnabled: { newValue in
                                    toggleEnabled(template, newValue: newValue)
                                },
                                conflictAlert: $conflictAlert
                            )
                            Divider()
                                .padding(.leading, 16)
                                .foregroundStyle(AppColors.separator)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createAndPushNew()
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.accent)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if !templates.isEmpty {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditMode.toggle()
                        }
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
        }
        .navigationDestination(item: $pendingNewTemplate) { template in
            ScheduleEditorView(template: template)
        }
        .navigationDestination(item: $selectedTemplate) { template in
            ScheduleEditorView(template: template)
        }
        .alert(item: $conflictAlert) { alert in
            Alert(
                title: Text("Schedule Conflict"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(AppColors.textTertiary)
            Text("No schedules.")
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
            Text("Tap + to create one.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Actions

    private func createAndPushNew() {
        do {
            let repo = ScheduleRepository(context: context)
            let newTemplate = try repo.create(name: "New Schedule")
            pendingNewTemplate = newTemplate
        } catch {
            print("[ScheduleListView] create error: \(error)")
        }
    }

    private func deleteTemplate(_ template: ScheduleTemplate) {
        do {
            let repo = ScheduleRepository(context: context)
            try repo.delete(template)
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[ScheduleListView] delete error: \(error)")
        }
    }

    private func toggleEnabled(_ template: ScheduleTemplate, newValue: Bool) {
        template.isEnabled = newValue
        do {
            let repo = ScheduleRepository(context: context)
            if let conflict = try repo.save(template) {
                // Revert the toggle
                template.isEnabled = !newValue
                conflictAlert = ScheduleConflictAlert(
                    message: conflict.reason
                )
            } else {
                try PageRefreshService.refresh(context: context)
            }
        } catch {
            template.isEnabled = !newValue
            print("[ScheduleListView] toggle error: \(error)")
        }
    }
}

// MARK: - ScheduleConflictAlert (Identifiable wrapper for alert)

private struct ScheduleConflictAlert: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - ScheduleTemplateRow

private struct ScheduleTemplateRow: View {
    @Bindable var template: ScheduleTemplate
    let isEditMode: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: (Bool) -> Void
    @Binding var conflictAlert: ScheduleConflictAlert?

    var body: some View {
        HStack(spacing: 12) {
            // Delete button (edit mode only)
            if isEditMode {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.destructive)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Main content
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name.isEmpty ? "Untitled" : template.name)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(assignmentSummary)
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { template.isEnabled },
                set: { onToggleEnabled($0) }
            ))
            .toggleStyle(SwitchToggleStyle(tint: AppColors.accentGreen))
            .labelsHidden()
            .frame(width: 51)

            // Disclosure chevron (read mode only)
            if !isEditMode {
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .animation(.easeInOut(duration: 0.2), value: isEditMode)
    }

    // MARK: - Assignment summary

    private var assignmentSummary: String {
        // Date range takes priority
        if let start = template.customDateStart, let end = template.customDateEnd {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
        // Weekdays
        if !template.assignedWeekdays.isEmpty {
            let sorted = template.assignedWeekdays.sorted()
            return sorted.map { weekdayAbbreviation($0) }.joined(separator: ", ")
        }
        return "Unassigned"
    }

    private func weekdayAbbreviation(_ weekday: Int) -> String {
        // 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat
        let abbrevs = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let index = weekday - 1
        guard index >= 0, index < abbrevs.count else { return "?" }
        return abbrevs[index]
    }
}
