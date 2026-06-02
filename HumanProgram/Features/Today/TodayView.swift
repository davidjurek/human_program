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
    // Keyboard "safety gap" — height of the bottom spacer that gives the scroll
    // range for KeyboardScrollNudge to lift the focused field (mirrors Schedule).
    @State private var keyboardSpacer: CGFloat = 0

    // Hold-to-reorder + swipe-to-delete for the task rows — the SAME shared gesture
    // engine the Schedule and Exercise editors use (see EditableRowList). Tapping a
    // row opens its detail; a vertical drag scrolls the page. Wired in `body`.
    @State private var rows = RowGestureCoordinator<String>(rowHeight: 52)
    @State private var navTask: DailyPageTask?

    // Live "now" line moves while the page stays open.
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var selectedCalendarIds: [String] {
        UserDefaults.standard.stringArray(forKey: DefaultsKey.selectedCalendarIds) ?? []
    }

    init(context: ModelContext) {
        _vm = State(initialValue: TodayViewModel(context: context))
    }

    var body: some View {
        // Point the shared gesture engine at the current task order + lock state.
        rows.orderedIds = { vm.sortedTasks.map(\.id) }
        rows.moveRow = { from, to in
            var order = vm.sortedTasks
            let moved = order.remove(at: from); order.insert(moved, at: to)
            // Synchronous write so sortedTasks reflects the new order within this
            // same transaction (rows animate without flashing back first).
            vm.reorderTasks(order)
        }
        rows.deleteRow = { id in
            if let task = vm.sortedTasks.first(where: { $0.id == id }) {
                Task { await vm.deleteTask(task) }
            }
        }
        rows.canInteract = { !vm.isPastLocked }

        return ZStack {
            SettingsBackground()
            ScrollView {
                // Uniform spacing: 22pt between every section (date→Schedule→Tasks→
                // Exercise), and 10pt between each section header and its content (set
                // on each section's own VStack). Every gap type is consistent. [owner]
                VStack(alignment: .leading, spacing: 22) {
                    titleRow
                    scheduleSection
                    tasksSection
                    exerciseSection
                    Color.clear.frame(height: 32)              // [#41] bottom inset
                    // Keyboard safety-gap room (= keyboard height). SwiftUI avoidance
                    // is OFF below, so this spacer gives the scroll range for the
                    // nudge to lift the focused "New task" field clear of the keyboard.
                    Color.clear.frame(height: keyboardSpacer)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)                             // [#41] top inset
                .background(KeyboardScrollNudge())             // 20pt gap above keyboard
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)        // disable SwiftUI auto-avoidance
            .scrollDismissesKeyboard(.interactively)           // [#46] drag-to-dismiss
            // Suspend native scrolling while a row is being dragged-to-reorder or
            // swiped, so the gesture owns the touch (Schedule does the same).
            .scrollDisabled(rows.isInteracting)
            .keyboardSpacer($keyboardSpacer)
            .navigationDestination(item: $navTask) { task in
                TaskDetailView(task: task,
                               sourceLabel: vm.sourceLabel(for: task),
                               projectName: vm.projectName(for: task),
                               onSave: { title, notes in Task { await vm.updateTask(task, title: title, notes: notes) } })
            }
            // Past-day lock/unlock pill: fixed top-right, just under the top bar (it
            // does NOT scroll with the content and never affects layout). [#16]
            .overlay(alignment: .topTrailing) {
                if !vm.isToday && isPast {
                    PastLockButton(locked: vm.isPastLocked) {
                        Task {
                            if vm.isPastLocked { await vm.unlockPastDay() } else { await vm.relockPastDay() }
                        }
                    }
                    // Right edge lined up with the calendar button's true frame edge
                    // (outer bar pad 12 + inner group pad 16 = 28). Top 0 lifts it to
                    // just under the bar, out of the date row below.
                    .padding(.trailing, 28)
                    .padding(.top, -8)
                }
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
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
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        var events: [EKEvent] = []
        if !selectedCalendarIds.isEmpty {
            if calendarService.authorizationStatus != .fullAccess {
                _ = await calendarService.requestAccess()
            }
            events = calendarService.fetchEvents(from: start, to: end, calendarIds: selectedCalendarIds)
        }

        // Events the user removed/hid from Today on this date are excluded from BOTH the
        // timeline and the Tasks list, and won't be re-added on sync. The Calendar
        // reconciliation page lists them and can restore them. [calendar sync]
        let hidden = vm.hiddenCalendarIds(for: start)
        let visible = events.filter { ev in !(ev.eventIdentifier.map { hidden.contains($0) } ?? false) }

        calendarItems = visible.map { ev in
            TimelineItem(id: ev.eventIdentifier ?? UUID().uuidString,
                         title: ev.title ?? "(no title)",
                         startMin: minutesOfDay(ev.startDate, dayStart: start),
                         endMin: minutesOfDay(ev.endDate, dayStart: start),
                         isCalendar: true)
        }

        // Flow chosen-calendar events into the Tasks list (only events with a stable
        // identifier; sorted into the calendar group by start time). An empty
        // selection syncs an empty list, which clears any prior calendar tasks.
        let taskInputs: [CalendarTaskInput] = visible.compactMap { ev in
            guard let id = ev.eventIdentifier else { return nil }
            return CalendarTaskInput(eventId: id,
                                     title: ev.title ?? "(no title)",
                                     startMinuteOfDay: minutesOfDay(ev.startDate, dayStart: start))
        }
        await vm.syncCalendarTasks(taskInputs)
    }

    private func minutesOfDay(_ date: Date?, dayStart: Date) -> Int {
        guard let date else { return 0 }
        let secs = date.timeIntervalSince(dayStart)
        return Int(max(0, min(1440, secs / 60)))
    }

    private var scheduleItems: [TimelineItem] {
        (vm.page?.scheduleBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }.flatMap { b -> [TimelineItem] in
            let color = BlockColors.color(hex: b.colorHex, title: b.title).opacity(0.55)
            let start = b.startMinuteOfDay
            let end = b.endMinuteOfDay
            if end > start {
                // Same-day block.
                return [TimelineItem(id: "blk-\(b.id)", title: b.title,
                                     startMin: start, endMin: end, isCalendar: false, color: color)]
            } else if end < start {
                // Overnight-wrapping block (e.g. Sleep 21:30→05:30): draw BOTH halves —
                // start→midnight at the bottom AND midnight→end at the top of the day —
                // instead of dropping the morning portion.
                return [
                    TimelineItem(id: "blk-\(b.id)-pm", title: b.title,
                                 startMin: start, endMin: 1440, isCalendar: false, color: color),
                    TimelineItem(id: "blk-\(b.id)-am", title: b.title,
                                 startMin: 0, endMin: end, isCalendar: false, color: color)
                ].filter { $0.endMin > $0.startMin }
            } else {
                // Zero-length block (e.g. a brand-new 00:00→00:00 Sleep): nothing to draw.
                return []
            }
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
                .a11yTapBorder(Rectangle())
                .onTapGesture { if dismissAddIfOpen() { return }; vm.relockOnLeave(); dismiss() }
            Spacer()
            HStack(spacing: 26) {                                 // [#44] spread out
                navButton("arrow.left") { vm.goToPreviousDay() }
                navButton("arrow.right") { vm.goToNextDay() }
                Button { if dismissAddIfOpen() { return }; vm.goToToday() } label: {
                    DSText("Today").dsTextStyle(.subheadline)
                        .frame(height: 44)   // full top-bar height, not just the text [owner]
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .a11yTapBorder(cornerRadius: 4)
                navButton("calendar", size: 18) { showDatePicker = true }   // [#7] 18pt glyph
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private func navButton(_ icon: String, size: CGFloat = 16, _ action: @escaping () -> Void) -> some View {
        Button(action: { if dismissAddIfOpen() { return }; action() }) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: - Title row + padlock

    private var titleRow: some View {
        // Date row only. The past-day lock pill lives as a fixed top-right overlay on
        // the scroll view (see body) so it never stretches this row or shifts anything.
        HStack {
            // Date turns green when the day is complete (replaces the old banner).
            if vm.isComplete {
                DSText(longDate).dsTextStyle(.title2, appCompleteGreen)
            } else {
                DSText(longDate).dsTextStyle(.title2)
            }
            Spacer()
        }
    }

    private var isPast: Bool {
        vm.viewingDate < Calendar.current.startOfDay(for: Date())
    }

    private var longDate: String {
        AppDateFormat.weekdayMonthDayYear(vm.viewingDate)
    }

    // MARK: - Section header

    /// Plain headline shared by the Schedule / Tasks / Exercise sections (no underline).
    private func sectionHeader(_ title: String) -> some View {
        DSText(title).dsTextStyle(.headline)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Schedule")
            DailyTimeline(
                items: scheduleItems + calendarItems,
                showNow: vm.isToday,
                now: now
            )
        }
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tasks")

            taskList

            if addingTask {
                HStack(spacing: 10) {
                    // No trailing commit circle — blank space; commit via return
                    // or by tapping out. [#8]
                    TextField("New task", text: $newTask)
                        .font(appFont(17))
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(commitAdd)
                        .onChange(of: addFocused) { _, focused in
                            // Tap-out: empty dismisses the field, text auto-adds. [#2/#9]
                            if !focused { commitAdd() }
                        }
                    Spacer(minLength: 0)
                }
                .frame(height: 40)
            }

            // "Add Task" is always visible — it never disappears. [#2]
            if !vm.isPastLocked {
                HStack {
                    Spacer()
                    Button {
                        if dismissAddIfOpen() { return }
                        addingTask = true
                        DispatchQueue.main.async { addFocused = true }
                    } label: {
                        DSText("Add Task").dsTextStyle(.headline)
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .a11yTapBorder(cornerRadius: 6)
                    }.buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .frame(minHeight: vm.sortedTasks.isEmpty ? 126 : 0, alignment: .top)   // [#4]
    }

    // Custom row list with hold-to-reorder + swipe-to-delete. The two UIKit
    // recognizers (installed on the enclosing scroll view) read each row's window
    // frame to hit-test which row a gesture began on. [reuse: EditorRowInteractions]
    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.sortedTasks.enumerated()), id: \.element.id) { index, task in
                EditableRow(coordinator: rows, id: task.id, index: index) {
                    taskRowContent(task)
                }
            }
        }
        .rowGestures(rows)
    }

    private func taskRowContent(_ task: DailyPageTask) -> some View {
        HStack(spacing: 12) {
            Button { if dismissAddIfOpen() { return }; Task { await vm.toggleTask(task) } } label: {
                SelectionCircle(isOn: task.completed)
            }
            .buttonStyle(.plain)
            .a11yTapBorder(Circle())

            // `.onTapGesture` (not a Button/NavigationLink) so a tap opens the detail
            // only on a CLEAN tap — never after a hold-reorder or a swipe.
            DSText(task.title).dsTextStyle(.body)
                .strikethrough(task.completed)
                .longTitle(lineLimit: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { tapTask(task) }
        }
        .padding(.vertical, 8)
        .frame(height: rows.rowHeight)
        .contentShape(Rectangle())
    }

    /// Clean tap on a row → open its detail. `consumeTap()` absorbs the tap if a
    /// swipe engaged or an open row needs closing first.
    private func tapTask(_ task: DailyPageTask) {
        if dismissAddIfOpen() { return }
        guard rows.consumeTap() else { return }
        navTask = task
    }

    /// While the "New task" field/keyboard is open, the first tap anywhere just
    /// dismisses it and is SWALLOWED — it must not also fire the tapped control
    /// (mirrors the editors' `dismissOpenInputIfAny`). Returns true if it absorbed
    /// the tap. [#9]
    @discardableResult
    private func dismissAddIfOpen() -> Bool {
        guard addingTask || addFocused else { return false }
        addFocused = false        // onChange(addFocused) → commitAdd closes the field
        return true
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

    private var isExerciseEmpty: Bool {
        (vm.exerciseRoutine?.items.isEmpty ?? true)
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Exercise")
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
                    // Centered within the content area's empty min-height. [#5]
                    DSText("Nothing for today")
                        .dsTextStyle(.subheadline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            // Empty content area ≈ the empty Tasks section height (header + ~100). [#5]
            .frame(maxWidth: .infinity,
                   minHeight: isExerciseEmpty ? 100 : 0,
                   alignment: isExerciseEmpty ? .center : .leading)
        }
    }
}

// ── Past-date padlock (tap-and-hold to toggle, haptics) ─────────────────────────
struct PastLockButton: View {
    let locked: Bool
    let onToggle: () -> Void
    @State private var pressing = false

    var body: some View {
        ZStack {
            Capsule().fill(locked ? Color.red : Color.green)
                .frame(width: 66, height: 32)
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(pressing ? 1.15 : 1)   // expand on press-and-hold [#17]
        .animation(.easeOut(duration: 0.15), value: pressing)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 0.6, pressing: { p in
            pressing = p
            if p { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        }, perform: {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onToggle()
        })
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
                        .contentShape(Capsule())
                        .a11yTapBorder(Capsule())
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 20)
        }
        .presentationDetents([.medium])
    }
}
