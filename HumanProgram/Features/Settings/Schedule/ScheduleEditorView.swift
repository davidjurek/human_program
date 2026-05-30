import SwiftUI
import SwiftData
import DSKit

// Schedule editor, built on the Reminder-editor pattern: SettingsScreen
// container, upper-right Save (disabled until valid), swipe-back, and a
// discard-changes guard that stays quiet when nothing was entered.
//
// Layout: Name · Repeat (Weekly | Custom range) · 7-day circles (always) ·
// From/To (custom range only) · Sleep from/to · block list (Sleep first,
// hold-drag to reorder) · inline add-block row with a time-remaining readout
// and a "+" that disables when the block won't fit in 24h.
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

    @State private var openSection: String?
    @State private var showDeleteConfirm = false
    @State private var showDiscardConfirm = false
    @State private var conflictMessage: String?
    @State private var original = ScheduleSnapshot()
    @State private var didLoad = false

    // Drag-to-reorder
    @State private var draggingId: UUID?
    @State private var dragOffset: CGFloat = 0
    private let rowHeight: CGFloat = 60

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
        SettingsScreen(centered: true, onBack: attemptBack, trailing: { editorButtons }) {
            AppTextField(text: $name, placeholder: "Schedule name", fontSize: 20)

            if let conflictMessage {
                Text(conflictMessage)
                    .font(appFont(15)).foregroundStyle(.red)
            }

            AppDropdown(
                label: "Repeat",
                options: [("weekly", "Weekly"), ("custom", "Custom range")],
                selection: $repeatMode, openSection: $openSection, id: "repeat"
            )

            WeekdayCircleSelector(selected: $weekdays)

            if repeatMode == "custom" {
                DateFieldRow(label: "From", date: $fromDate)
                DateFieldRow(label: "To", date: $toDate, notBefore: fromDate)
            }

            // Sleep
            SettingsSectionLabel(title: "Sleep")
            TimeFieldRow(id: "sleepFrom", label: "Sleep from", minutesOfDay: $sleepStart, openSection: $openSection)
            TimeFieldRow(id: "sleepTo", label: "Sleep to", minutesOfDay: $sleepEnd, openSection: $openSection)

            // Blocks
            SettingsSectionLabel(title: "Blocks")
            blockList
            addBlockRow
        }
        .overlay {
            if showDeleteConfirm {
                ConfirmPopup(message: "Delete schedule?", confirmTitle: "Delete",
                             onConfirm: { deleteSchedule() }, onCancel: { showDeleteConfirm = false })
            }
            if showDiscardConfirm {
                ConfirmPopup(message: "Discard Changes?", confirmTitle: "Discard",
                             onConfirm: { dismiss() }, onCancel: { showDiscardConfirm = false })
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    @ViewBuilder
    private var editorButtons: some View {
        if template != nil {
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash").font(.system(size: 18))
                    .foregroundStyle(.red).frame(width: 44, height: 44)
            }
        }
        Button { save() } label: {
            Text("Save").font(appFont(18))
                .foregroundStyle(canSave ? .primary : .secondary)
                .frame(height: 44).padding(.horizontal, 6)
        }
        .disabled(!canSave)
    }

    // MARK: - Block list (Sleep first, then draggable non-sleep blocks)

    private var blockList: some View {
        VStack(spacing: 0) {
            // Sleep row — fixed first, not draggable.
            blockRowContent(title: "Sleep", start: sleepStart, end: sleepEnd,
                            duration: sleepDuration, draggable: false, draftIndex: nil)

            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                let times = blockTimes[index]
                blockRowContent(title: block.title, start: times.start, end: times.end,
                                duration: block.duration, draggable: true, draftIndex: index)
                    .offset(y: draggingId == block.id ? dragOffset : 0)
                    .zIndex(draggingId == block.id ? 1 : 0)
                    .gesture(dragGesture(for: index, id: block.id))
            }
        }
    }

    private func blockRowContent(title: String, start: Int, end: Int, duration: Int,
                                 draggable: Bool, draftIndex: Int?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                DSText(title.isEmpty ? "Untitled" : title).dsTextStyle(.body)
                    .lineLimit(1)
                Text("\(hhmm(start))–\(hhmm(end))")
                    .font(appFont(14)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(durationText(duration))
                .font(appFont(15)).foregroundStyle(.secondary)

            if let draftIndex {
                Button { removeBlock(at: draftIndex) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .opacity(draggable ? 1 : 1)
    }

    private func dragGesture(for index: Int, id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture())
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    draggingId = id
                    dragOffset = drag.translation.height
                }
            }
            .onEnded { _ in
                let shift = Int((dragOffset / rowHeight).rounded())
                let target = max(0, min(blocks.count - 1, index + shift))
                if target != index {
                    let moved = blocks.remove(at: index)
                    blocks.insert(moved, at: target)
                }
                draggingId = nil
                dragOffset = 0
            }
    }

    // MARK: - Add-block row

    private var addBlockRow: some View {
        VStack(spacing: 10) {
            AppTextField(text: $newTitle, placeholder: "Block title", fontSize: 18)
            DurationFieldRow(id: "newDuration", label: "Duration", minutes: $newDuration, openSection: $openSection)
            HStack {
                DSText(remaining == 0 ? "Day full" : "\(durationText(remaining)) left")
                    .dsTextStyle(.subheadline)
                Spacer()
                Button { addBlock() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(canAddBlock ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAddBlock)
            }
        }
    }

    private func addBlock() {
        guard canAddBlock else { return }
        blocks.append(DraftBlock(title: newTitle.trimmingCharacters(in: .whitespaces), duration: newDuration))
        newTitle = ""
    }

    private func removeBlock(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        blocks.remove(at: index)
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
    private func durationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

/// A non-sleep block while editing: title + duration (times are derived).
struct DraftBlock: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var duration: Int   // minutes
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
