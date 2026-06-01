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

    // Hold-to-reorder (vertical) + swipe-to-delete (horizontal) for the task rows,
    // mirroring the Schedule editor's block list. Both are UIKit recognizers
    // installed on the enclosing scroll view (see EditorRowInteractions). Tapping a
    // row opens its detail; a vertical drag scrolls the page.
    @State private var dragInfo: TaskDragInfo?
    @State private var reorderRowFrames: [String: CGRect] = [:]   // window coords
    @State private var swipeOpenId: String?
    @State private var swipeDragId: String?
    @State private var swipeDragX: CGFloat = 0
    @State private var navTask: DailyPageTask?

    private let taskRowHeight: CGFloat = 52
    private let trashWidth: CGFloat = 72

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
                    exerciseSection
                    Color.clear.frame(height: 32)              // [#41] bottom inset
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)                             // [#41] top inset
            }
            .scrollDismissesKeyboard(.interactively)           // [#46] drag-to-dismiss
            // Suspend native scrolling while a row is being dragged-to-reorder or
            // swiped, so the gesture owns the touch (Schedule does the same).
            .scrollDisabled(dragInfo != nil || swipeDragId != nil)
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

        calendarItems = events.map { ev in
            TimelineItem(id: ev.eventIdentifier ?? UUID().uuidString,
                         title: ev.title ?? "(no title)",
                         startMin: minutesOfDay(ev.startDate, dayStart: start),
                         endMin: minutesOfDay(ev.endDate, dayStart: start),
                         isCalendar: true)
        }

        // Flow chosen-calendar events into the Tasks list (only events with a stable
        // identifier; sorted into the calendar group by start time). An empty
        // selection syncs an empty list, which clears any prior calendar tasks.
        let taskInputs: [CalendarTaskInput] = events.compactMap { ev in
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
        (vm.page?.scheduleBlocks ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { b in
            let end = b.endMinuteOfDay <= b.startMinuteOfDay ? 1440 : b.endMinuteOfDay
            return TimelineItem(id: "blk-\(b.id)", title: b.title,
                                startMin: b.startMinuteOfDay, endMin: end, isCalendar: false,
                                color: BlockColors.color(hex: b.colorHex, title: b.title)
                                    .opacity(0.55))   // [#18] block colour drives the left lane
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
                .onTapGesture { vm.relockOnLeave(); dismiss() }
            Spacer()
            HStack(spacing: 26) {                                 // [#44] spread out
                navButton("arrow.left") { vm.goToPreviousDay() }
                navButton("arrow.right") { vm.goToNextDay() }
                Button { vm.goToToday() } label: {
                    DSText("Today").dsTextStyle(.subheadline)
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
        Button(action: action) {
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
                DSText(longDate).dsTextStyle(.title2, Color(red: 0.18, green: 0.62, blue: 0.32))
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
            ForEach(vm.sortedTasks, id: \.id) { task in
                taskRow(task)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: RowFrameKey<String>.self,
                                                   value: [task.id: proxy.frame(in: .global)])
                        }
                    )
            }
        }
        .onPreferenceChange(RowFrameKey<String>.self) { reorderRowFrames = $0 }
        .background(
            ReorderRecognizer(
                rowFrames: reorderRowFrames,
                onBegan: beginReorder,
                onChanged: { dy in dragInfo?.dy = dy },
                onEnded: endReorder,
                onCancelled: { dragInfo = nil }
            )
        )
        .background(
            SwipePanRecognizer(
                rowFrames: reorderRowFrames,
                canStart: { dragInfo == nil && !vm.isPastLocked },
                onBegan: swipeBegan,
                onChanged: swipeChanged,
                onEnded: swipeEnded
            )
        )
    }

    private func taskRow(_ task: DailyPageTask) -> some View {
        let isDragging = dragInfo?.id == task.id
        let index = vm.sortedTasks.firstIndex(where: { $0.id == task.id }) ?? 0
        let shiftY = shiftOffset(forIndex: index)

        return GeometryReader { geo in
            // Content + trash lane move together, clipped, so the red trash slides in
            // from the trailing edge as you swipe (never flashes over the content).
            HStack(spacing: 0) {
                taskRowContent(task)
                    .frame(width: geo.size.width, height: taskRowHeight)
                Button { Task { await deleteTask(task) } } label: {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 40, height: 40)
                        Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(.white)
                    }
                    .frame(width: trashWidth, height: taskRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .offset(x: swipeOffset(for: task.id))
            .frame(width: geo.size.width, height: taskRowHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: taskRowHeight)
        .offset(y: isDragging ? (dragInfo?.dy ?? 0) : shiftY)
        .animation(.snappy(duration: 0.2), value: isDragging)
        .animation(isDragging ? nil : .snappy(duration: 0.2), value: shiftY)
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 8, y: 4)
        .zIndex(isDragging ? 1 : 0)
    }

    private func taskRowContent(_ task: DailyPageTask) -> some View {
        HStack(spacing: 12) {
            Button { Task { await vm.toggleTask(task) } } label: {
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
        .frame(height: taskRowHeight)
        .contentShape(Rectangle())
    }

    /// Clean tap on a row → open its detail (or just close an open swipe).
    private func tapTask(_ task: DailyPageTask) {
        if swipeOpenId != nil { closeSwipe(); return }
        navTask = task
    }

    // MARK: - Reorder / swipe handlers (mirrors ScheduleEditor)

    private func beginReorder(_ id: String) {
        guard !vm.isPastLocked else { return }
        swipeOpenId = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy(duration: 0.18)) { dragInfo = TaskDragInfo(id: id, dy: 0) }
    }

    private func endReorder(_ dy: CGFloat) {
        guard let info = dragInfo else { return }
        var order = vm.sortedTasks
        guard let base = order.firstIndex(where: { $0.id == info.id }) else { dragInfo = nil; return }
        let proj = projectedIndex(from: base, dy: dy, count: order.count)
        withAnimation(.snappy(duration: 0.22)) {
            if proj != base {
                let moved = order.remove(at: base)
                order.insert(moved, at: proj)
                // Synchronous write: sortedTasks reflects the new order within this
                // same transaction, so the rows animate into place without flashing
                // back to the old order first.
                vm.reorderTasks(order)
            }
            dragInfo = nil
        }
    }

    private func swipeBegan(_ id: String) {
        if swipeOpenId != id, swipeOpenId != nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
        }
        swipeDragId = id
        swipeDragX = 0
    }
    private func swipeChanged(_ tx: CGFloat) {
        guard swipeDragId != nil else { return }
        swipeDragX = tx
    }
    private func swipeEnded(_ tx: CGFloat, _ vx: CGFloat) {
        guard let id = swipeDragId else { return }
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let total = base + tx
        // Snap open or closed; delete is via the revealed trash, never full-swipe.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            swipeOpenId = (total < -trashWidth / 2) ? id : nil
            swipeDragId = nil
            swipeDragX = 0
        }
    }

    private func deleteTask(_ task: DailyPageTask) async {
        swipeOpenId = nil
        await vm.deleteTask(task)
    }

    private func closeSwipe() {
        withAnimation(.snappy(duration: 0.2)) { swipeOpenId = nil }
    }

    // MARK: - Reorder / swipe geometry

    private func projectedIndex(from base: Int, dy: CGFloat, count: Int) -> Int {
        let shift = Int((dy / taskRowHeight).rounded())
        return max(0, min(count - 1, base + shift))
    }

    /// Shift rows the dragged row has passed over to open a gap (array isn't mutated
    /// until the drag ends).
    private func shiftOffset(forIndex i: Int) -> CGFloat {
        guard let info = dragInfo else { return 0 }
        let order = vm.sortedTasks
        guard let base = order.firstIndex(where: { $0.id == info.id }), base != i else { return 0 }
        let proj = projectedIndex(from: base, dy: info.dy, count: order.count)
        if base < proj, (base + 1 ... proj).contains(i) { return -taskRowHeight }
        if proj < base, (proj ..< base).contains(i) { return taskRowHeight }
        return 0
    }

    /// Live horizontal offset. Clamps at the open position with a little rubber-band.
    private func swipeOffset(for id: String) -> CGFloat {
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let raw = base + ((swipeDragId == id) ? swipeDragX : 0)
        if raw < -trashWidth { return -trashWidth - (-trashWidth - raw) * 0.2 }
        return min(0, raw)
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

/// Transient drag-reorder state for a task row (driven by the UIKit reorder
/// recognizer). Keyed by the task's String id.
struct TaskDragInfo: Equatable {
    var id: String
    var dy: CGFloat
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
