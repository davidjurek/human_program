import SwiftUI
import SwiftData
import PhotosUI
import DSKit
import UIKit

// Reminder editor — built on the Schedule editor's interaction pattern:
// SettingsScreen container, upper-right Save (disabled until valid), swipe-back,
// a discard-changes guard, and the shared AnchoredPopup + GlassKeypad for every
// value picker (Repeat, Time/Start/End wheels, the Every-N interval wheel). No
// inline-expanding rows and no Apple numpad anywhere.

struct ReminderEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let reminder: NotificationReminder?   // nil = new

    @State private var title = ""
    @State private var message = ""
    @State private var repeatMode = "once"          // "once" | "multiple"
    @State private var weekdays: Set<Int> = []
    @State private var onceMinutes = 8 * 60
    @State private var startMinutes = 8 * 60
    @State private var endMinutes = 17 * 60
    @State private var everyAmount = 1
    @State private var everyUnitHours = true
    @State private var soundMode: NotificationSoundMode = .defaultSound
    @State private var imageFilename: String?
    @State private var photoItem: PhotosPickerItem?

    @State private var activePicker: ActivePicker?            // drives the popups
    @State private var anchorFrames: [String: CGRect] = [:]   // value frames for anchoring
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var original = ReminderSnapshot()
    @State private var didLoad = false

    // Custom numeric keypad (replaces Apple's numpad for the time wheels)
    @State private var keypadVisible = false
    @State private var typedDigits = ""
    @State private var keypadMeasuredHeight: CGFloat = 0
    // Extra scroll room at the bottom while the system keyboard is up (for the
    // title / message text fields), so the focused field can lift above it.
    @State private var keyboardSpacer: CGFloat = 0

    private let scheduler = RollingReminderScheduler()

    /// One coordinate space shared by the anchor tags and the popups so they
    /// line up exactly (matches the Schedule editor).
    private let anchorSpace = "reminderAnchorSpace"

    /// What the shared anchored popup is currently editing.
    private enum ActivePicker: Equatable {
        case repeatMode, time, start, end, interval
    }

    private let repeatOptions: [(value: String, title: String)] =
        [("once", "Once"), ("multiple", "Multiple")]
    private var repeatTitle: String {
        repeatOptions.first { $0.value == repeatMode }?.title ?? ""
    }

    /// Anchor-frame id for the active picker (matches the `.anchorFrame(...)` tag).
    private func anchorId(for picker: ActivePicker) -> String {
        switch picker {
        case .repeatMode: return "repeat"
        case .time:       return "time"
        case .start:      return "start"
        case .end:        return "end"
        case .interval:   return "interval"
        }
    }

    /// Time popups widen in 12-hour mode to fit the extra AM/PM wheel column.
    private var timePopupWidth: CGFloat { TimeFormatSetting.is24Hour ? 210 : 250 }
    private var intervalUnitLabel: String {
        everyUnitHours ? (everyAmount == 1 ? "hour" : "hours") : "min"
    }

    private var canSave: Bool {
        // Needs a title AND scheduling info (at least one weekday selected).
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty
    }

    private var currentSnapshot: ReminderSnapshot {
        ReminderSnapshot(title: title, message: message, repeatMode: repeatMode, weekdays: weekdays,
                         onceMinutes: onceMinutes, startMinutes: startMinutes, endMinutes: endMinutes,
                         everyAmount: everyAmount, everyUnitHours: everyUnitHours,
                         soundMode: soundMode, imageFilename: imageFilename)
    }

    private var hasUnsavedChanges: Bool {
        // New item: only if it has enough to save. Existing: if anything changed.
        reminder == nil ? canSave : (currentSnapshot != original)
    }

    private func attemptBack() {
        if hasUnsavedChanges { showDiscardConfirm = true } else { dismiss() }
    }

    var body: some View {
        SettingsScreen(centered: true, onBack: attemptBack,
                       swipeBackBlocked: { hasUnsavedChanges },
                       manualKeyboardAvoidance: true,
                       trailing: { editorButtons }) {
            // Title (header-less: grey placeholder is the label)
            AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20))

            // Repeat — tappable value that opens a shared anchored popup.
            repeatRow

            // Days
            WeekdayCircleSelector(selected: $weekdays)

            // Time
            if repeatMode == "once" {
                valueRow(label: "Time", value: clockString(minutesOfDay: onceMinutes), anchorId: "time") {
                    if !dismissOpenInputIfAny() { activePicker = .time }
                }
            } else {
                valueRow(label: "Start", value: clockString(minutesOfDay: startMinutes), anchorId: "start") {
                    if !dismissOpenInputIfAny() { activePicker = .start }
                }
                valueRow(label: "Every", value: "\(everyAmount) \(intervalUnitLabel)", anchorId: "interval") {
                    if !dismissOpenInputIfAny() { activePicker = .interval }
                }
                valueRow(label: "End", value: clockString(minutesOfDay: endMinutes), anchorId: "end") {
                    if !dismissOpenInputIfAny() { activePicker = .end }
                }
            }

            // Sound (only the value is tappable)
            HStack {
                DSText("Sound").dsTextStyle(.title3)
                Spacer()
                NavigationLink {
                    SoundListView(selection: $soundMode)
                } label: {
                    HStack(spacing: 4) {
                        Text("Default").font(appFont(18)).foregroundStyle(.primary)
                        DSChevronView()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(cornerRadius: 4)
            }
            .frame(height: 34)

            // Optional image
            imageSection

            // Message / note — at the bottom so it can grow without moving
            // the controls above it. Multiline, expands to fit.
            AppTextField(text: $message, placeholder: "Message", fontSize: appScaledSize(18), multiline: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(KeyboardScrollNudge())

            // Room for the focused field to lift above the system keyboard.
            Color.clear.frame(height: keyboardSpacer)
        }
        .onPreferenceChange(AnchorFrameKey.self) { anchorFrames = $0 }
        .overlay {
            if showDeleteConfirm {
                ConfirmPopup(
                    message: "Delete reminder?",
                    confirmTitle: "Delete",
                    onConfirm: { deleteReminder() },
                    onCancel: { showDeleteConfirm = false }
                )
            }
            if showDiscardConfirm {
                ConfirmPopup(
                    message: "Discard Changes?",
                    confirmTitle: "Discard",
                    onConfirm: { dismiss() },
                    onCancel: { showDiscardConfirm = false }
                )
            }
            anchoredPopup
            if keypadVisible {
                KeypadOverlay(onDigit: keypadDigit, onBackspace: keypadBackspace, onDone: keypadDone,
                              onHeight: { keypadMeasuredHeight = $0 })
                    .zIndex(2)
            }
        }
        .coordinateSpace(.named(anchorSpace))
        .onChange(of: activePicker) { _, v in
            if v == nil, keypadVisible {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { keypadVisible = false }
            }
        }
        .keyboardSpacer($keyboardSpacer)
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Repeat picker (shared anchored popup)

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

    // MARK: - Reusable value row (label + tappable value that opens a popup)

    private func valueRow(label: String, value: String, anchorId: String,
                          action: @escaping () -> Void) -> some View {
        PlanningValueRow(label: label, value: value, anchorId: anchorId,
                         anchorSpace: anchorSpace, action: action)   // [#43] shared row
    }

    // MARK: - Shared anchored popup (repeat, time wheels, interval wheel)

    @ViewBuilder
    private var anchoredPopup: some View {
        if let picker = activePicker, let rect = anchorFrames[anchorId(for: picker)] {
            let close = { dismissKeypadAndPopup() }
            let space = CoordinateSpace.named(anchorSpace)
            let inset: CGFloat = keypadVisible ? (keypadMeasuredHeight > 0 ? keypadMeasuredHeight : 320) : 0
            switch picker {
            case .repeatMode:
                AnchoredPopup(anchor: rect, width: 210, estimatedHeight: 112,
                              alignment: .trailing, space: space, onClose: { activePicker = nil }) {
                    repeatOptionList
                }
            case .time:
                AnchoredPopup(anchor: rect, width: timePopupWidth, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $onceMinutes, mode: .time, onRequestKeypad: showKeypad)
                }
            case .start:
                AnchoredPopup(anchor: rect, width: timePopupWidth, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $startMinutes, mode: .time, onRequestKeypad: showKeypad)
                }
            case .end:
                AnchoredPopup(anchor: rect, width: timePopupWidth, estimatedHeight: 185,
                              alignment: .trailing, space: space, bottomInset: inset, onClose: close) {
                    SteppedWheel(minutes: $endMinutes, mode: .time, onRequestKeypad: showKeypad)
                }
            case .interval:
                // No keypad here — the interval wheel scrolls only.
                AnchoredPopup(anchor: rect, width: 200, estimatedHeight: 185,
                              alignment: .trailing, space: space, onClose: { activePicker = nil }) {
                    IntervalWheel(amount: $everyAmount, unitIsHours: $everyUnitHours)
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
                .a11yTapBorder(Rectangle())
            }
        }
    }

    // MARK: - Custom keypad (HHMM entry for the time wheels)

    /// The minutes binding the keypad currently types into (matches activePicker).
    private var activeMinutesBinding: Binding<Int>? {
        switch activePicker {
        case .time:  return $onceMinutes
        case .start: return $startMinutes
        case .end:   return $endMinutes
        default:     return nil
        }
    }

    private func showKeypad() {
        typedDigits = ""
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { keypadVisible = true }
    }

    private func keypadDigit(_ d: String) { TimeKeypadEntry.digit(d, typed: &typedDigits, into: activeMinutesBinding) }
    private func keypadBackspace() { TimeKeypadEntry.backspace(typed: &typedDigits, into: activeMinutesBinding) }
    private func keypadDone() { dismissKeypadAndPopup() }

    /// Eases the keypad down and the popup out together.
    private func dismissKeypadAndPopup() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            keypadVisible = false
            activePicker = nil
        }
    }

    /// If a keypad/popup is open, dismiss it and return true — so a tap on a value
    /// while something is open just CLOSES it instead of opening a new popup.
    private func dismissOpenInputIfAny() -> Bool {
        if keypadVisible || activePicker != nil {
            dismissKeypadAndPopup()
            return true
        }
        return false
    }

    // MARK: - Custom top bar (bare icons, no glass card)

    @ViewBuilder
    private var editorButtons: some View {
        if reminder != nil {
            EditorDeleteButton { showDeleteConfirm = true }
        }
        EditorSaveButton(enabled: canSave) { save() }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSText("Image").dsTextStyle(.title3)
                Spacer(minLength: 8)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(imageFilename == nil ? "Add" : "Change").font(appFont(18))
                        .contentShape(Rectangle())
                }
                .a11yTapBorder(cornerRadius: 4)
            }
            .frame(height: 34)

            if let filename = imageFilename, let image = ReminderImageStore.load(filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            ReminderImageStore.delete(filename)
                            imageFilename = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, .black.opacity(0.4))
                                .padding(8)
                                .contentShape(Circle())
                                .a11yTapBorder(Circle())
                        }
                    }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let name = ReminderImageStore.save(data) {
                    imageFilename = name
                }
            }
        }
    }

    // MARK: - Load / Save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        defer { original = currentSnapshot }
        guard let r = reminder else { return }
        title = r.title
        message = r.message
        weekdays = Set(r.weekdays)
        soundMode = r.soundMode
        imageFilename = r.imageFilename
        if r.recurrenceMode == .everyNMinutes {
            repeatMode = "multiple"
            startMinutes = r.windowStartMinute
            endMinutes = r.windowEndMinute
            if r.intervalMinutes >= 60, r.intervalMinutes % 60 == 0 {
                everyUnitHours = true
                everyAmount = min(10, r.intervalMinutes / 60)
            } else {
                everyUnitHours = false
                everyAmount = max(1, min(59, r.intervalMinutes))
            }
        } else {
            repeatMode = "once"
            onceMinutes = r.fireHour * 60 + r.fireMinute
        }
    }

    private func deleteReminder() {
        showDeleteConfirm = false
        guard let reminder else { return }
        let id = reminder.id
        do {
            try NotificationReminderRepository(context: context).delete(reminder)
            scheduler.cancel(reminderId: id)
        } catch {
            print("[ReminderEditor] delete error: \(error)")
        }
        dismiss()
    }

    private func save() {
        let repo = NotificationReminderRepository(context: context)
        let mode: NotificationRecurrenceMode = repeatMode == "multiple" ? .everyNMinutes : .selectedWeekdays
        let fh = (repeatMode == "multiple" ? startMinutes : onceMinutes) / 60
        let fm = (repeatMode == "multiple" ? startMinutes : onceMinutes) % 60

        do {
            // One write path for both new and edit: get-or-create the object, set every
            // field once, then save once (no create()+update() double-write).
            let target = reminder ?? repo.makeNew()
            target.title = title
            target.message = message
            target.recurrenceMode = mode
            target.weekdays = weekdays.sorted()
            target.fireHour = fh
            target.fireMinute = fm
            if repeatMode == "multiple" {
                target.windowStartMinute = startMinutes
                target.windowEndMinute = endMinutes
                target.intervalMinutes = everyUnitHours ? everyAmount * 60 : everyAmount
            }
            target.soundMode = soundMode
            target.imageFilename = imageFilename
            try repo.update(target)

            let all = (try? repo.fetchAll()) ?? []
            Task { await scheduler.reschedule(reminders: all) }
        } catch {
            print("[ReminderEditor] save error: \(error)")
        }
        dismiss()
    }
}

/// Snapshot of the editable fields, to detect unsaved changes.
private struct ReminderSnapshot: Equatable {
    var title = ""
    var message = ""
    var repeatMode = "once"
    var weekdays: Set<Int> = []
    var onceMinutes = 8 * 60
    var startMinutes = 8 * 60
    var endMinutes = 17 * 60
    var everyAmount = 1
    var everyUnitHours = true
    var soundMode: NotificationSoundMode = .defaultSound
    var imageFilename: String?
}

/// Stores reminder images on disk (app support), returns the filename.
enum ReminderImageStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReminderImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try jpeg.write(to: dir.appendingPathComponent(name)); return name } catch { return nil }
    }

    static func load(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(filename).path)
    }

    /// On-disk URL for a stored image — used by the notification scheduler so it
    /// looks in the SAME directory the image was saved to. [#57]
    static func url(for filename: String) -> URL { dir.appendingPathComponent(filename) }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
    }
}
