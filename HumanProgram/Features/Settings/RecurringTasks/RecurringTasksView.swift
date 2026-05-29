import SwiftUI
import SwiftData

// MARK: - RecurringTasksView

struct RecurringTasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringTaskTemplate.createdAt, order: .forward)
    private var templates: [RecurringTaskTemplate]

    @State private var isEditMode = false
    @State private var showAddSheet = false
    @State private var selectedTemplate: RecurringTaskTemplate?

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if templates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(templates) { template in
                            RecurringTaskRow(
                                template: template,
                                isEditMode: isEditMode,
                                onTap: {
                                    if !isEditMode {
                                        selectedTemplate = template
                                    }
                                },
                                onDelete: {
                                    deleteTemplate(template)
                                }
                            )
                            Divider()
                                .padding(.leading, 52)
                                .foregroundStyle(AppColors.separator)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle("Recurring Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
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
        .sheet(isPresented: $showAddSheet) {
            RecurringTaskEditorView(template: nil)
        }
        .sheet(item: $selectedTemplate) { template in
            RecurringTaskEditorView(template: template)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "repeat")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(AppColors.textTertiary)
            Text("No recurring tasks.")
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
            Text("Tap + to add one.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Delete

    private func deleteTemplate(_ template: RecurringTaskTemplate) {
        do {
            let repo = RecurringTaskRepository(context: context)
            try repo.delete(template)
            try PageRefreshService.refresh(context: context)
        } catch {
            // Non-critical: log and continue
            print("[RecurringTasksView] delete error: \(error)")
        }
    }
}

// MARK: - RecurringTaskRow

private struct RecurringTaskRow: View {
    let template: RecurringTaskTemplate
    let isEditMode: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

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

            // Active indicator circle
            Circle()
                .fill(template.active ? AppColors.accentGreen : AppColors.textTertiary.opacity(0.35))
                .frame(width: 10, height: 10)
                .padding(.leading, isEditMode ? 0 : 6)

            // Title + weekday summary
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(weekdaySummary(for: template.recurrenceRule))
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            // "Off" badge
            if !template.active {
                Text("Off")
                    .font(AppTypography.sectionHeader())
                    .foregroundStyle(AppColors.accentOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.accentOrange.opacity(0.12))
                    .clipShape(Capsule())
            }

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
}

// MARK: - Weekday summary helper

func weekdaySummary(for rule: RecurrenceRule) -> String {
    switch rule.frequency {
    case .everyDay:
        return "Every day"
    case .weekdays:
        return "Weekdays"
    case .weekends:
        return "Weekends"
    case .selectedWeekdays:
        if rule.weekdays.isEmpty { return "No days selected" }
        let sorted = rule.weekdays.sorted()
        return sorted.map { weekdayAbbrev($0) }.joined(separator: ", ")
    case .everyNDays:
        let n = max(2, rule.interval)
        return "Every \(n) days"
    case .everyNWeeks:
        let n = max(2, rule.interval)
        if rule.weekdays.isEmpty {
            return "Every \(n) weeks"
        }
        let days = rule.weekdays.sorted().map { weekdayAbbrev($0) }.joined(separator: ", ")
        return "Every \(n) weeks on \(days)"
    case .everyOtherDay:
        return "Every other day"
    case .fourDaySplit:
        return "4-day split"
    }
}

private func weekdayAbbrev(_ weekday: Int) -> String {
    // 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat
    let abbrevs = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let index = weekday - 1
    guard index >= 0, index < abbrevs.count else { return "?" }
    return abbrevs[index]
}
