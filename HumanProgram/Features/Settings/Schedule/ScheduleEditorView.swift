import SwiftUI
import SwiftData
import DSKit
import UIKit

// Schedule editor, built on the Reminder-editor pattern: SettingsScreen
// container, upper-right Save (disabled until valid), swipe-back, and a
// discard-changes guard that stays quiet when nothing was entered.
//
// Layout: Name · Repeat (Weekly | Custom range) · 7-day circles (always) ·
// From/To (custom range only) · Sleep from/to · block list (Sleep first,
// locked; non-sleep blocks: hold-anywhere to drag-reorder, tap name/time to
// rename, tap duration to edit, swipe left to delete) · add-block row.
//
// The Repeat picker and all wheel pickers (sleep times, durations) and the
// block-name editor open as a shared translucent popup (AnchoredPopup) that
// drops beneath the tapped value.
//
// Block durations are the source of truth; start/end times are computed by
// chaining from the sleep wake time. Persistence reuses ScheduleRepository,
// whose normalizeBlocks recomputes the same chain.

struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new schedule; non-nil = editing an existing one.
    let template: ScheduleTemplate?

    /// Set when the user taps Duplicate: this same editor turns INTO a new-schedule
    /// draft copied from the current one (sleep + blocks carry over; title/weekdays
    /// reset). Saving then creates a brand-new schedule and dismisses once back to
    /// the list — no nested editor, so there's no multi-level-pop bug. (SwiftUI
    /// won't let an ancestor pop a view while its descendant is still on top, which
    /// is why the old push-a-second-editor approach left you stranded on save.)
    @State private var forceNew = false

    @State private var name = ""
    @State private var repeatMode = "weekly"          // "weekly" | "custom"
    @State private var weekdays: Set<Int> = []
    @State private var fromDate = Calendar.current.startOfDay(for: Date())
    @State private var toDate = Calendar.current.startOfDay(for: Date())
    @State private var sleepStart = 21 * 60 + 30       // 21:30
    @State private var sleepEnd = 5 * 60 + 30          // 05:30
    @State private var sleepColorHex: String? = nil    // Sleep block colour [#20]
    @State private var blocks: [DraftBlock] = []       // non-sleep, in order
    @State private var colorPickerTarget: ColorPickerTarget?   // custom colour picker [#14]

    // Inline add-block row
    @State private var newTitle = ""
    @State private var newDuration = 60

    @State private var activePicker: ActivePicker?     // drives the wheel/name/repeat popups
    @State private var anchorFrames: [String: CGRect] = [:]   // value frames for anchoring
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var conflictMessage: String?
    @State private var original = ScheduleSnapshot()
    @State private var didLoad = false

    // Hold-to-reorder + swipe-to-delete: the shared gesture engine (see
    // EditableRowList). All the state, geometry, thresholds and animations live in
    // the coordinator so this screen behaves identically to the Exercise and Today
    // lists. Wired to the block array in `body`.
    @State private var rows = RowGestureCoordinator<UUID>(rowHeight: 60)

    // Inline title editing
    @State private var editingTitleId: UUID?
    @FocusState private var titleFieldFocused: Bool

    // Custom numeric keypad (replaces Apple's numpad for the wheels)
    @State private var keypadVisible = false
    @State private var typedDigits = ""
    @State private var keypadMeasuredHeight: CGFloat = 0
    // Extra scroll room at the bottom while the (system) keyboard is up, so
    // SwiftUI's native avoidance can lift bottom fields above it consistently.
    @State private var keyboardSpacer: CGFloat = 0

    private var rowHeight: CGFloat { rows.rowHeight }
    /// One coordinate space shared by the anchor tags and the popups so they
    /// line up exactly (the screen-level `.global` space was unreliable here).
    private let anchorSpace = "scheduleAnchorSpace"

    /// What the shared anchored popup is currently editing. (Block titles are
    /// edited inline, not via a popup.)
    private enum ActivePicker: Equatable {
        case repeatMode, sleepFrom, sleepTo, newDuration
        case blockDuration(UUID)
    }

    private let repeatOptions: [(value: String, title: String)] =
        [("weekly", "Weekly"), ("custom", "Custom range")]
    private var repeatTitle: String {
        repeatOptions.first { $0.value == repeatMode }?.title ?? ""
    }
    /// Time popups widen in 12-hour mode to fit the extra AM/PM wheel column.
    /// (Duration popups don't have an AM/PM column, so they stay 210.)
    private var timePopupWidth: CGFloat { TimeFormatSetting.is24Hour ? 210 : 250 }

    /// Anchor-frame id for the active picker (matches the `.anchorFrame(...)` tag).
    private func anchorId(for picker: ActivePicker) -> String {
        switch picker {
        case .repeatMode:           return "repeat"
        case .sleepFrom:            return "sleepFrom"
        case .sleepTo:              return "sleepTo"
        case .newDuration:          return "newDuration"
        case .blockDuration(let id): return "dur-\(id)"
        }
    }

    // MARK: - Derived values

    private var sleepDuration: Int {
        sleepEnd > sleepStart ? sleepEnd - sleepStart : (1440 - sleepStart) + sleepEnd
    }
    private var usedMinutes: Int { sleepDuration + blocks.reduce(0) { $0 + $1.duration } }
    private var remaining: Int { max(0, 1440 - usedMinutes) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty
    }
    private var canAddBlock: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && newDuration > 0 && newDuration <= remaining
    }

    /// Start/end minute for each non-sleep block, chained from the wake time.
    private var blockTimes: [(start: Int, end: Int)] {
        var cursor = sleepEnd
        return blocks.map { b in
            let start = cursor
            let end = (cursor + b.duration) % 1440
            cursor = end
            return (start, end)
        }
    }

    private var currentSnapshot: ScheduleSnapshot {
        ScheduleSnapshot(name: name, repeatMode: repeatMode, weekdays: weekdays,
                         fromDate: fromDate, toDate: toDate,
                         sleepStart: sleepStart, sleepEnd: sleepEnd, blocks: blocks)
    }
    private var hasUnsavedChanges: Bool {
        // A duplicated-in-place draft counts as new (compare against "empty", not
        // the original template it was copied from).
        (template == nil || forceNew) ? (canSave || !blocks.isEmpty) : (currentSnapshot != original)
    }
    private func attemptBack() {
        if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() }
    }

    // MARK: - Body

    var body: some View {
        // Keep the shared gesture engine pointed at the CURRENT block array + edit
        // state (reassigned each render; closures are @ObservationIgnored so this
        // doesn't loop). One place owns the reorder/swipe/tap behaviour.
        rows.orderedIds = { blocks.map(\.id) }
        rows.moveRow = { from, to in
            let moved = blocks.remove(at: from); blocks.insert(moved, at: to)
        }
        rows.deleteRow = { id in
            withAnimation(.snappy(duration: 0.2)) { blocks.removeAll { $0.id == id } }
        }
        rows.beginEditGesture = { editingTitleId = nil; titleFieldFocused = false }

        return SettingsScreen(centered: true, onBack: attemptBack,
                       swipeBackBlocked: { hasUnsavedChanges },
                       scrollDisabled: rows.isInteracting,
                       manualKeyboardAvoidance: true,
                       trailing: { editorButtons }) {
            AppTextField(text: $name, placeholder: "Schedule name", fontSize: appScaledSize(20))

            if let conflictMessage {
                Text(conflictMessage)
                    .font(appFont(15)).foregroundStyle(.red)
            }

            repeatRow

            WeekdayCircleSelector(selected: $weekdays)

            if repeatMode == "custom" {
                DateFieldRow(label: "From", date: $fromDate)
                DateFieldRow(label: "To", date: $toDate, notBefore: fromDate)
            }

            // Sleep — section label with the Sleep colour circle on the right. [#20]
            HStack {
                SettingsSectionLabel(title: "Sleep")
                Spacer()
                colorCircle(hex: sleepColorHex, title: "Sleep") {
                    if !dismissOpenInputIfAny() { colorPickerTarget = .sleep }
                }
            }
            valueRow(label: "Sleep from", value: hhmm(sleepStart), anchorId: "sleepFrom") {
                if !dismissOpenInputIfAny() { activePicker = .sleepFrom }
            }
            valueRow(label: "Sleep to", value: hhmm(sleepEnd), anchorId: "sleepTo") {
                if !dismissOpenInputIfAny() { activePicker = .sleepTo }
            }

            // Blocks — running total of all durations, directly under the header.
            VStack(alignment: .leading, spacing: 4) {
                SettingsSectionLabel(title: "Blocks")
                Text(totalString).font(appFont(14)).foregroundStyle(.secondary)
            }
            blockList
            addBlockRow
            // Room for SwiftUI's keyboard avoidance to lift bottom fields.
            Color.clear.frame(height: keyboardSpacer)
        }
        .onPreferenceChange(AnchorFrameKey.self) { anchorFrames = $0 }
        .overlay {
            if showDeleteConfirm {
                ConfirmPopup(message: "Delete schedule?", confirmTitle: "Delete",
                             onConfirm: { deleteSchedule() }, onCancel: { showDeleteConfirm = false })
            }
            anchoredPopup
            if keypadVisible {
                KeypadOverlay(onDigit: keypadDigit, onBackspace: keypadBackspace, onDone: keypadDone,
                              onHeight: { keypadMeasuredHeight = $0 })
                    .zIndex(2)
            }
            colorPickerOverlay.zIndex(3)   // [#14]
        }
        .discardChangesGuard(isPresented: $showDiscardConfirm) { dismiss() }   // [#197]
        .coordinateSpace(.named(anchorSpace))
        // Any interaction elsewhere (a popup, editing a title, toggling days,
        // changing repeat, the name field, adding a block) auto-closes an open
        // swipe — but scrolling, which changes none of these, leaves it open.
        .onChange(of: activePicker) { _, v in
            rows.closeSwipeIfOpen()
            if v == nil, keypadVisible {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { keypadVisible = false }
            }
        }
        .onChange(of: editingTitleId) { _, v in if v != nil { rows.closeSwipeIfOpen() } }
        .onChange(of: weekdays) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: repeatMode) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: sleepStart) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: sleepEnd) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: name) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: newTitle) { _, _ in rows.closeSwipeIfOpen() }
        .onChange(of: newDuration) { _, _ in rows.closeSwipeIfOpen() }
        .onAppear(perform: loadIfNeeded)
    }

    // Repeat picker — tappable value that opens a floating anchored popup.
    private var repeatRow: some View {
        HStack {
            DSText("Repeat").dsTextStyle(.title3)
            Spacer(minLength: 8)
            Button { if !dismissOpenInputIfAny() { activePicker = .repeatMode } } label: {
                HStack(spacing: 4) {
                    Text(repeatTitle).font(appFont(18)).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .a11yTapBorder(cornerRadius: 4)
            .anchorFrame("repeat", in: .named(anchorSpace))
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var editorButtons: some View {
        // Duplicate + Delete only on an existing, not-yet-duplicated schedule.
        if template != nil && !forceNew {
            // Duplicate: turn THIS editor into a fresh copy (in place).
            Button { startDuplicateInPlace() } label: {
                Image(systemName: "plus.square.on.square").font(.system(size: 18))
                    .foregroundStyle(.primary).frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }
            EditorDeleteButton { showDeleteConfirm = true }
        }
        EditorSaveButton(enabled: canSave) { save() }
    }

    // MARK: - Shared anchored popup (repeat, sleep times, durations, block name)

    @ViewBuilder
    private var anchoredPopup: some View {
        if let picker = activePicker, let rect = anchorFrames[anchorId(for: picker)] {
            // Tapping outside eases the keypad + popup away together.
            let close = { dismissKeypadAndPopup() }
            let space = CoordinateSpace.named(anchorSpace)
            let inset: CGFloat = keypadVisible ? (keypadMeasuredHeight > 0 ? keypadMeasuredHeight : 320) : 0
            switch picker {
            case .repeatMode:
                AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 112,
                              alignment: .trailing, space: space, onClose: close) {
                    repeatOptionList
                }
            case .sleepFrom:
                AnchoredPopup(anchor: rect, width: timePopupWidth, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $sleepStart, mode: .time, onRequestKeypad: showKeypad)
                }
            case .sleepTo:
                AnchoredPopup(anchor: rect, width: timePopupWidth, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $sleepEnd, mode: .time, onRequestKeypad: showKeypad)
                }
            case .newDuration:
                AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $newDuration, mode: .duration, onRequestKeypad: showKeypad)
                }
            case .blockDuration(let id):
                AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: durationBinding(for: id), mode: .duration, onRequestKeypad: showKeypad)
                }
            }
        }
    }

    private var repeatOptionList: some View {
        VStack(spacing: 0) {
            ForEach(repeatOptions, id: \.value) { option in
                Button {
                    repeatMode = option.value
                    activePicker = nil
                } label: {
                    HStack(spacing: 12) {
                        Text(option.title).font(appFont(18)).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if option.value == repeatMode {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func durationBinding(for id: UUID) -> Binding<Int> {
        arrayFieldBinding($blocks, id: id, fallback: 0,
                          get: { $0.duration }, set: { $0.duration = $1 })
    }
    private func nameBinding(for id: UUID) -> Binding<String> {
        arrayFieldBinding($blocks, id: id, fallback: "",
                          get: { $0.title }, set: { $0.title = $1 })
    }

    /// Which colour the custom picker is editing. [#14]
    enum ColorPickerTarget: Equatable { case block(UUID); case sleep }

    /// Hex binding for a block's colour (nil → default-by-name resolved on read). [#14]
    private func colorHexBinding(for id: UUID) -> Binding<String?> {
        arrayFieldBinding($blocks, id: id, fallback: nil,
                          get: { $0.colorHex }, set: { $0.colorHex = $1 })
    }
    private var sleepColorHexBinding: Binding<String?> {
        Binding(get: { sleepColorHex }, set: { sleepColorHex = $0 })
    }

    @ViewBuilder
    private var colorPickerOverlay: some View {
        if let target = colorPickerTarget {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .onTapGesture { colorPickerTarget = nil }
                switch target {
                case .block(let id):
                    BlockColorPickerView(colorHex: colorHexBinding(for: id),
                                         title: blocks.first(where: { $0.id == id })?.title ?? "Block") {
                        colorPickerTarget = nil
                    }
                case .sleep:
                    BlockColorPickerView(colorHex: sleepColorHexBinding, title: "Sleep") {
                        colorPickerTarget = nil
                    }
                }
            }
        }
    }

    /// A tappable colour circle that opens the custom picker. [#14]
    private func colorCircle(hex: String?, title: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            Circle().fill(BlockColors.color(hex: hex, title: title))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                .contentShape(Circle())
        }.buttonStyle(.plain)
        .a11yTapBorder(Circle())
    }

    // MARK: - Custom keypad

    /// The minutes binding the keypad currently types into (matches activePicker).
    private var activeMinutesBinding: Binding<Int>? {
        switch activePicker {
        case .sleepFrom:             return $sleepStart
        case .sleepTo:               return $sleepEnd
        case .newDuration:           return $newDuration
        case .blockDuration(let id): return durationBinding(for: id)
        default:                     return nil
        }
    }

    private func showKeypad() {
        typedDigits = ""
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { keypadVisible = true }
    }

    private func keypadDigit(_ d: String) { TimeKeypadEntry.digit(d, typed: &typedDigits, into: activeMinutesBinding) }
    private func keypadBackspace() { TimeKeypadEntry.backspace(typed: &typedDigits, into: activeMinutesBinding) }
    private func keypadDone() { dismissKeypadAndPopup() }

    /// Eases the keypad down and the popup out together (smooth, not abrupt).
    private func dismissKeypadAndPopup() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            keypadVisible = false
            activePicker = nil
        }
    }

    /// If a keypad/popup/keyboard is open, dismiss it and return true — so a tap
    /// on a value while something is open just CLOSES it instead of opening a new
    /// popup (the tap is "consumed" by the dismissal).
    private func dismissOpenInputIfAny() -> Bool {
        if keypadVisible || activePicker != nil {
            dismissKeypadAndPopup()
            return true
        }
        if editingTitleId != nil {
            editingTitleId = nil
            titleFieldFocused = false
            return true
        }
        return false
    }

    // MARK: - Block list (Sleep first/locked, then draggable non-sleep blocks)

    private var blockList: some View {
        VStack(spacing: 0) {
            sleepRow
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                EditableRow(coordinator: rows, id: block.id, index: index) {
                    blockRowContent(block: block, index: index)
                }
            }
        }
        // ONE shared install of the reorder + swipe recognizers (see EditableRowList).
        .rowGestures(rows)
        // Leaving the title field (tapped elsewhere / keyboard dismissed) ends edit.
        .onChange(of: titleFieldFocused) { _, focused in
            if !focused { editingTitleId = nil }
        }
        // SwiftUI avoidance is off; the bottom spacer gives scroll room and this
        // scrolls the focused field to a uniform 20pt above the keyboard.
        .background(KeyboardScrollNudge())
        // When editing a title near the bottom, nudge the scroll so the row sits
        // a comfortable gap above the keyboard (proper breathing room).
        // Track the system keyboard so we can add bottom room for SwiftUI's
        // native avoidance (only fires for text fields — the wheel uses the
        // custom keypad, which isn't a system keyboard).
        .keyboardSpacer($keyboardSpacer)
    }

    /// Sleep — fixed first, not draggable / deletable / renamable. Its duration
    /// is driven by Sleep from/to.
    private var sleepRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                DSText("Sleep").dsTextStyle(.body).lineLimit(1)
                Text("\(hhmm(sleepStart))–\(hhmm(sleepEnd))")
                    .font(appFont(14)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationPadded(sleepDuration))
                .font(appFont(15)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    private func blockRowContent(block: DraftBlock, index: Int) -> some View {
        let times = blockTimes.indices.contains(index) ? blockTimes[index] : (start: 0, end: 0)
        let isEditing = editingTitleId == block.id
        // `.onTapGesture` (not Button) so edit fires ONLY on a clean tap — never
        // after a hold, a drag-reorder, or a swipe (those involve movement/time
        // and so don't count as a tap).
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Title", text: nameBinding(for: block.id))
                        // Match the read style (.body is font-scaled) so the title
                        // doesn't change size when entering edit mode. [#21]
                        .font(appFont(appScaledSize(17)))
                        .focused($titleFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { editingTitleId = nil }
                } else {
                    DSText(block.title.isEmpty ? "Untitled" : block.title)
                        .dsTextStyle(.body).lineLimit(1)
                }
                Text("\(hhmm(times.start))–\(hhmm(times.end))")
                    .font(appFont(14)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { tapTitle(block) }

            // Colour circle (opens the custom DSKit picker) just left of the duration. [#14]
            colorCircle(hex: block.colorHex, title: block.title) {
                if !dismissOpenInputIfAny() { colorPickerTarget = .block(block.id) }
            }

            Text(durationPadded(block.duration))
                .font(appFont(15)).foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture { tapDuration(block) }
                .anchorFrame("dur-\(block.id)", in: .named(anchorSpace))
        }
        .padding(.vertical, 8)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    /// Clean tap on the title/time → edit the title inline. `consumeTap()` absorbs
    /// the tap if a swipe engaged or an open row needs closing first.
    private func tapTitle(_ block: DraftBlock) {
        guard rows.consumeTap() else { return }
        // If editing a DIFFERENT title, or a keypad/popup is open, just dismiss.
        if editingTitleId != block.id, dismissOpenInputIfAny() { return }
        editingTitleId = block.id
        // Focus after the field is in the hierarchy so the keyboard reliably opens.
        DispatchQueue.main.async { titleFieldFocused = true }
    }

    /// Clean tap on the duration → open the wheel popup.
    private func tapDuration(_ block: DraftBlock) {
        guard rows.consumeTap() else { return }
        if dismissOpenInputIfAny() { return }
        activePicker = .blockDuration(block.id)
    }

    // MARK: - Add-block row

    private var addBlockRow: some View {
        let isFull = remaining == 0
        return VStack(spacing: 10) {
            // Title, Duration label + value all at the block-title size (.body / 17).
            if isFull {
                Text("Your blocks are full!")
                    .font(appFont(17)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            } else {
                // Plain SwiftUI TextField (same type as the inline existing-block
                // title) so SwiftUI's keyboard-avoidance gap is identical for both.
                // Its placeholder also shows while empty/focused natively.
                TextField("Block title", text: $newTitle)
                    .font(appFont(appScaledSize(17)))
                    .frame(minHeight: 34)
            }
            HStack(spacing: 0) {
                DSText("Duration").dsTextStyle(.body)
                Button { if !dismissOpenInputIfAny() { activePicker = .newDuration } } label: {
                    DSText(durationPadded(newDuration))
                        .dsTextStyle(.body, isFull ? Color.secondary : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(cornerRadius: 4)
                .disabled(isFull)
                .padding(.leading, 12)
                .anchorFrame("newDuration", in: .named(anchorSpace))
                Spacer()
                // Plain "+" (no circle), matching the top-bar + style.
                Button { addBlock() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(canAddBlock ? Color.primary : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .a11yTapBorder(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAddBlock)
            }
            .frame(height: 44)
        }
    }

    private func addBlock() {
        guard canAddBlock else { return }
        blocks.append(DraftBlock(title: newTitle.trimmingCharacters(in: .whitespaces), duration: newDuration))
        newTitle = ""
        newDuration = 60
    }

    // MARK: - Reusable value row (label + tappable value that opens a popup)

    private func valueRow(label: String, value: String, anchorId: String,
                          action: @escaping () -> Void) -> some View {
        PlanningValueRow(label: label, value: value, anchorId: anchorId,
                         anchorSpace: anchorSpace, action: action)   // [#43] shared row
    }

    // MARK: - Load / Save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        defer { original = currentSnapshot }
        guard let t = template else { return }   // brand-new schedule: blank form
        name = t.name
        if t.customDateStart != nil || t.customDateEnd != nil {
            repeatMode = "custom"
            fromDate = t.customDateStart ?? Calendar.current.startOfDay(for: Date())
            toDate = t.customDateEnd ?? fromDate
            weekdays = Set(t.assignedWeekdays)
        } else {
            repeatMode = "weekly"
            weekdays = Set(t.assignedWeekdays)
        }
        let sorted = t.blocks.sorted { $0.sortOrder < $1.sortOrder }
        if let sleep = sorted.first(where: { $0.title == "Sleep" }) {
            sleepStart = sleep.startMinuteOfDay
            sleepEnd = sleep.endMinuteOfDay
            sleepColorHex = sleep.colorHex
        }
        blocks = sorted.filter { $0.title != "Sleep" }
            .map { DraftBlock(title: $0.title, duration: $0.durationMinutes, colorHex: $0.colorHex) }
    }

    private func buildBlocks() -> [ScheduleBlock] {
        var result: [ScheduleBlock] = [
            ScheduleBlock(title: "Sleep", startMinuteOfDay: sleepStart, endMinuteOfDay: sleepEnd,
                          sortOrder: 0, colorHex: sleepColorHex)
        ]
        for (i, b) in blocks.enumerated() {
            // Times are placeholders; ScheduleRepository.normalizeBlocks recomputes
            // them from each block's duration when saving.
            result.append(ScheduleBlock(title: b.title, startMinuteOfDay: 0,
                                        endMinuteOfDay: b.duration % 1440, sortOrder: i + 1,
                                        colorHex: b.colorHex))
        }
        return result
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !weekdays.isEmpty else { return }

        // A schedule can't be longer than a day. Sleep + all block durations must
        // fit in 24h. Show the error in the same slot as the day-conflict message.
        if usedMinutes > 1440 {
            conflictMessage = "Schedule exceeds 24 hours"
            return
        }

        let repo = ScheduleRepository(context: context)
        // A duplicated-in-place draft creates a NEW template (never touches the
        // original it was copied from).
        let isNew = template == nil || forceNew
        let t = isNew ? ScheduleTemplate(name: trimmed) : template!
        if isNew { repo.insert(t) }

        t.name = trimmed
        if repeatMode == "custom" {
            t.assignedWeekdays = weekdays.sorted()
            t.customDateStart = Calendar.current.startOfDay(for: fromDate)
            t.customDateEnd = Calendar.current.startOfDay(for: toDate)
        } else {
            t.assignedWeekdays = weekdays.sorted()
            t.customDateStart = nil
            t.customDateEnd = nil
        }
        t.blocks = buildBlocks()

        do {
            if let conflict = try repo.save(t) {
                conflictMessage = conflict.reason
                if isNew { try? repo.delete(t) }
                return
            }
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[ScheduleEditor] save error: \(error)")
        }
        dismiss()
    }

    /// Turn this editor into a new-schedule draft copied from the current one:
    /// sleep + blocks stay, title/weekdays/repeat reset so it can't save as-is and
    /// the original is untouched. Saving creates a new schedule → back to the list.
    private func startDuplicateInPlace() {
        forceNew = true
        name = ""
        weekdays = []
        repeatMode = "weekly"
        fromDate = Calendar.current.startOfDay(for: Date())
        toDate = fromDate
        conflictMessage = nil
        rows.swipeOpenId = nil
    }

    private func deleteSchedule() {
        showDeleteConfirm = false
        guard let template else { return }
        do {
            try ScheduleRepository(context: context).delete(template)
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[ScheduleEditor] delete error: \(error)")
        }
        dismiss()
    }

    // MARK: - Formatting

    /// Clock time honoring the app's 12h/24h setting (shared helper). Used for the
    /// sleep/block start–end ranges. Durations use `durationPadded`, the running
    /// total uses `totalString` — both stay fixed-format, independent of this.
    private func hhmm(_ minutes: Int) -> String {
        clockString(minutesOfDay: minutes)
    }
    /// Zero-padded "##h ##m" duration label.
    private func durationPadded(_ minutes: Int) -> String {
        String(format: "%02dh %02dm", minutes / 60, minutes % 60)
    }
    /// Running total of all block durations (incl. Sleep), 24-hour HH:MM,
    /// independent of the app's time-format setting.
    private var totalString: String {
        String(format: "%02d:%02d", usedMinutes / 60, usedMinutes % 60)
    }
}

/// A non-sleep block while editing: title + duration (times are derived).
struct DraftBlock: Identifiable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var duration: Int   // minutes
    var colorHex: String? = nil   // assigned block colour [#20]
}

/// Snapshot of the editable fields, to detect unsaved changes.
private struct ScheduleSnapshot: Equatable {
    var name = ""
    var repeatMode = "weekly"
    var weekdays: Set<Int> = []
    var fromDate = Calendar.current.startOfDay(for: Date())
    var toDate = Calendar.current.startOfDay(for: Date())
    var sleepStart = 21 * 60 + 30
    var sleepEnd = 5 * 60 + 30
    var blocks: [DraftBlock] = []
}
