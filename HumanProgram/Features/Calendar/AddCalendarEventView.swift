import SwiftUI
import EventKit
import DSKit

// MARK: - Add Calendar Event Sheet

// Pushed DSKit page to add an Apple Calendar event. Covers every field EventKit
// supports (Invitees + Travel Time are impossible via EventKit, so omitted).
// Uses native date/time pickers; saves straight to Apple Calendar. [#40,#41]
struct AddCalendarEventView: View {
    @Environment(\.dismiss) private var dismiss
    /// When set, the form edits this existing event instead of creating a new one.
    let eventToEdit: EKEvent?
    let defaultDate: Date
    let calendarService: CalendarAdapterService
    let onSave: () -> Void

    @State private var title = ""
    @State private var location = ""
    @State private var allDay = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var repeatRule: RepeatRule = .never
    @State private var alert: AlertOption = .none
    @State private var notes = ""
    @State private var urlText = ""
    @State private var allCalendars: [EKCalendar] = []
    @State private var selectedCalendarId: String? = nil
    @State private var errorMessage: String? = nil
    @State private var keyboardSpacer: CGFloat = 0

    enum RepeatRule: String, CaseIterable, Identifiable {
        case never = "Never", daily = "Daily", weekly = "Weekly", monthly = "Monthly", yearly = "Yearly"
        var id: String { rawValue }
        var frequency: EKRecurrenceFrequency? {
            switch self {
            case .never: return nil
            case .daily: return .daily
            case .weekly: return .weekly
            case .monthly: return .monthly
            case .yearly: return .yearly
            }
        }
        /// Map an existing event's first recurrence rule back to a menu choice.
        init(from rule: EKRecurrenceRule?) {
            switch rule?.frequency {
            case .daily:   self = .daily
            case .weekly:  self = .weekly
            case .monthly: self = .monthly
            case .yearly:  self = .yearly
            default:       self = .never
            }
        }
    }
    enum AlertOption: String, CaseIterable, Identifiable {
        case none = "None", atTime = "At time of event", m5 = "5 min before",
             m10 = "10 min before", m30 = "30 min before", h1 = "1 hour before"
        var id: String { rawValue }
        var minutes: Int? {
            switch self {
            case .none: return nil
            case .atTime: return 0
            case .m5: return 5
            case .m10: return 10
            case .m30: return 30
            case .h1: return 60
            }
        }
        /// Map an existing event's first alarm back to a menu choice.
        init(from alarm: EKAlarm?) {
            guard let offset = alarm?.relativeOffset else { self = .none; return }
            switch Int((-offset) / 60) {
            case 0:  self = .atTime
            case 5:  self = .m5
            case 10: self = .m10
            case 30: self = .m30
            case 60: self = .h1
            default: self = .atTime
            }
        }
    }

    init(eventToEdit: EKEvent? = nil, defaultDate: Date,
         calendarService: CalendarAdapterService, onSave: @escaping () -> Void) {
        self.eventToEdit = eventToEdit
        self.defaultDate = defaultDate
        self.calendarService = calendarService
        self.onSave = onSave
        if let e = eventToEdit {
            // Prefill every field from the event being edited.
            _title = State(initialValue: e.title ?? "")
            _location = State(initialValue: e.location ?? "")
            _allDay = State(initialValue: e.isAllDay)
            _startDate = State(initialValue: e.startDate)
            _endDate = State(initialValue: e.endDate)
            _notes = State(initialValue: e.notes ?? "")
            _urlText = State(initialValue: e.url?.absoluteString ?? "")
            _selectedCalendarId = State(initialValue: e.calendar?.calendarIdentifier)
            _repeatRule = State(initialValue: RepeatRule(from: e.recurrenceRules?.first))
            _alert = State(initialValue: AlertOption(from: e.alarms?.first))
        } else {
            let cal = Calendar.current
            let baseHour = cal.component(.hour, from: Date()) + 1
            var sc = cal.dateComponents([.year, .month, .day], from: defaultDate)
            sc.hour = baseHour; sc.minute = 0
            let s = cal.date(from: sc) ?? defaultDate
            _startDate = State(initialValue: s)
            _endDate = State(initialValue: s.addingTimeInterval(3600))
        }
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isEditing: Bool { eventToEdit != nil }

    var body: some View {
        // Editing is presented as a modal sheet → no back chevron, Save aligned with
        // the read-mode detail sheet's Done. Adding is pushed → keep the back chevron.
        SettingsScreen(centered: true, showsBackButton: !isEditing, manualKeyboardAvoidance: true, trailing: {
            Button { saveEvent() } label: {
                DSText(isEditing ? "Save" : "Add").dsTextStyle(.body, canSave ? Color.primary : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }.disabled(!canSave)
        }) {
            SettingsSectionLabel(title: "Event")
            AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20))
            AppTextField(text: $location, placeholder: "Location", fontSize: appScaledSize(17))

            SettingsGroup(title: "Time") {
                HStack {
                    DSText("All-day").dsTextStyle(.body); Spacer()
                    Toggle("", isOn: $allDay).labelsHidden().tint(appToggleTint)
                        .a11yTapBorder(Capsule())
                }.frame(height: 34)
                HStack(spacing: 14) {
                    DSText("Starts").dsTextStyle(.body); Spacer()
                    DSDateField(date: $startDate)                       // [#13]
                    if !allDay { DSTimeField(date: $startDate) }        // [#13]
                }
                .frame(height: 34)
                .onChange(of: startDate) { _, new in if endDate <= new { endDate = new.addingTimeInterval(3600) } }
                HStack(spacing: 14) {
                    DSText("Ends").dsTextStyle(.body); Spacer()
                    DSDateField(date: $endDate, minDate: startDate)     // [#13]
                    if !allDay { DSTimeField(date: $endDate) }          // [#13]
                }
                .frame(height: 34)
                // The time wheel can push end before start; clamp it back. [#120]
                .onChange(of: endDate) { _, new in if new < startDate { endDate = startDate } }
            }

            SettingsGroup(title: "Options") {
                menuRow("Repeat", repeatRule.rawValue) {
                    ForEach(RepeatRule.allCases) { r in Button(r.rawValue) { repeatRule = r } }
                }
                menuRow("Alert", alert.rawValue) {
                    ForEach(AlertOption.allCases) { a in Button(a.rawValue) { alert = a } }
                }
                if !allCalendars.isEmpty {
                    menuRow("Calendar", selectedCalendarName) {
                        ForEach(allCalendars, id: \.calendarIdentifier) { c in
                            Button(c.title) { selectedCalendarId = c.calendarIdentifier }
                        }
                    }
                }
            }

            SettingsSectionLabel(title: "Note")
            AppTextField(text: $notes, placeholder: "Note", fontSize: appScaledSize(17), multiline: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            AppTextField(text: $urlText, placeholder: "URL", fontSize: appScaledSize(17))
                .background(KeyboardScrollNudge())   // lift the focused field above the keyboard

            if let error = errorMessage {
                DSText(error).dsTextStyle(.subheadline, Color.red)
            }

            Color.clear.frame(height: keyboardSpacer)   // scroll room for the nudge
        }
        .keyboardSpacer($keyboardSpacer)
        .onAppear {
            allCalendars = calendarService.fetchAllCalendars()
            // Auto-pick a default calendar only for brand-new events; an edited
            // event keeps its own calendar (set from the event in init). [#118]
            if !isEditing, selectedCalendarId == nil {
                selectedCalendarId = allCalendars.first?.calendarIdentifier
            }
        }
    }

    private var selectedCalendarName: String {
        // Prefer the matched picker entry. When editing an event whose real
        // calendar isn't in the editable list (read-only/subscribed), show that
        // calendar's actual name instead of a misleading "Default". [#118]
        if let match = allCalendars.first(where: { $0.calendarIdentifier == selectedCalendarId }) {
            return match.title
        }
        if let eventCal = eventToEdit?.calendar, eventCal.calendarIdentifier == selectedCalendarId {
            return eventCal.title
        }
        return "Default"
    }

    private func menuRow<Content: View>(_ label: String, _ value: String,
                                        @ViewBuilder _ menu: () -> Content) -> some View {
        HStack {
            DSText(label).dsTextStyle(.body)
            Spacer(minLength: 8)
            Menu {
                menu()
            } label: {
                HStack(spacing: 4) {
                    DSText(value).dsTextStyle(.body)
                    DSImageView(systemName: "chevron.up.chevron.down", size: .font(.caption1),
                                tint: .color(.secondary))
                }
                .contentShape(Rectangle())
            }.tint(.primary)
            .a11yTapBorder(cornerRadius: 4)
        }
        .frame(height: 34)
    }

    private func saveEvent() {
        // Final guard: never save an event that ends before it starts. [#120]
        if endDate < startDate { endDate = startDate }
        var recurrence: EKRecurrenceRule? = nil
        if let freq = repeatRule.frequency {
            recurrence = EKRecurrenceRule(recurrenceWith: freq, interval: 1, end: nil)
        }
        let spec = NewEventSpec(
            title: title.trimmingCharacters(in: .whitespaces),
            location: location,
            isAllDay: allDay,
            start: startDate,
            end: endDate,
            calendarId: selectedCalendarId,
            recurrence: recurrence,
            alarmMinutesBefore: alert.minutes,
            notes: notes,
            url: URL(string: urlText.trimmingCharacters(in: .whitespaces))
        )
        do {
            if let id = eventToEdit?.eventIdentifier {
                try calendarService.updateEvent(id: id, spec)
            } else {
                try calendarService.createEvent(spec)
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
