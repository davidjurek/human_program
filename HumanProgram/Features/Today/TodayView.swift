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
    // The EKEvents behind the green lane, keyed by id, so tapping a calendar block
    // in the timeline can open its event card. Schedule blocks are inert.
    @State private var calendarEvents: [String: EKEvent] = [:]
    @State private var tappedEvent: TimelineTappedEvent? = nil
    @State private var editEvent: TimelineTappedEvent? = nil
    @Environment(\.modelContext) private var modelContext
    // Keyboard "safety gap" — height of the bottom spacer that gives the scroll
    // range for KeyboardScrollNudge to lift the focused field (mirrors Schedule).
    @State private var keyboardSpacer: CGFloat = 0

    // Hold-to-reorder + swipe-to-delete for the task rows — the SAME shared gesture
    // engine the Schedule and Exercise editors use (see EditableRowList). Tapping a
    // row opens its detail; a vertical drag scrolls the page. Wired in `body`.
    @State private var rows = RowGestureCoordinator<String>(rowHeight: 52)
    @State private var navTask: DailyPageTask?
    // Today/future "differences" report: calendar events hidden from this day (the
    // recurring/backlog half comes from the view model). [today-diffs]
    @State private var calendarDiffs: [CalendarEventDifference] = []
    @State private var showDifferences = false

    // Live "now" line moves while the page stays open.
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    // Top-bar paddings, named once so the lock pill's trailing offset is DERIVED from
    // them (outer + inner) rather than a hand-typed 28 that silently misaligns if a
    // neighbor changes. [#116]
    private let topBarOuterPad: CGFloat = 12
    private let topBarInnerPad: CGFloat = 16
    private var lockPillTrailing: CGFloat { topBarOuterPad + topBarInnerPad }

    private var selectedCalendarIds: [String] {
        UserDefaults.standard.stringArray(forKey: DefaultsKey.selectedCalendarIds) ?? []
    }

    init(context: ModelContext, initialDate: Date? = nil) {
        _vm = State(initialValue: TodayViewModel(context: context, initialDate: initialDate))
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
                // Reload after the delete so the differences count updates right away
                // (calendar deletes recompute the calendar half; a full reload also
                // reassigns the page so the number never lags). [today-diffs]
                Task { await vm.deleteTask(task); await vm.loadPage(); await loadCalendarItems() }
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
                    TodayExerciseSection(routine: vm.exerciseRoutine)
                    Color.clear.frame(height: 32)              // [#41] bottom inset
                    // Keyboard safety-gap room (= keyboard height). SwiftUI avoidance
                    // is OFF below, so this spacer gives the scroll range for the
                    // nudge to lift the focused "New task" field clear of the keyboard.
                    Color.clear.frame(height: keyboardSpacer)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)                             // [#41] top inset
                // Top-right status capsule — past days: the red/green lock padlock;
                // today & future: the differences count. It lives INSIDE the scroll
                // content (same top-right spot, trailing edge derived like before) so it
                // SCROLLS WITH THE PAGE rather than floating fixed. [#16][today-diffs]
                .overlay(alignment: .topTrailing) {
                    Group {
                        if !vm.isToday && isPast {
                            PastLockButton(locked: vm.isPastLocked) {
                                Task {
                                    if vm.isPastLocked { await vm.unlockPastDay() } else { await vm.relockPastDay() }
                                }
                            }
                        } else {
                            DiffCountButton(count: differenceCount) { showDifferences = true }
                        }
                    }
                    .padding(.trailing, lockPillTrailing)
                }
                .background(KeyboardScrollNudge())             // 20pt gap above keyboard
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)        // disable SwiftUI auto-avoidance
            .scrollDismissesKeyboard(.interactively)           // [#46] drag-to-dismiss
            // Suspend native scrolling while a row is being dragged-to-reorder or
            // swiped, so the gesture owns the touch (Schedule does the same).
            // (The timeline pinch-zoom suspends the scroll itself, from inside
            // DailyTimeline — see PinchScrollLock.)
            .scrollDisabled(rows.isInteracting)
            .keyboardSpacer($keyboardSpacer)
            .navigationDestination(item: $navTask) { task in
                TaskDetailView(task: task,
                               sourceLabel: vm.sourceLabel(for: task),
                               projectName: vm.projectName(for: task),
                               onSave: { title, notes in Task { await vm.updateTask(task, title: title, notes: notes) } })
            }
            .navigationDestination(isPresented: $showDifferences) {
                TodayDifferencesView(date: vm.viewingDate)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .task { await vm.loadPage(); await loadCalendarItems() }
        .onReceive(ticker) { now = $0 }
        .onChange(of: vm.viewingDate) { _, _ in Task { await loadCalendarItems() } }
        // Returning from the differences page: reload so restored items reappear and the
        // count updates (a push keeps this view alive, so `.task` won't re-run). [today-diffs]
        .onChange(of: showDifferences) { _, shown in
            if !shown { Task { await vm.loadPage(); await loadCalendarItems() } }
        }
        // An app-wide undo/redo (shake popup) mutates the store directly; this screen
        // drives its data imperatively, so reload when one is applied — otherwise a
        // restored/re-deleted task only shows after navigating away and back. [today-undo-refresh]
        .onChange(of: UndoStore.shared.revision) { _, _ in
            Task { await vm.loadPage(); await loadCalendarItems() }
        }
        // Leaving the Today screen re-locks an unlocked past day — but a PUSH from this
        // screen (task detail, differences page) also fires onDisappear, and stepping
        // into a task on that same day is not leaving the day. Only a real exit relocks.
        // [past-unlock]
        .onDisappear {
            guard navTask == nil, !showDifferences else { return }
            vm.relockOnLeave()
        }
        .sheet(isPresented: $showDatePicker) {
            TodayDatePicker(date: vm.viewingDate, minDate: vm.minNavigableDate) { vm.jumpTo(date: $0) }
        }
        // Tapping a calendar block in the timeline opens its event card; "Edit"
        // there opens the same editor the Calendar screen uses.
        .sheet(item: $tappedEvent, onDismiss: { Task { await loadCalendarItems() } }) { wrap in
            CalendarEventDetailSheet(event: wrap.event, date: vm.viewingDate, context: modelContext,
                                     onEdit: { let e = wrap; tappedEvent = nil; editEvent = e })
        }
        .sheet(item: $editEvent, onDismiss: { Task { await loadCalendarItems() } }) { wrap in
            AddCalendarEventView(eventToEdit: wrap.event, defaultDate: vm.viewingDate,
                                 calendarService: calendarService, onSave: { Task { await loadCalendarItems() } })
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

        // Per-day local title overrides (a rename done on Today). They win over the
        // event's own title everywhere it's shown, and a rename counts as a difference.
        let overrides = vm.calendarTitleOverrides(for: start)
        func displayTitle(_ ev: EKEvent) -> String {
            (ev.eventIdentifier.flatMap { overrides[$0] }) ?? ev.title ?? "(no title)"
        }

        // Calendar half of the differences report — events HIDDEN or RENAMED on THIS
        // day. Both add to the top-right capsule count. Only today/future have a report
        // (past days are frozen snapshots). [today-diffs][calendar-diffs]
        if start >= Calendar.current.startOfDay(for: Date()) {
            let hiddenDiffs: [CalendarEventDifference] = events.compactMap { ev in
                guard let eid = ev.eventIdentifier, hidden.contains(eid) else { return nil }
                return CalendarEventDifference(id: "calendar|\(eid)", kind: .hidden, eventId: eid,
                                               title: ev.title ?? "(no title)",
                                               originalTitle: ev.title ?? "(no title)", date: start)
            }
            let renamedDiffs: [CalendarEventDifference] = visible.compactMap { ev in
                guard let eid = ev.eventIdentifier, let ov = overrides[eid],
                      ov != (ev.title ?? "") else { return nil }
                return CalendarEventDifference(id: "caltitle|\(eid)", kind: .renamed, eventId: eid,
                                               title: ov, originalTitle: ev.title ?? "(no title)", date: start)
            }
            calendarDiffs = hiddenDiffs + renamedDiffs
        } else {
            calendarDiffs = []
        }

        // All-day events get no timeline block or label — they have no real time
        // span on the schedule. They still flow into the Tasks list below.
        var eventMap: [String: EKEvent] = [:]
        calendarItems = visible.filter { !$0.isAllDay }.map { ev in
            let id = ev.eventIdentifier ?? UUID().uuidString
            eventMap[id] = ev
            return TimelineItem(id: id,
                                title: displayTitle(ev),
                                startMin: minutesOfDay(ev.startDate, dayStart: start),
                                endMin: minutesOfDay(ev.endDate, dayStart: start),
                                isCalendar: true)
        }
        calendarEvents = eventMap

        // Flow chosen-calendar events into the Tasks list (only events with a stable
        // identifier; sorted into the calendar group by start time). An empty
        // selection syncs an empty list, which clears any prior calendar tasks. The
        // event's own title/notes are the BASE — syncCalendarTasks layers any local
        // override on top. [calendar-override]
        let taskInputs: [CalendarTaskInput] = visible.compactMap { ev in
            guard let id = ev.eventIdentifier else { return nil }
            return CalendarTaskInput(eventId: id,
                                     title: ev.title ?? "(no title)",
                                     notes: ev.notes ?? "",
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
                // instead of dropping the morning portion. Show ONE label, on the PM
                // half, reading the true wrapped range (21:30–05:30); the AM half draws
                // its colour but suppresses its label so we don't get two.
                return [
                    TimelineItem(id: "blk-\(b.id)-pm", title: b.title,
                                 startMin: start, endMin: 1440, isCalendar: false, color: color,
                                 labelEndMin: end),
                    TimelineItem(id: "blk-\(b.id)-am", title: b.title,
                                 startMin: 0, endMin: end, isCalendar: false, color: color,
                                 suppressLabel: true)
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
            BackChevronButton { if dismissAddIfOpen() { return }; vm.relockOnLeave(); dismiss() }
            Spacer()
            HStack(spacing: 26) {                                 // [#44] spread out
                navButton("arrow.left") { vm.goToPreviousDay() }
                    .disabled(!vm.canGoToPreviousDay)
                    .opacity(vm.canGoToPreviousDay ? 1 : 0.3)
                navButton("arrow.right") { vm.goToNextDay() }
                Button { if dismissAddIfOpen() { return }; vm.goToToday() } label: {
                    DSText("Today").dsTextStyle(.subheadline)
                        .frame(height: 44)   // full top-bar height, not just the text [owner]
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .a11yTapBorder(cornerRadius: 4)
                navButton("calendar", size: 18) { showDatePicker = true }   // [#7] 18pt glyph
            }
            .padding(.horizontal, topBarInnerPad)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, topBarOuterPad)
        .padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private func navButton(_ icon: String, size: CGFloat = 16, _ action: @escaping () -> Void) -> some View {
        Button(action: { if dismissAddIfOpen() { return }; action() }) {
            DSImageView(systemName: icon, size: .size(.custom(size)), tint: .color(.primary))   // [#199]
                .frame(width: 44, height: 44)   // square, matches "Today" height
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

    /// Total Today↔templates differences for the viewed day: deleted recurring + backlog
    /// (from the view model) plus this day's hidden calendar events. [today-diffs]
    private var differenceCount: Int {
        vm.taskDifferences.count + calendarDiffs.count
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
                now: now,
                onTapCalendar: { id in if let ev = calendarEvents[id] { tappedEvent = TimelineTappedEvent(event: ev) } }
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
                    // Kept a plain SwiftUI TextField (not AppTextField, which is
                    // UITextView-backed) so KeyboardScrollNudge measures the same
                    // field type and the keyboard gap stays uniform. Size routes
                    // through appScaledSize so it tracks the read rows' .body scale. [#115]
                    TextField("New task", text: $newTask)
                        .font(appFont(appScaledSize(17)))
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
            // A locked past day is a read-only snapshot: the checkbox shows completion
            // but doesn't toggle, and tapping the title doesn't open the editor. Unlock
            // (the padlock) to edit. Add / reorder / swipe are already lock-gated. [past-lock]
            Button {
                if dismissAddIfOpen() { return }
                if vm.isPastLocked { return }
                Task { await vm.toggleTask(task) }
            } label: {
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
        if vm.isPastLocked { return }   // locked past day is read-only — unlock to edit [past-lock]
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
        Task { await vm.addManualTask() }   // addManualTask refreshes the page itself [#114]
        newTask = ""
        addingTask = false
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
        .animation(.easeInOut(duration: 0.2), value: locked)   // smooth lock/unlock color
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 0.6, pressing: { p in
            pressing = p
            if p { Haptics.impact() }
        }, perform: {
            Haptics.success()
            onToggle()
        })
    }
}

// ── Date picker (jump to a date) ────────────────────────────────────────────────
private struct TodayDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Date
    let minDate: Date?
    let onSelect: (Date) -> Void

    init(date: Date, minDate: Date? = nil, onSelect: @escaping (Date) -> Void) {
        _selected = State(initialValue: date)
        self.minDate = minDate
        self.onSelect = onSelect
    }

    /// Upper bound for navigation/selection — the jump picker stops at year 2100. [owner]
    private static let maxDate = Calendar.current.date(from: DateComponents(year: 2100, month: 12, day: 31))

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 0) {
                // Push the whole calendar down ~50pt, then nudge all popup content up
                // 18pt (94 − 18 = 76); the gap below shrinks so Go tracks with it. [owner]
                Color.clear.frame(height: 76)
                // Shared DSKit month-grid picker (app font) — replaces the stock
                // graphical DatePicker (wrong font, navigable to year 4000). [owner]
                DSCalendarView(date: $selected, minDate: minDate, maxDate: Self.maxDate)
                    .padding(.horizontal, 20)
                Color.clear.frame(height: 10)
                Button {
                    onSelect(selected); dismiss()
                } label: {
                    DSText("Go").dsTextStyle(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .contentShape(Capsule())
                        .a11yTapBorder(Capsule())
                }.buttonStyle(.plain)
                Spacer()
            }
        }
        .presentationDetents([.medium])
    }
}
