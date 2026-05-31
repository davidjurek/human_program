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

    @State private var name = ""
    @State private var repeatMode = "weekly"          // "weekly" | "custom"
    @State private var weekdays: Set<Int> = []
    @State private var fromDate = Calendar.current.startOfDay(for: Date())
    @State private var toDate = Calendar.current.startOfDay(for: Date())
    @State private var sleepStart = 21 * 60 + 30       // 21:30
    @State private var sleepEnd = 5 * 60 + 30          // 05:30
    @State private var blocks: [DraftBlock] = []       // non-sleep, in order

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

    // Drag-to-reorder (vertical). Driven by a UIKit long-press recognizer (real
    // 0.4s hold + small allowable movement) so it can't be triggered by a tap, a
    // scroll, or a swipe — only a deliberate stationary hold. The recognizer
    // reliably reports began/changed/ended/cancelled, so the pop never sticks and
    // scrolling/tapping stay free. The array is moved once on release.
    @State private var dragInfo: BlockDragInfo?
    @State private var reorderRowFrames: [UUID: CGRect] = [:]   // window coords, for hit-testing

    // Swipe-to-delete (horizontal)
    @State private var swipeOpenId: UUID?              // row showing the trash
    @State private var swipeDragId: UUID?              // row being dragged now
    @State private var swipeDragX: CGFloat = 0

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

    private let rowHeight: CGFloat = 60
    private let trashWidth: CGFloat = 72
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
        template == nil ? (canSave || !blocks.isEmpty) : (currentSnapshot != original)
    }
    private func attemptBack() {
        if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() }
    }

    // MARK: - Body

    var body: some View {
        SettingsScreen(centered: true, onBack: attemptBack,
                       swipeBackBlocked: { hasUnsavedChanges },
                       scrollDisabled: dragInfo != nil || swipeDragId != nil,
                       manualKeyboardAvoidance: true,
                       trailing: { editorButtons }) {
            AppTextField(text: $name, placeholder: "Schedule name", fontSize: 20)

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

            // Sleep
            SettingsSectionLabel(title: "Sleep")
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
            if showDiscardConfirm {
                ConfirmPopup(message: "Discard Changes?", confirmTitle: "Discard",
                             onConfirm: { dismiss() }, onCancel: { showDiscardConfirm = false })
            }
            anchoredPopup
            if keypadVisible {
                VStack(spacing: 0) {
                    Spacer()
                    GlassKeypad(onDigit: keypadDigit, onBackspace: keypadBackspace, onDone: keypadDone)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: KeypadHeightKey.self, value: g.size.height)
                        })
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .coordinateSpace(.named(anchorSpace))
        // Any interaction elsewhere (a popup, editing a title, toggling days,
        // changing repeat, the name field, adding a block) auto-closes an open
        // swipe — but scrolling, which changes none of these, leaves it open.
        .onChange(of: activePicker) { _, v in
            closeSwipeIfOpen()
            if v == nil, keypadVisible {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { keypadVisible = false }
            }
        }
        .onChange(of: editingTitleId) { _, v in if v != nil { closeSwipeIfOpen() } }
        .onChange(of: weekdays) { _, _ in closeSwipeIfOpen() }
        .onChange(of: repeatMode) { _, _ in closeSwipeIfOpen() }
        .onChange(of: sleepStart) { _, _ in closeSwipeIfOpen() }
        .onChange(of: sleepEnd) { _, _ in closeSwipeIfOpen() }
        .onChange(of: name) { _, _ in closeSwipeIfOpen() }
        .onChange(of: newTitle) { _, _ in closeSwipeIfOpen() }
        .onChange(of: newDuration) { _, _ in closeSwipeIfOpen() }
        .onPreferenceChange(KeypadHeightKey.self) { keypadMeasuredHeight = $0 }
        .onAppear(perform: loadIfNeeded)
    }

    private func closeSwipeIfOpen() {
        guard swipeOpenId != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
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
            .anchorFrame("repeat", in: .named(anchorSpace))
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var editorButtons: some View {
        if template != nil {
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash").font(.system(size: 18))
                    .foregroundStyle(.red).frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        Button { save() } label: {
            Text("Save").font(appFont(18))
                .foregroundStyle(canSave ? .primary : .secondary)
                .frame(height: 44).padding(.horizontal, 6)
        }
        .disabled(!canSave)
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
                AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $sleepStart, mode: .time, onRequestKeypad: showKeypad)
                }
            case .sleepTo:
                AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 185,
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
        Binding(
            get: { blocks.first(where: { $0.id == id })?.duration ?? 0 },
            set: { v in if let i = blocks.firstIndex(where: { $0.id == id }) { blocks[i].duration = v } }
        )
    }
    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { blocks.first(where: { $0.id == id })?.title ?? "" },
            set: { v in if let i = blocks.firstIndex(where: { $0.id == id }) { blocks[i].title = v } }
        )
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

    private func keypadDigit(_ d: String) {
        typedDigits = String((typedDigits + d).filter(\.isNumber).suffix(4))
        applyTypedToActive()
    }
    private func keypadBackspace() {
        typedDigits = String(typedDigits.dropLast())
        applyTypedToActive()
    }
    /// HHMM entry, minutes snapped to the nearest 5 (same rule as the wheel).
    private func applyTypedToActive() {
        guard let binding = activeMinutesBinding, !typedDigits.isEmpty else { return }
        let s = typedDigits
        let hh = min(23, Int(String(s.prefix(2))) ?? 0)
        var mm = s.count >= 3 ? (Int(String(s.dropFirst(2))) ?? 0) : 0
        mm = min(55, Int((Double(mm) / 5).rounded()) * 5)
        binding.wrappedValue = hh * 60 + mm
    }
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
                blockRow(block: block, index: index)
                    // Report each row's window frame so the reorder recognizer
                    // can tell which row a long-press landed on.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: RowFrameKey.self,
                                                   value: [block.id: proxy.frame(in: .global)])
                        }
                    )
            }
        }
        .onPreferenceChange(RowFrameKey.self) { reorderRowFrames = $0 }
        // UIKit long-press drives reorder (reliable delay; never fires on tap/
        // scroll/swipe). Installed on the enclosing scroll view.
        .background(
            ReorderRecognizer(
                rowFrames: reorderRowFrames,
                onBegan: beginReorder,
                onChanged: { dy in dragInfo?.dy = dy },
                onEnded: endReorder,
                onCancelled: { dragInfo = nil }
            )
        )
        // UIKit pan drives swipe-to-delete. It only begins for horizontal drags,
        // so vertical drags fall through to native scrolling.
        .background(
            SwipePanRecognizer(
                rowFrames: reorderRowFrames,
                canStart: { dragInfo == nil },
                onBegan: swipeBegan,
                onChanged: swipeChanged,
                onEnded: swipeEnded
            )
        )
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let f = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) { keyboardSpacer = f.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardSpacer = 0 }
        }
    }

    private func swipeBegan(_ id: UUID) {
        if swipeOpenId != id, swipeOpenId != nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
        }
        editingTitleId = nil
        titleFieldFocused = false
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
        // No swipe-to-delete: just snap open or closed. Delete is via the trash.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            swipeOpenId = (total < -trashWidth / 2) ? id : nil
            swipeDragId = nil
            swipeDragX = 0
        }
    }

    private func beginReorder(_ id: UUID) {
        // Close any open swipe and end title editing; pop + haptic.
        swipeOpenId = nil
        editingTitleId = nil
        titleFieldFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy(duration: 0.18)) { dragInfo = BlockDragInfo(id: id, dy: 0) }
    }

    private func endReorder(_ dy: CGFloat) {
        guard let info = dragInfo, let base = blocks.firstIndex(where: { $0.id == info.id }) else {
            dragInfo = nil; return
        }
        let proj = projectedIndex(from: base, dy: dy)
        withAnimation(.snappy(duration: 0.22)) {
            if proj != base {
                let moved = blocks.remove(at: base)
                blocks.insert(moved, at: proj)
            }
            dragInfo = nil
        }
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

    private func blockRow(block: DraftBlock, index: Int) -> some View {
        let isDragging = dragInfo?.id == block.id
        let shiftY = shiftOffset(forIndex: index)

        return GeometryReader { geo in
            // Content + trash lane move together and the row is clipped, so the
            // red circle slides IN from the right edge as you swipe (it never
            // flashes in over the content).
            HStack(spacing: 0) {
                blockRowContent(block: block, index: index)
                    .frame(width: geo.size.width, height: rowHeight)
                Button { deleteBlock(id: block.id) } label: {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 40, height: 40)
                        Image(systemName: "trash")
                            .font(.system(size: 17)).foregroundStyle(.white)
                    }
                    .frame(width: trashWidth, height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .offset(x: swipeOffset(for: block.id))
            .frame(width: geo.size.width, height: rowHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight)
        .offset(y: isDragging ? (dragInfo?.dy ?? 0) : shiftY)
        .animation(.snappy(duration: 0.2), value: isDragging)
        .animation(isDragging ? nil : .snappy(duration: 0.2), value: shiftY)
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 8, y: 4)
        .zIndex(isDragging ? 1 : 0)
        // Reorder (long-press) and swipe-to-delete (horizontal pan) are both UIKit
        // recognizers installed in blockList, so vertical drags scroll natively.
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
                        .font(appFont(17))
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

    /// Clean tap on the title/time → edit the title inline (or close an open swipe).
    private func tapTitle(_ block: DraftBlock) {
        if swipeOpenId != nil { closeSwipe(); return }
        // If editing a DIFFERENT title, or a keypad/popup is open, just dismiss.
        if editingTitleId != block.id, dismissOpenInputIfAny() { return }
        editingTitleId = block.id
        // Focus after the field is in the hierarchy so the keyboard reliably opens.
        DispatchQueue.main.async { titleFieldFocused = true }
    }

    /// Clean tap on the duration → open the wheel popup (or close an open swipe).
    private func tapDuration(_ block: DraftBlock) {
        if swipeOpenId != nil { closeSwipe(); return }
        if dismissOpenInputIfAny() { return }
        activePicker = .blockDuration(block.id)
    }

    // MARK: - Reorder / swipe geometry

    private func projectedIndex(from base: Int, dy: CGFloat) -> Int {
        let shift = Int((dy / rowHeight).rounded())
        return max(0, min(blocks.count - 1, base + shift))
    }

    /// Offset that makes room for the dragged row by shifting the rows it has
    /// passed over (the array isn't mutated until the drag ends).
    private func shiftOffset(forIndex i: Int) -> CGFloat {
        guard let info = dragInfo,
              let base = blocks.firstIndex(where: { $0.id == info.id }),
              base != i else { return 0 }
        let proj = projectedIndex(from: base, dy: info.dy)
        if base < proj, (base + 1 ... proj).contains(i) { return -rowHeight }
        if proj < base, (proj ..< base).contains(i) { return rowHeight }
        return 0
    }

    /// Live horizontal offset. Clamps at the open position (no full-swipe), with
    /// a little rubber-band past it.
    private func swipeOffset(for id: UUID) -> CGFloat {
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let raw = base + ((swipeDragId == id) ? swipeDragX : 0)
        if raw < -trashWidth {
            // Rubber-band resistance past the open position.
            return -trashWidth - (-trashWidth - raw) * 0.2
        }
        return min(0, raw)
    }

    private func closeSwipe() {
        withAnimation(.snappy(duration: 0.2)) { swipeOpenId = nil }
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
                    .font(appFont(17))
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

    private func deleteBlock(id: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            blocks.removeAll { $0.id == id }
            swipeOpenId = nil
        }
    }

    // MARK: - Reusable value row (label + tappable value that opens a popup)

    private func valueRow(label: String, value: String, anchorId: String,
                          action: @escaping () -> Void) -> some View {
        HStack {
            DSText(label).dsTextStyle(.title3)
            Spacer(minLength: 8)
            Button(action: action) {
                Text(value).font(appFont(18)).foregroundStyle(.primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .anchorFrame(anchorId, in: .named(anchorSpace))
        }
        .frame(height: 34)
    }

    // MARK: - Load / Save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        defer { original = currentSnapshot }
        guard let t = template else { return }
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
        }
        blocks = sorted.filter { $0.title != "Sleep" }
            .map { DraftBlock(title: $0.title, duration: $0.durationMinutes) }
    }

    private func buildBlocks() -> [ScheduleBlock] {
        var result: [ScheduleBlock] = [
            ScheduleBlock(title: "Sleep", startMinuteOfDay: sleepStart, endMinuteOfDay: sleepEnd, sortOrder: 0)
        ]
        for (i, b) in blocks.enumerated() {
            // Times are placeholders; ScheduleRepository.normalizeBlocks recomputes
            // them from each block's duration when saving.
            result.append(ScheduleBlock(title: b.title, startMinuteOfDay: 0,
                                        endMinuteOfDay: b.duration % 1440, sortOrder: i + 1))
        }
        return result
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !weekdays.isEmpty else { return }

        let repo = ScheduleRepository(context: context)
        let isNew = template == nil
        let t = template ?? ScheduleTemplate(name: trimmed)
        if isNew { context.insert(t) }

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
                if isNew { context.delete(t); try? context.save() }
                return
            }
            try PageRefreshService.refresh(context: context)
        } catch {
            print("[ScheduleEditor] save error: \(error)")
        }
        dismiss()
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

    private func hhmm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
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
struct DraftBlock: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var duration: Int   // minutes
}

/// Transient drag-reorder state. Driven by the UIKit reorder recognizer.
struct BlockDragInfo: Equatable {
    var id: UUID
    var dy: CGFloat
}

/// Reports each block row's window (global) frame so the reorder recognizer can
/// tell which row a long-press began on.
private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Reports the custom keypad's measured height so the wheel popup can sit a
/// small, consistent gap above it.
private struct KeypadHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// Drives block reordering with a real UIKit long-press recognizer installed on
/// the enclosing scroll view. A genuine 0.4s hold with a small allowable
/// movement means a tap, a scroll, or a swipe never arms it — only a deliberate
/// stationary hold. It coexists with scrolling and SwiftUI taps (simultaneous
/// recognition, doesn't cancel touches).
private struct ReorderRecognizer: UIViewRepresentable {
    var rowFrames: [UUID: CGRect]          // window coords
    var onBegan: (UUID) -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false  // just a hook to reach the scroll view
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.install(from: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ReorderRecognizer
        private weak var recognizer: UILongPressGestureRecognizer?
        private var activeId: UUID?
        private var startY: CGFloat = 0
        init(_ parent: ReorderRecognizer) { self.parent = parent }

        func install(from view: UIView) {
            guard recognizer == nil else { return }
            var v: UIView? = view
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let target = v else {
                DispatchQueue.main.async { [weak self, weak view] in
                    if let self, let view { self.install(from: view) }
                }
                return
            }
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            lp.minimumPressDuration = 0.4
            lp.allowableMovement = 10
            lp.delegate = self
            lp.cancelsTouchesInView = false
            target.addGestureRecognizer(lp)
            recognizer = lp
        }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: nil)   // window coordinates
            switch g.state {
            case .began:
                if let id = parent.rowFrames.first(where: { $0.value.contains(p) })?.key {
                    activeId = id
                    startY = p.y
                    parent.onBegan(id)
                }
            case .changed:
                if activeId != nil { parent.onChanged(p.y - startY) }
            case .ended:
                if activeId != nil { parent.onEnded(p.y - startY) }
                activeId = nil
            case .cancelled, .failed:
                if activeId != nil { parent.onCancelled() }
                activeId = nil
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Drives swipe-to-delete with a UIKit pan recognizer that only begins for
/// HORIZONTAL drags — so vertical drags fall straight through to native
/// scrolling. Hit-tests which block row the pan started on.
private struct SwipePanRecognizer: UIViewRepresentable {
    var rowFrames: [UUID: CGRect]
    var canStart: () -> Bool
    var onBegan: (UUID) -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.install(from: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SwipePanRecognizer
        private weak var pan: UIPanGestureRecognizer?
        private var activeId: UUID?
        init(_ parent: SwipePanRecognizer) { self.parent = parent }

        func install(from view: UIView) {
            guard pan == nil else { return }
            var v: UIView? = view
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let target = v else {
                DispatchQueue.main.async { [weak self, weak view] in
                    if let self, let view { self.install(from: view) }
                }
                return
            }
            let p = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            p.delegate = self
            p.cancelsTouchesInView = false
            target.addGestureRecognizer(p)
            pan = p
        }

        @objc func handle(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                let loc = g.location(in: nil)
                if let id = parent.rowFrames.first(where: { $0.value.contains(loc) })?.key {
                    activeId = id
                    parent.onBegan(id)
                }
            case .changed:
                if activeId != nil { parent.onChanged(g.translation(in: g.view).x) }
            case .ended:
                if activeId != nil { parent.onEnded(g.translation(in: g.view).x, g.velocity(in: g.view).x) }
                activeId = nil
            case .cancelled, .failed:
                if activeId != nil { parent.onEnded(g.translation(in: g.view).x, 0) }
                activeId = nil
            default:
                break
            }
        }

        // Begin only for horizontal drags over a block row (vertical → scroll).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard parent.canStart(), let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            guard abs(v.x) > abs(v.y) else { return false }
            let loc = pan.location(in: nil)
            return parent.rowFrames.contains(where: { $0.value.contains(loc) })
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Scrolls the focused text field to a uniform gap above the keyboard. SwiftUI's
/// avoidance is OFF on this screen and a bottom spacer (= keyboard height) gives
/// the scroll the range — so this can position the field itself, identically for
/// every field, without SwiftUI fighting/resetting it. Only scrolls when the
/// field is actually covered/too close; clear fields are left alone.
private struct KeyboardScrollNudge: UIViewRepresentable {
    var gap: CGFloat = 20

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        context.coordinator.hostView = v
        context.coordinator.start()
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.hostView = uiView }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: KeyboardScrollNudge
        weak var hostView: UIView?
        private var didNudge = false
        init(_ parent: KeyboardScrollNudge) { self.parent = parent }

        func start() {
            NotificationCenter.default.addObserver(self, selector: #selector(didShow(_:)),
                name: UIResponder.keyboardDidShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(willHide),
                name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        @objc func willHide() { didNudge = false }

        // Runs after the keyboard is up (so the bottom spacer is laid out and the
        // scroll has range). One nudge per keyboard session.
        @objc func didShow(_ note: Notification) {
            guard !didNudge,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let host = hostView else { return }
            var v: UIView? = host
            while let cur = v, !(cur is UIScrollView) { v = cur.superview }
            guard let scroll = v as? UIScrollView,
                  let responder = scroll.firstResponderInHierarchy else { return }
            didNudge = true
            let fieldFrame = responder.convert(responder.bounds, to: nil)   // window coords
            let overlap = fieldFrame.maxY - (frame.minY - parent.gap)
            guard overlap > 1 else { return }   // already clear → leave it
            let maxOffset = max(0, scroll.contentSize.height + scroll.adjustedContentInset.bottom
                                   - scroll.bounds.height)
            let target = min(scroll.contentOffset.y + overlap, maxOffset)
            guard target > scroll.contentOffset.y + 1 else { return }
            UIView.animate(withDuration: 0.13, delay: 0, options: [.curveEaseOut]) {
                scroll.contentOffset = CGPoint(x: scroll.contentOffset.x, y: target)
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private extension UIView {
    var firstResponderInHierarchy: UIView? {
        if isFirstResponder { return self }
        for sub in subviews { if let r = sub.firstResponderInHierarchy { return r } }
        return nil
    }
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

// MARK: - Shared popup content (Schedule editor only, for now)

/// Hours + minutes wheel where minutes snap to 5-minute steps. Hours are free
/// (0–23). `.time` renders "HH" / "MM"; `.duration` renders "Nh" / "Nm". A tap
/// (not a drag) requests the custom keypad; drags still scroll the wheel.
private struct SteppedWheel: View {
    @Binding var minutes: Int
    enum Mode { case time, duration }
    let mode: Mode
    let onRequestKeypad: () -> Void

    private let step = 5
    private var minuteOptions: [Int] { Array(stride(from: 0, to: 60, by: step)) }

    private var hourBinding: Binding<Int> {
        Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + (minutes % 60) })
    }
    private var minuteBinding: Binding<Int> {
        Binding(get: { ((minutes % 60) / step) * step },
                set: { minutes = (minutes / 60) * 60 + $0 })
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { h in
                    Text(mode == .time ? String(format: "%02d", h) : "\(h)h").tag(h)
                }
            }
            .pickerStyle(.wheel)

            if mode == .time {
                Text(":").font(.system(size: 20, weight: .semibold))
            }

            Picker("", selection: minuteBinding) {
                ForEach(minuteOptions, id: \.self) { m in
                    Text(mode == .time ? String(format: "%02d", m) : "\(m)m").tag(m)
                }
            }
            .pickerStyle(.wheel)
        }
        .frame(width: 180, height: 150)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .simultaneousGesture(TapGesture().onEnded { onRequestKeypad() })
    }
}

/// One key on the custom keypad.
private enum KeypadKey {
    case digit(String, String)   // number, decorative letters
    case backspace
    case done
}

/// Custom numeric keypad — a bottom-pinned liquid-glass panel with capsule keys,
/// replacing Apple's numpad so the layout, look, and the ✓ are fully ours.
private struct GlassKeypad: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onDone: () -> Void

    private let rows: [[KeypadKey]] = [
        [.digit("1", ""), .digit("2", "ABC"), .digit("3", "DEF")],
        [.digit("4", "GHI"), .digit("5", "JKL"), .digit("6", "MNO")],
        [.digit("7", "PQRS"), .digit("8", "TUV"), .digit("9", "WXYZ")],
        [.backspace, .digit("0", ""), .done]
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                        keyButton(key)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        // Extra bottom space lifts the keys up by ~one row (empty space below).
        .padding(.bottom, 84)
        .frame(maxWidth: .infinity)
        .background(keypadGlass)
    }

    @ViewBuilder
    private var keypadGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26.0, *) {
            // Clear glass — more see-through/glassy than .regular.
            shape.fill(.clear).glassEffect(.clear, in: shape).ignoresSafeArea(edges: .bottom)
        } else {
            BlurView(style: .systemUltraThinMaterial)
                .clipShape(shape)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func keyButton(_ key: KeypadKey) -> some View {
        switch key {
        case .digit(let number, let letters):
            Button { onDigit(number) } label: {
                VStack(spacing: 0) {
                    Text(number).font(.system(size: 24, weight: .regular))
                    if !letters.isEmpty {
                        Text(letters).font(.system(size: 9, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        case .backspace:
            Button(action: onBackspace) {
                Image(systemName: "delete.left").font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        case .done:
            Button(action: onDone) {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
        }
    }
}
