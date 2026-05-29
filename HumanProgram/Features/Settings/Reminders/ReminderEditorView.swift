import SwiftUI
import SwiftData

// MARK: - ReminderEditorView

struct ReminderEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = creating new; non-nil = editing existing
    let reminder: NotificationReminder?

    // Form state
    @State private var title: String = ""
    @State private var message: String = ""
    @State private var isEnabled: Bool = true
    @State private var recurrenceMode: NotificationRecurrenceMode = .daily
    @State private var selectedWeekdays: Set<Int> = []    // 1=Sun…7=Sat
    @State private var intervalMinutes: Int = 30
    @State private var windowStart: Date = defaultWindowStart()
    @State private var windowEnd: Date = defaultWindowEnd()
    @State private var fireTime: Date = defaultFireTime()
    @State private var soundMode: NotificationSoundMode = .defaultSound

    // UX
    @State private var showUnsavedAlert = false
    @State private var saveError: String?
    @FocusState private var titleFocused: Bool

    private let scheduler = RollingReminderScheduler()

    private var isNew: Bool { reminder == nil }
    private var isTitleValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Defaults

    private static func defaultFireTime() -> Date {
        var c = DateComponents(); c.hour = 8; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }
    private static func defaultWindowStart() -> Date {
        var c = DateComponents(); c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }
    private static func defaultWindowEnd() -> Date {
        var c = DateComponents(); c.hour = 17; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleField
                        Divider().padding(.horizontal, 16)
                        messageField
                        Divider().padding(.horizontal, 16)
                        enabledToggle
                        Divider().padding(.horizontal, 16)
                        recurrencePicker
                        conditionalFields
                        Divider().padding(.horizontal, 16)
                        soundPicker
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(isNew ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .font(AppTypography.bodyMediumText())
                    .foregroundStyle(isTitleValid ? AppColors.accent : AppColors.textTertiary)
                    .disabled(!isTitleValid)
                }
            }
            .alert("Save Error", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveError ?? "An unknown error occurred.")
            }
        }
        .onAppear { populateFields() }
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("TITLE")
            TextField("Reminder name", text: $title)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .focused($titleFocused)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .submitLabel(.next)
        }
    }

    // MARK: - Message

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("MESSAGE")
            TextField("Notification body (optional)", text: $message, axis: .vertical)
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2...4)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    // MARK: - Enabled toggle

    private var enabledToggle: some View {
        Toggle(isOn: $isEnabled) {
            Text("Enabled")
                .font(AppTypography.bodyText())
                .foregroundStyle(AppColors.textPrimary)
        }
        .toggleStyle(SwitchToggleStyle(tint: AppColors.accentGreen))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Recurrence mode picker

    private var recurrencePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("REPEAT")
            Picker("Repeat", selection: $recurrenceMode) {
                Text("Daily").tag(NotificationRecurrenceMode.daily)
                Text("Weekdays").tag(NotificationRecurrenceMode.weekdays)
                Text("Selected Days").tag(NotificationRecurrenceMode.selectedWeekdays)
                Text("Every N Minutes").tag(NotificationRecurrenceMode.everyNMinutes)
                Text("Hourly Window").tag(NotificationRecurrenceMode.hourlyWindow)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Conditional fields

    @ViewBuilder
    private var conditionalFields: some View {
        Divider().padding(.horizontal, 16)
        switch recurrenceMode {
        case .daily:
            fireTimePicker(label: "TIME")
        case .weekdays:
            fireTimePicker(label: "TIME")
        case .selectedWeekdays:
            weekdaySelector
            Divider().padding(.horizontal, 16)
            fireTimePicker(label: "TIME")
        case .everyNMinutes:
            intervalStepper
            Divider().padding(.horizontal, 16)
            windowTimePickers(label: "ACTIVE WINDOW")
        case .hourlyWindow:
            windowTimePickers(label: "WINDOW")
            Divider().padding(.horizontal, 16)
            weekdaySelector
        }
    }

    // MARK: - Fire time picker

    private func fireTimePicker(label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(label)
            DatePicker(
                "Fire time",
                selection: $fireTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Weekday selector (S M T W T F S)

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DAYS")
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let selected = selectedWeekdays.contains(weekday)
                    Button {
                        if selected {
                            selectedWeekdays.remove(weekday)
                        } else {
                            selectedWeekdays.insert(weekday)
                        }
                    } label: {
                        Text(shortWeekdayLetter(weekday))
                            .font(AppTypography.buttonLabel())
                            .foregroundStyle(selected ? .white : AppColors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(selected ? AppColors.accent : AppColors.surfaceElevated)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selected ? AppColors.accent : AppColors.border,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Interval stepper

    private var intervalStepper: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("INTERVAL")
            HStack {
                Text("Every \(intervalMinutes) min")
                    .font(AppTypography.bodyText())
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Stepper("", value: $intervalMinutes, in: 5...120, step: 5)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Window time pickers (start + end)

    private func windowTimePickers(label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(label)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.textTertiary)
                    DatePicker(
                        "Start",
                        selection: $windowStart,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End")
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.textTertiary)
                    DatePicker(
                        "End",
                        selection: $windowEnd,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Sound picker

    private var soundPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("SOUND")
            Picker("Sound", selection: $soundMode) {
                Text("Default").tag(NotificationSoundMode.defaultSound)
                Text("Silent").tag(NotificationSoundMode.silent)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Section label helper

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.sectionHeader())
            .foregroundStyle(AppColors.textTertiary)
            .kerning(0.4)
            .padding(.horizontal, 16)
            .padding(.top, 14)
    }

    // MARK: - Populate fields from existing reminder

    private func populateFields() {
        if let r = reminder {
            title = r.title
            message = r.message
            isEnabled = r.isEnabled
            recurrenceMode = r.recurrenceMode
            selectedWeekdays = Set(r.weekdays)
            intervalMinutes = max(5, r.intervalMinutes)
            fireTime = timeDate(hour: r.fireHour, minute: r.fireMinute)
            windowStart = minuteOfDayToDate(r.windowStartMinute)
            windowEnd = minuteOfDayToDate(r.windowEndMinute)
            soundMode = r.soundMode
        }
        titleFocused = isNew
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let cal = Calendar.current
        let fHour = cal.component(.hour, from: fireTime)
        let fMinute = cal.component(.minute, from: fireTime)
        let wsMinute = cal.component(.hour, from: windowStart) * 60 + cal.component(.minute, from: windowStart)
        let weMinute = cal.component(.hour, from: windowEnd) * 60 + cal.component(.minute, from: windowEnd)
        let weekdaysArray = selectedWeekdays.sorted()

        do {
            let repo = NotificationReminderRepository(context: context)

            if let existing = reminder {
                existing.title = trimmedTitle
                existing.message = message
                existing.isEnabled = isEnabled
                existing.recurrenceMode = recurrenceMode
                existing.weekdays = weekdaysArray
                existing.fireHour = fHour
                existing.fireMinute = fMinute
                existing.intervalMinutes = intervalMinutes
                existing.windowStartMinute = wsMinute
                existing.windowEndMinute = weMinute
                existing.soundMode = soundMode
                try repo.update(existing)
            } else {
                let newReminder = try repo.create(
                    title: trimmedTitle,
                    message: message,
                    fireHour: fHour,
                    fireMinute: fMinute,
                    recurrenceMode: recurrenceMode,
                    weekdays: weekdaysArray,
                    soundMode: soundMode
                )
                newReminder.isEnabled = isEnabled
                newReminder.intervalMinutes = intervalMinutes
                newReminder.windowStartMinute = wsMinute
                newReminder.windowEndMinute = weMinute
                try repo.update(newReminder)
            }

            let all = (try? repo.fetchAll()) ?? []
            Task {
                await scheduler.reschedule(reminders: all)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Conversion helpers

    private func timeDate(hour: Int, minute: Int) -> Date {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }

    private func minuteOfDayToDate(_ minutes: Int) -> Date {
        timeDate(hour: minutes / 60, minute: minutes % 60)
    }

    private func shortWeekdayLetter(_ weekday: Int) -> String {
        // 1=Sun 2=Mon 3=Tue 4=Wed 5=Thu 6=Fri 7=Sat
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        let index = weekday - 1
        guard index >= 0, index < letters.count else { return "?" }
        return letters[index]
    }
}
