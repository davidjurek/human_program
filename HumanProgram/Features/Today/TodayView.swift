import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @State private var vm: TodayViewModel

    init(context: ModelContext) {
        _vm = State(initialValue: TodayViewModel(context: context))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Date header
                DateHeaderView(
                    date: vm.viewingDate,
                    isToday: vm.isToday,
                    onPrevious: vm.goToPreviousDay,
                    onNext: vm.goToNextDay,
                    onToday: vm.goToToday,
                    onPickerRequested: { vm.showDatePicker = true }
                )
                .padding(.top, 4)

                // Past-lock banner
                if vm.isPastLocked {
                    pastLockBanner
                }

                // Schedule (placeholder for milestone 1)
                scheduleSection

                Divider().padding(.horizontal, 16).padding(.vertical, 8)

                // Today's Tasks
                tasksSection

                // Completion message
                if vm.isComplete {
                    CompletionBannerView()
                        .padding(.top, 8)
                }

                Divider().padding(.horizontal, 16).padding(.vertical, 8)

                // Exercise
                exerciseSection

                Spacer(minLength: 40)
            }
        }
        .background(AppColors.background)
        .sheet(isPresented: $vm.showDatePicker) {
            DatePickerSheet(selectedDate: vm.viewingDate) { date in
                vm.jumpTo(date: date)
            }
        }
        .sheet(isPresented: $vm.showAddTask) {
            AddTaskSheet(title: $vm.newTaskTitle) {
                Task { await vm.addManualTask() }
            }
        }
        .task { await vm.loadPage() }
        .refreshable { await vm.loadPage() }
    }

    // MARK: - Subviews

    private var pastLockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
            Text("This day is locked. Double-tap to edit.")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onTapGesture(count: 2) {
            Task { await vm.unlockPastDay() }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Schedule") { }
            if let blocks = vm.page?.scheduleBlocks, !blocks.isEmpty {
                ForEach(blocks.sorted { $0.sortOrder < $1.sortOrder }) { block in
                    ScheduleBlockRow(block: block)
                }
            } else {
                Text("No schedule for this day")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Required") {
                if !vm.isPastLocked {
                    Button {
                        vm.showAddTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }

            if vm.isLoading {
                ProgressView()
                    .padding(16)
            } else if vm.sortedTasks.isEmpty {
                Text("No tasks for this day")
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach(vm.sortedTasks) { task in
                    TaskRowView(task: task) {
                        Task { await vm.toggleTask(task) }
                    }
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Exercise") { }
            Text("No exercise routine")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppTypography.sectionHeader())
                .foregroundStyle(AppColors.textTertiary)
                .kerning(0.5)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// ── Schedule block row ────────────────────────────────────────────
struct ScheduleBlockRow: View {
    let block: DailyPageScheduleBlock

    var body: some View {
        HStack(spacing: 12) {
            Text(formatMinutes(block.startMinuteOfDay))
                .font(AppTypography.timeLabel())
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 40, alignment: .trailing)
            Text(block.title)
                .font(AppTypography.taskTitle())
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Text(formatMinutes(block.endMinuteOfDay))
                .font(AppTypography.timeLabel())
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = (minutes / 60) % 24
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }
}

// ── Date picker sheet ─────────────────────────────────────────────
struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Date
    let onSelect: (Date) -> Void

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        _selected = State(initialValue: selectedDate)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            DatePicker("Select date", selection: $selected, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Jump to Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            onSelect(selected)
                            dismiss()
                        }
                        .foregroundStyle(AppColors.accent)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

// ── Add task sheet ────────────────────────────────────────────────
struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    let onAdd: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Task title", text: $title)
                    .font(AppTypography.taskTitle())
                    .focused($focused)
                    .padding(12)
                    .background(AppColors.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                Spacer()
            }
            .padding(.top, 20)
            .background(AppColors.background)
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { title = ""; dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(180)])
    }
}
