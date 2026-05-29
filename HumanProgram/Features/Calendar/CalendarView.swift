import SwiftUI
import EventKit
import SwiftData

// MARK: - View mode

enum CalendarViewMode: String, CaseIterable {
    case month  = "Month"
    case week   = "Week"
    case day    = "Day"
    case agenda = "Agenda"
}

// MARK: - CalendarView

struct CalendarView: View {

    @Environment(\.modelContext) private var context
    @State private var viewMode: CalendarViewMode = .month
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var calendarService = CalendarAdapterService()
    @State private var events: [EKEvent] = []
    @State private var displayedMonthStart: Date = CalendarView.monthStart(for: Date())
    @State private var displayedWeekStart: Date = CalendarView.weekStart(for: Date())
    @State private var selectedEvent: EKEvent? = nil
    @State private var showEventDetail = false
    @State private var showAddEvent = false
    @State private var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private var selectedCalendarIds: [String] {
        UserDefaults.standard.stringArray(forKey: "selectedCalendarIds") ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePickerBar
                Divider()
                Group {
                    switch authStatus {
                    case .notDetermined:
                        permissionRequestView
                    case .denied, .restricted:
                        permissionDeniedView
                    default:
                        calendarContent
                    }
                }
            }
            .background(AppColors.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Today") {
                        let today = Calendar.current.startOfDay(for: Date())
                        selectedDate = today
                        displayedMonthStart = CalendarView.monthStart(for: today)
                        displayedWeekStart = CalendarView.weekStart(for: today)
                        loadEvents()
                    }
                    .font(AppTypography.buttonLabel())
                    .foregroundStyle(AppColors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddEvent = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            .sheet(isPresented: $showEventDetail, onDismiss: loadEvents) {
                if let event = selectedEvent {
                    CalendarEventDetailSheet(
                        event: event,
                        date: selectedDate,
                        context: context
                    )
                }
            }
            .sheet(isPresented: $showAddEvent, onDismiss: loadEvents) {
                AddCalendarEventSheet(
                    defaultDate: selectedDate,
                    calendarService: calendarService,
                    onSave: loadEvents
                )
            }
            .task { await checkAuthAndLoad() }
        }
    }

    // MARK: - Mode picker

    private var modePickerBar: some View {
        Picker("View", selection: $viewMode) {
            ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: viewMode) { _, _ in loadEvents() }
    }

    // MARK: - Auth states

    private var permissionRequestView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            Text("Calendar Access Needed")
                .font(AppTypography.bodyMediumText())
                .foregroundStyle(AppColors.textPrimary)
            Text("Grant access so Human Program can display your calendar events.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Grant Calendar Access") {
                Task {
                    _ = await calendarService.requestAccess()
                    authStatus = calendarService.authorizationStatus
                    if calendarService.isAuthorized { loadEvents() }
                }
            }
            .font(AppTypography.buttonLabel())
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.accent, lineWidth: 1))
            Spacer()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)
            Text("Calendar Access Denied")
                .font(AppTypography.bodyMediumText())
                .foregroundStyle(AppColors.textPrimary)
            Text("Open Settings to allow calendar access for Human Program.")
                .font(AppTypography.bodySmallText())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(AppTypography.buttonLabel())
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.accent, lineWidth: 1))
            Spacer()
        }
    }

    // MARK: - Calendar content

    @ViewBuilder
    private var calendarContent: some View {
        switch viewMode {
        case .month:  monthView
        case .week:   weekView
        case .day:    dayView
        case .agenda: agendaView
        }
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 0) {
            monthNavHeader
            weekdayHeaderRow
            Divider()
            monthGrid
            Divider()
            dayEventsListBelow
                .frame(maxHeight: .infinity)
        }
    }

    private var monthNavHeader: some View {
        HStack {
            Button {
                displayedMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonthStart) ?? displayedMonthStart
                loadEvents()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTypography.navButton)
                    .foregroundStyle(AppColors.accent)
            }
            Spacer()
            Text(displayedMonthStart, format: .dateTime.month(.wide).year())
                .font(AppTypography.dateLabel())
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Button {
                displayedMonthStart = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonthStart) ?? displayedMonthStart
                loadEvents()
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTypography.navButton)
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(AppTypography.sectionHeader())
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var monthGrid: some View {
        let cal = Calendar.current
        let days = daysInMonthGrid()
        let today = cal.startOfDay(for: Date())
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(days, id: \.self) { day in
                if cal.component(.month, from: day) == cal.component(.month, from: displayedMonthStart) {
                    let hasEvents = events.contains { cal.isDate($0.startDate, inSameDayAs: day) }
                    let isToday = cal.isDate(day, inSameDayAs: today)
                    let isSelected = cal.isDate(day, inSameDayAs: selectedDate)

                    MonthDayCell(
                        day: day,
                        isToday: isToday,
                        isSelected: isSelected,
                        hasEvents: hasEvents
                    ) {
                        selectedDate = day
                    }
                } else {
                    // Filler cell from adjacent month
                    Text(String(Calendar.current.component(.day, from: day)))
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textDisabled)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var dayEventsListBelow: some View {
        let dayEvents = eventsForDay(selectedDate)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(AppTypography.bodySmallMedium)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            if dayEvents.isEmpty {
                Text("No events")
                    .font(AppTypography.bodySmallText())
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(dayEvents, id: \.eventIdentifier) { event in
                            EventRowView(event: event) {
                                selectedEvent = event
                                showEventDetail = true
                            }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Week View

    private var weekView: some View {
        VStack(spacing: 0) {
            weekNavHeader
            Divider()
            ScrollView {
                weekColumns
            }
        }
    }

    private var weekNavHeader: some View {
        HStack {
            Button {
                displayedWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: displayedWeekStart) ?? displayedWeekStart
                loadEvents()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTypography.navButton)
                    .foregroundStyle(AppColors.accent)
            }
            Spacer()
            let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: displayedWeekStart) ?? displayedWeekStart
            Text("\(displayedWeekStart, format: .dateTime.month(.abbreviated).day()) – \(weekEnd, format: .dateTime.month(.abbreviated).day().year())")
                .font(AppTypography.dateLabel())
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Button {
                displayedWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: displayedWeekStart) ?? displayedWeekStart
                loadEvents()
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTypography.navButton)
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var weekColumns: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        let dayAbbrevs = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                let isToday = cal.isDate(day, inSameDayAs: today)
                let dayEvents = eventsForDay(day)
                let dayNum = cal.component(.day, from: day)
                let abbrev = dayAbbrevs[index]

                VStack(spacing: 4) {
                    // Column header
                    VStack(spacing: 2) {
                        Text(abbrev)
                            .font(AppTypography.sectionHeader())
                            .foregroundStyle(isToday ? AppColors.accent : AppColors.textTertiary)
                        Text("\(dayNum)")
                            .font(AppTypography.caption())
                            .foregroundStyle(isToday ? AppColors.accent : AppColors.textPrimary)
                            .fontWeight(isToday ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isToday ? AppColors.accent.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Events
                    ForEach(dayEvents, id: \.eventIdentifier) { event in
                        Button {
                            selectedDate = day
                            selectedEvent = event
                            showEventDetail = true
                        } label: {
                            Text(event.title ?? "")
                                .font(AppTypography.caption())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(cgColor: event.calendar.cgColor))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if dayEvents.isEmpty {
                        Spacer(minLength: 20)
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity)

                if index < 6 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Day View

    private var dayView: some View {
        VStack(spacing: 0) {
            dayNavHeader
            Divider()
            dayTimeline
        }
    }

    private var dayNavHeader: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                loadEvents()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTypography.navButton)
                    .foregroundStyle(AppColors.accent)
            }
            Spacer()
            Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                .font(AppTypography.dateLabel())
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                loadEvents()
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTypography.navButton)
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var dayTimeline: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let isToday = cal.isDate(selectedDate, inSameDayAs: today)
        let nowMinute: Int = {
            let comps = cal.dateComponents([.hour, .minute], from: Date())
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }()
        let dayEvents = eventsForDay(selectedDate).sorted { $0.startDate < $1.startDate }
        let hourHeight: CGFloat = 56

        return ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour grid
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 8) {
                                Text(hourLabel(hour))
                                    .font(AppTypography.timeLabel())
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(width: 40, alignment: .trailing)
                                Divider()
                                Spacer()
                            }
                            .frame(height: hourHeight)
                            .id(hour)
                        }
                    }

                    // Event blocks
                    ForEach(dayEvents, id: \.eventIdentifier) { event in
                        let startMin = minuteOfDay(event.startDate)
                        let endMin = minuteOfDay(event.endDate)
                        let duration = max(endMin - startMin, 30)
                        let topOffset = CGFloat(startMin) / 60.0 * hourHeight
                        let height = CGFloat(duration) / 60.0 * hourHeight

                        Button {
                            selectedEvent = event
                            showEventDetail = true
                        } label: {
                            DayEventBlock(event: event)
                                .frame(height: height)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 56, y: topOffset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 16)
                    }

                    // Current time line
                    if isToday {
                        let topOffset = CGFloat(nowMinute) / 60.0 * hourHeight
                        HStack(spacing: 0) {
                            Circle()
                                .fill(AppColors.accentRed)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(AppColors.accentRed)
                                .frame(height: 1)
                        }
                        .offset(x: 52, y: topOffset)
                        .id("currentTime")
                    }
                }
            }
            .padding(.horizontal, 4)
            .onAppear {
                if isToday {
                    let scrollHour = max(0, (nowMinute / 60) - 1)
                    proxy.scrollTo(scrollHour, anchor: .top)
                }
            }
        }
    }

    // MARK: - Agenda View

    private var agendaView: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let futureDays: [Date] = (0..<30).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let daysWithEvents = futureDays.filter { !eventsForDay($0).isEmpty }

        return ScrollView {
            if daysWithEvents.isEmpty {
                VStack(spacing: 16) {
                    Spacer(minLength: 40)
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("No events in the next 30 days")
                        .font(AppTypography.bodySmallText())
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                    ForEach(daysWithEvents, id: \.self) { day in
                        Section {
                            VStack(spacing: 0) {
                                ForEach(eventsForDay(day), id: \.eventIdentifier) { event in
                                    EventRowView(event: event) {
                                        selectedDate = day
                                        selectedEvent = event
                                        showEventDetail = true
                                    }
                                    Divider().padding(.leading, 16)
                                }
                            }
                            .background(AppColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        } header: {
                            HStack {
                                Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                    .font(AppTypography.bodySmallMedium)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(AppColors.background)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Helpers

    private func checkAuthAndLoad() async {
        authStatus = calendarService.authorizationStatus
        if authStatus == .notDetermined {
            _ = await calendarService.requestAccess()
            authStatus = calendarService.authorizationStatus
        }
        if calendarService.isAuthorized {
            loadEvents()
        }
    }

    private func loadEvents() {
        guard calendarService.isAuthorized else { return }
        let cal = Calendar.current
        let start: Date
        let end: Date

        switch viewMode {
        case .month:
            start = displayedMonthStart
            end = cal.date(byAdding: .month, value: 1, to: displayedMonthStart) ?? displayedMonthStart
        case .week:
            start = displayedWeekStart
            end = cal.date(byAdding: .day, value: 7, to: displayedWeekStart) ?? displayedWeekStart
        case .day:
            start = cal.startOfDay(for: selectedDate)
            end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        case .agenda:
            start = cal.startOfDay(for: Date())
            end = cal.date(byAdding: .day, value: 30, to: start) ?? start
        }

        events = calendarService.fetchEvents(from: start, to: end, calendarIds: selectedCalendarIds)
    }

    private func eventsForDay(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func daysInMonthGrid() -> [Date] {
        let cal = Calendar.current
        guard let monthRange = cal.range(of: .day, in: .month, for: displayedMonthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: displayedMonthStart) // 1=Sun
        let leadingBlanks = firstWeekday - 1

        var days: [Date] = []
        for offset in stride(from: -leadingBlanks, to: monthRange.count + (7 - ((leadingBlanks + monthRange.count) % 7)) % 7, by: 1) {
            if let day = cal.date(byAdding: .day, value: offset, to: displayedMonthStart) {
                days.append(day)
            }
        }
        return days
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "a" : "p"
        return "\(h)\(suffix)"
    }

    static func monthStart(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    static func weekStart(for date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let offset = -(weekday - 1)
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: date)) ?? date
    }
}

// MARK: - Month day cell

private struct MonthDayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 30, height: 30)
                    } else if isToday {
                        Circle()
                            .fill(AppColors.accent.opacity(0.15))
                            .frame(width: 30, height: 30)
                    }
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(
                            isSelected ? .white :
                            isToday ? AppColors.accent :
                            AppColors.textPrimary
                        )
                        .fontWeight(isToday ? .semibold : .regular)
                }
                if hasEvents {
                    Circle()
                        .fill(isSelected ? .white : AppColors.accent)
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event row (agenda / day list)

private struct EventRowView: View {
    let event: EKEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 3)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title ?? "(No title)")
                        .font(AppTypography.taskTitle())
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if !event.isAllDay {
                        Text("\(event.startDate, format: .dateTime.hour().minute()) – \(event.endDate, format: .dateTime.hour().minute())")
                            .font(AppTypography.timeLabel())
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Text("All day")
                            .font(AppTypography.timeLabel())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day event block (timeline)

private struct DayEventBlock: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "(No title)")
                    .font(AppTypography.caption())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !event.isAllDay {
                    Text("\(event.startDate, format: .dateTime.hour().minute())")
                        .font(AppTypography.timeLabel())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .background(Color(cgColor: event.calendar.cgColor).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(cgColor: event.calendar.cgColor).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Add Calendar Event Sheet

struct AddCalendarEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultDate: Date
    let calendarService: CalendarAdapterService
    let onSave: () -> Void

    @State private var title = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var allCalendars: [EKCalendar] = []
    @State private var selectedCalendarId: String? = nil
    @State private var errorMessage: String? = nil
    @FocusState private var titleFocused: Bool

    init(defaultDate: Date, calendarService: CalendarAdapterService, onSave: @escaping () -> Void) {
        self.defaultDate = defaultDate
        self.calendarService = calendarService
        self.onSave = onSave
        let cal = Calendar.current
        let now = Date()
        let startComponents = cal.dateComponents([.year, .month, .day, .hour], from: defaultDate)
        let baseHour = cal.component(.hour, from: now) + 1
        var sc = startComponents
        sc.hour = baseHour
        sc.minute = 0
        let s = cal.date(from: sc) ?? defaultDate
        _startDate = State(initialValue: s)
        _endDate = State(initialValue: s.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(AppTypography.taskTitle())
                        .focused($titleFocused)
                }

                Section {
                    DatePicker("Starts", selection: $startDate)
                        .onChange(of: startDate) { _, new in
                            if endDate <= new { endDate = new.addingTimeInterval(3600) }
                        }
                    DatePicker("Ends", selection: $endDate)
                }

                if !allCalendars.isEmpty {
                    Section("Calendar") {
                        Picker("Calendar", selection: $selectedCalendarId) {
                            ForEach(allCalendars, id: \.calendarIdentifier) { cal in
                                HStack {
                                    Circle()
                                        .fill(Color(cgColor: cal.cgColor))
                                        .frame(width: 10, height: 10)
                                    Text(cal.title)
                                }
                                .tag(Optional(cal.calendarIdentifier))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(AppColors.accentRed)
                            .font(AppTypography.caption())
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveEvent() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundStyle(AppColors.accent)
                }
            }
            .onAppear {
                allCalendars = calendarService.fetchAllCalendars()
                titleFocused = true
            }
        }
    }

    private func saveEvent() {
        do {
            try calendarService.createEvent(
                title: title.trimmingCharacters(in: .whitespaces),
                start: startDate,
                end: endDate,
                calendarId: selectedCalendarId
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
