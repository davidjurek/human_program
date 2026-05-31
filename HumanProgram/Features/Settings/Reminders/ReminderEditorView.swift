import SwiftUI
import SwiftData
import PhotosUI
import DSKit

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
    @State private var openSection: String?
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var original = ReminderSnapshot()
    @State private var didLoad = false

    private let scheduler = RollingReminderScheduler()

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
                       swipeBackBlocked: { hasUnsavedChanges }, trailing: { editorButtons }) {
            // Title (header-less: grey placeholder is the label)
            AppTextField(text: $title, placeholder: "Title", fontSize: 20)

            // Repeat
            AppDropdown(
                label: "Repeat",
                options: [("once", "Once"), ("multiple", "Multiple")],
                selection: $repeatMode,
                openSection: $openSection,
                id: "repeat"
            )

            // Days
            WeekdayCircleSelector(selected: $weekdays)

            // Time
            if repeatMode == "once" {
                TimeFieldRow(id: "time", label: "Time", minutesOfDay: $onceMinutes, openSection: $openSection)
            } else {
                TimeFieldRow(id: "start", label: "Start", minutesOfDay: $startMinutes, openSection: $openSection)
                IntervalFieldRow(id: "every", label: "Every", amount: $everyAmount, unitIsHours: $everyUnitHours, openSection: $openSection)
                TimeFieldRow(id: "end", label: "End", minutesOfDay: $endMinutes, openSection: $openSection)
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
                }
                .buttonStyle(.plain)
            }
            .frame(height: 34)

            // Optional image
            imageSection

            // Message / note — at the bottom so it can grow without moving
            // the controls above it. Multiline, expands to fit.
            AppTextField(text: $message, placeholder: "Message", fontSize: 20, multiline: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Custom top bar (bare icons, no glass card)

    @ViewBuilder
    private var editorButtons: some View {
        if reminder != nil {
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        Button { save() } label: {
            Text("Save").font(appFont(18))
                .foregroundStyle(canSave ? .primary : .secondary)
                .frame(height: 44)
                .padding(.horizontal, 6)
        }
        .disabled(!canSave)
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
                }
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
            let target: NotificationReminder
            if let existing = reminder {
                target = existing
            } else {
                target = try repo.create(
                    title: title, message: message,
                    fireHour: fh, fireMinute: fm,
                    recurrenceMode: mode,
                    weekdays: weekdays.sorted(),
                    soundMode: soundMode
                )
            }
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

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
    }
}
