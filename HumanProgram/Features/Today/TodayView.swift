import SwiftUI
import SwiftData
import DSKit
import UIKit
import EventKit

// The Today screen, rebuilt on DSKit (DailyOS-inspired): date nav + padlock,
// a Daily Schedule hour-timeline (the Settings schedule flows in) with a red
// "now" bar, Today's Tasks (checkbox + chevron → detail), and an Exercise
// reference section. Pushed from the hub; the back arrow returns there.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TodayViewModel
    @State private var showDatePicker = false
    @State private var addingTask = false
    @State private var newTask = ""
    @FocusState private var addFocused: Bool
    @State private var now = Date()
    @State private var calendarService = CalendarAdapterService()
    @State private var calendarItems: [TimelineItem] = []

    // Live "now" line moves while the page stays open.
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var selectedCalendarIds: [String] {
        UserDefaults.standard.stringArray(forKey: "selectedCalendarIds") ?? []
    }

    init(context: ModelContext) {
        _vm = State(initialValue: TodayViewModel(context: context))
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleRow
                    scheduleSection
                    tasksSection
                    if vm.isComplete { CompletionBannerView() }
                    exerciseSection
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadPage(); await loadCalendarItems() }
        .onReceive(ticker) { now = $0 }
        .onChange(of: vm.viewingDate) { _, _ in Task { await loadCalendarItems() } }
        .onDisappear { vm.relockOnLeave() }
        .sheet(isPresented: $showDatePicker) {
            TodayDatePicker(date: vm.viewingDate) { vm.jumpTo(date: $0) }
        }
    }

    // MARK: - Calendar events for the green lane

    private func loadCalendarItems() async {
        let start = Calendar.current.startOfDay(for: vm.viewingDate)
        guard !selectedCalendarIds.isEmpty else { calendarItems = []; return }
        if calendarService.authorizationStatus != .fullAccess {
            _ = await calendarService.requestAccess()
        }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let events = calendarService.fetchEvents(from: start, to: end, calendarIds: selectedCalendarIds)
        calendarItems = events.map { ev in
            TimelineItem(id: ev.eventIdentifier ?? UUID().uuidString,
                         title: ev.title ?? "(no title)",
                         startMin: minutesOfDay(ev.startDate, dayStart: start),
                         endMin: minutesOfDay(ev.endDate, dayStart: start),
                         isCalendar: true)
        }
    }

    private func minutesOfDay(_ date: Date?, dayStart: Date) -> Int {
        guard let date else { return 0 }
        let secs = date.timeIntervalSince(dayStart)
        return Int(max(0, min(1440, secs / 60)))
    }

    private var scheduleItems: [TimelineItem] {
        (vm.page?.scheduleBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { b in
            let end = b.endMinuteOfDay <= b.startMinuteOfDay ? 1440 : b.endMinuteOfDay
            return TimelineItem(id: "blk-\(b.id)", title: b.title,
                                startMin: b.startMinuteOfDay, endMin: end, isCalendar: false)
        }
    }

    // MARK: - Top bar (back + date nav)

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture { vm.relockOnLeave(); dismiss() }
            Spacer()
            HStack(spacing: 18) {
                navButton("arrow.left") { vm.goToPreviousDay() }
                navButton("arrow.right") { vm.goToNextDay() }
                Button { vm.goToToday() } label: {
                    DSText("Today").dsTextStyle(.subheadline)
                }.buttonStyle(.plain)
                navButton("calendar") { showDatePicker = true }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: - Title row + padlock

    private var titleRow: some View {
        HStack {
            DSText(longDate).dsTextStyle(.title2)
            Spacer()
            if !vm.isToday && isPast {
                PastLockButton(locked: vm.isPastLocked) {
                    Task {
                        if vm.isPastLocked { await vm.unlockPastDay() } else { await vm.relockPastDay() }
                    }
                }
            }
        }
    }

    private var isPast: Bool {
        vm.viewingDate < Calendar.current.startOfDay(for: Date())
    }

    private var longDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f.string(from: vm.viewingDate)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSText("Schedule").dsTextStyle(.headline)
            DailyTimeline(
                items: scheduleItems + calendarItems,
                showNow: vm.isToday,
                now: now
            )
        }
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSText("Tasks").dsTextStyle(.headline)

            ForEach(vm.sortedTasks) { task in
                TodayTaskRow(
                    task: task,
                    sourceLabel: vm.sourceLabel(for: task),
                    projectName: vm.projectName(for: task),
                    onToggle: { Task { await vm.toggleTask(task) } },
                    onSave: { title, notes in Task { await vm.updateTask(task, title: title, notes: notes) } }
                )
            }

            if addingTask {
                HStack(spacing: 10) {
                    TextField("New task", text: $newTask)
                        .font(appFont(17))
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(commitAdd)
                    Button(action: commitAdd) {
                        SelectionCircle(isOn: !newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }.buttonStyle(.plain).disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(height: 40)
            }

            // Centered, padded liquid-glass "Add Task" under the last task.
            if !vm.isPastLocked && !addingTask {
                HStack {
                    Spacer()
                    Button {
                        addingTask = true
                        DispatchQueue.main.async { addFocused = true }
                    } label: {
                        DSText("Add Task").dsTextStyle(.headline)
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private func commitAdd() {
        let t = newTask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { addingTask = false; return }
        vm.newTaskTitle = t
        Task { await vm.addManualTask(); await vm.loadPage() }
        newTask = ""
        addingTask = false
    }

    // MARK: - Exercise (reference only)

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSText("Exercise").dsTextStyle(.headline)
            VStack(alignment: .leading, spacing: 8) {
                if let routine = vm.exerciseRoutine, !routine.items.isEmpty {
                    ForEach(routine.items.sorted { $0.sortOrder < $1.sortOrder }) { item in
                        HStack(spacing: 10) {
                            DSText("•").dsTextStyle(.body)
                            DSText(item.text).dsTextStyle(.body)
                            Spacer()
                            if let s = item.sets, let r = item.reps {
                                DSText("\(s) × \(r)").dsTextStyle(.subheadline)
                            } else if let s = item.sets {
                                DSText("\(s) sets").dsTextStyle(.subheadline)
                            } else if let r = item.reps {
                                DSText("\(r) reps").dsTextStyle(.subheadline)
                            }
                        }
                    }
                } else {
                    DSText("There is no exercise routine for \(weekdayName).")
                        .dsTextStyle(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weekdayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: vm.viewingDate)
    }
}

// ── Past-date padlock (tap-and-hold to toggle, haptics) ─────────────────────────
struct PastLockButton: View {
    let locked: Bool
    let onToggle: () -> Void
    @State private var pressing = false

    var body: some View {
        ZStack {
            Circle().fill(locked ? Color.red : Color.green)
                .frame(width: 52, height: 52)
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(pressing ? 1.15 : 1)   // expand on press-and-hold [#17]
        .animation(.easeOut(duration: 0.15), value: pressing)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0.6, pressing: { p in
            pressing = p
            if p { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        }, perform: {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onToggle()
        })
    }
}

// ── Today task row (checkbox + title + chevron → detail) ─────────────────────────
private struct TodayTaskRow: View {
    let task: DailyPageTask
    let sourceLabel: String
    let projectName: String
    let onToggle: () -> Void
    let onSave: (String, String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                SelectionCircle(isOn: task.completed)
            }.buttonStyle(.plain)

            NavigationLink {
                TaskDetailView(task: task, sourceLabel: sourceLabel,
                               projectName: projectName, onSave: onSave)
            } label: {
                HStack {
                    DSText(task.title).dsTextStyle(.body)
                        .strikethrough(task.completed)
                        .lineLimit(2)
                    Spacer()
                    DSChevronView()
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .frame(minHeight: 44)
    }
}

// ── Date picker (jump to a date) ────────────────────────────────────────────────
private struct TodayDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Date
    let onSelect: (Date) -> Void

    init(date: Date, onSelect: @escaping (Date) -> Void) {
        _selected = State(initialValue: date)
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 16) {
                DatePicker("", selection: $selected, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(weekdaySelectedColor)
                    .padding()
                Button {
                    onSelect(selected); dismiss()
                } label: {
                    DSText("Go").dsTextStyle(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 20)
        }
        .presentationDetents([.medium])
    }
}
