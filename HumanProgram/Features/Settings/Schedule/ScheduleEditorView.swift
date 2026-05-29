import SwiftUI
import SwiftData

// MARK: - ScheduleEditorView

struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var template: ScheduleTemplate

    // Local edit state — seeded from template on appear, committed on Save
    @State private var name: String = ""
    @State private var isEnabled: Bool = true
    @State private var assignmentMode: AssignmentMode = .weekdays
    @State private var selectedWeekdays: [Int] = []
    @State private var customDateStart: Date = Calendar.current.startOfDay(for: Date())
    @State private var customDateEnd: Date = Calendar.current.startOfDay(for: Date())

    // Block editing sheets
    @State private var showSleepEditor = false
    @State private var blockToEdit: ScheduleBlock? = nil
    @State private var showAddBlock = false

    // Edit mode for block deletion / reorder
    @State private var isEditMode = false

    // Error and conflict state
    @State private var conflictMessage: String? = nil
    @State private var saveError: String? = nil

    @FocusState private var nameFocused: Bool

    private enum AssignmentMode: String, CaseIterable {
        case weekdays = "Weekdays"
        case dateRange = "Date Range"
    }

    private var sortedBlocks: [ScheduleBlock] {
        template.blocks.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var nonSleepBlocks: [ScheduleBlock] {
        sortedBlocks.filter { $0.title != "Sleep" }
    }

    private var sleepBlock: ScheduleBlock? {
        template.blocks.first { $0.title == "Sleep" }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameSection
                    divider()
                    enabledSection
                    divider()
                    assignmentSection
                    divider()
                    blocksSection
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(name.isEmpty ? "New Schedule" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    save()
                }
                .font(AppTypography.bodyMediumText())
                .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.textTertiary : AppColors.accent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                if !sortedBlocks.isEmpty {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditMode.toggle()
                        }
                    }
                    .foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showSleepEditor) {
            if let sleep = sleepBlock {
                SleepBlockEditorSheet(
                    template: template,
                    initialBedtime: sleep.startMinuteOfDay,
                    initialWake: sleep.endMinuteOfDay
                )
            }
        }
        .sheet(item: $blockToEdit) { block in
            ScheduleBlockEditorSheet(
                template: template,
                existingBlock: block,
                startMinuteOfDay: block.startMinuteOfDay
            )
        }
        .sheet(isPresented: $showAddBlock) {
            let startMinute = sortedBlocks.last?.endMinuteOfDay ?? (5 * 60 + 30)
            ScheduleBlockEditorSheet(
                template: template,
                existingBlock: nil,
                startMinuteOfDay: startMinute
            )
        }
        .alert("Schedule Conflict", isPresented: Binding(
            get: { conflictMessage != nil },
            set: { if !$0 { conflictMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(conflictMessage ?? "")
        }
        .alert("Save Error", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "An unknown error occurred.")
        }
        .onAppear {
            syncFromTemplate()
        }
    }

    // MARK: - Name section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("NAME")
                .padding(.horizontal, 16)
                .padding(.top, 14)
            TextField("Schedule name", text: $name)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .focused($nameFocused)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .submitLabel(.done)
        }
    }

    // MARK: - Enabled section

    private var enabledSection: some View {
        Toggle(isOn: $isEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enabled")
                    .font(AppTypography.bodyText())
                    .foregroundStyle(AppColors.textPrimary)
                Text(isEnabled ? "Applied on assigned days" : "Not applied to any day")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: AppColors.accentGreen))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Assignment section

    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("ASSIGNMENT")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Segmented control
            Picker("Assignment mode", selection: $assignmentMode) {
                ForEach(AssignmentMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            if assignmentMode == .weekdays {
                weekdayToggleRow
                    .padding(.bottom, 14)
            } else {
                dateRangeRows
                    .padding(.bottom, 14)
            }
        }
    }

    private var weekdayToggleRow: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { wd in
                DayToggleButton(
                    label: singleDayLetter(wd),
                    isSelected: selectedWeekdays.contains(wd),
                    action: { toggleWeekday(wd) }
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private var dateRangeRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("FROM")
                }
                Spacer()
                DatePicker("", selection: $customDateStart, displayedComponents: .date)
                    .labelsHidden()
                    .accentColor(AppColors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("TO")
                }
                Spacer()
                DatePicker("", selection: $customDateEnd, in: customDateStart..., displayedComponents: .date)
                    .labelsHidden()
                    .accentColor(AppColors.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Blocks section

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("BLOCKS")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if sortedBlocks.isEmpty {
                Text("No blocks yet.")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                // Sleep block (always first, not deletable)
                if let sleep = sleepBlock {
                    sleepBlockRow(sleep)
                    divider()
                }

                // Non-sleep blocks
                ForEach(nonSleepBlocks) { block in
                    blockRow(block)
                    divider()
                }
            }

            // Add block button
            Button {
                showAddBlock = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.accent)
                    Text("Add Block")
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sleep block row

    private func sleepBlockRow(_ block: ScheduleBlock) -> some View {
        HStack(spacing: 12) {
            // Time label
            Text(minutesToTimeString(block.startMinuteOfDay))
                .font(AppTypography.timeLabel())
                .foregroundStyle(AppColors.textTertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(minutesToTimeString(block.startMinuteOfDay)) – \(minutesToTimeString(block.endMinuteOfDay))")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            // Duration
            Text(formatDuration(block.durationMinutes))
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)

            // Chevron
            Image(systemName: "chevron.right")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            showSleepEditor = true
        }
    }

    // MARK: - Regular block row

    private func blockRow(_ block: ScheduleBlock) -> some View {
        HStack(spacing: 12) {
            // Delete button (edit mode only)
            if isEditMode {
                Button {
                    deleteBlock(block)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.destructive)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Time label
            Text(minutesToTimeString(block.startMinuteOfDay))
                .font(AppTypography.timeLabel())
                .foregroundStyle(AppColors.textTertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)

            // Title + time range
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(minutesToTimeString(block.startMinuteOfDay)) – \(minutesToTimeString(block.endMinuteOfDay))")
                    .font(AppTypography.taskMeta())
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            // Duration
            Text(formatDuration(block.durationMinutes))
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)

            if isEditMode {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                // Chevron
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                blockToEdit = block
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditMode)
    }

    // MARK: - Helpers

    private func divider() -> some View {
        Divider()
            .padding(.leading, 16)
            .foregroundStyle(AppColors.separator)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.sectionHeader())
            .foregroundStyle(AppColors.textTertiary)
            .kerning(0.4)
    }

    private func singleDayLetter(_ weekday: Int) -> String {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let idx = weekday - 1
        guard idx >= 0, idx < letters.count else { return "?" }
        return letters[idx]
    }

    private func toggleWeekday(_ weekday: Int) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.removeAll { $0 == weekday }
        } else {
            selectedWeekdays.append(weekday)
        }
    }

    // MARK: - Sync

    private func syncFromTemplate() {
        name = template.name
        isEnabled = template.isEnabled

        if template.customDateStart != nil || template.customDateEnd != nil {
            assignmentMode = .dateRange
            customDateStart = template.customDateStart ?? Calendar.current.startOfDay(for: Date())
            customDateEnd = template.customDateEnd ?? Calendar.current.startOfDay(for: Date())
        } else {
            assignmentMode = .weekdays
            selectedWeekdays = template.assignedWeekdays
        }
    }

    private func commitToTemplate() {
        template.name = name.trimmingCharacters(in: .whitespaces)
        template.isEnabled = isEnabled

        if assignmentMode == .weekdays {
            template.assignedWeekdays = selectedWeekdays
            template.customDateStart = nil
            template.customDateEnd = nil
        } else {
            template.assignedWeekdays = []
            template.customDateStart = customDateStart
            template.customDateEnd = customDateEnd
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        commitToTemplate()

        do {
            let repo = ScheduleRepository(context: context)
            if let conflict = try repo.save(template) {
                conflictMessage = conflict.reason
                return
            }
            try PageRefreshService.refresh(context: context)
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Delete block

    private func deleteBlock(_ block: ScheduleBlock) {
        do {
            let repo = ScheduleRepository(context: context)
            try repo.deleteBlock(block, from: template)
            try PageRefreshService.refresh(context: context)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Formatting helpers (file-private)

func minutesToTimeString(_ minutes: Int) -> String {
    let totalMinutes = ((minutes % 1440) + 1440) % 1440
    let hours = totalMinutes / 60
    let mins = totalMinutes % 60
    return String(format: "%02d:%02d", hours, mins)
}

func formatDuration(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h > 0 && m > 0 {
        return "\(h)h \(m)m"
    } else if h > 0 {
        return "\(h)h"
    } else {
        return "\(m)m"
    }
}
