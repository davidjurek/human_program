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
        SettingsScreen(centered: true, trailing: {
            Button { saveEvent() } label: {
                Text(isEditing ? "Save" : "Add").font(appFont(18))
                    .foregroundStyle(canSave ? .primary : .secondary)
                    .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }.disabled(!canSave)
        }) {
            SettingsSectionLabel(title: "Event")
            AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20))
            AppTextField(text: $location, placeholder: "Location", fontSize: 17)

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
                }.frame(height: 34)
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
            AppTextField(text: $notes, placeholder: "Note", fontSize: 17, multiline: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            AppTextField(text: $urlText, placeholder: "URL", fontSize: 17)

            if let error = errorMessage {
                DSText(error).dsTextStyle(.subheadline, Color.red)
            }
        }
        .onAppear {
            allCalendars = calendarService.fetchAllCalendars()
            if selectedCalendarId == nil { selectedCalendarId = allCalendars.first?.calendarIdentifier }
        }
    }

    private var selectedCalendarName: String {
        allCalendars.first(where: { $0.calendarIdentifier == selectedCalendarId })?.title ?? "Default"
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
                    Text(value).font(appFont(17)).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }.tint(.primary)
            .a11yTapBorder(cornerRadius: 4)
        }
        .frame(height: 34)
    }

    private func saveEvent() {
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
