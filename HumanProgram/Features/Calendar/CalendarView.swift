import SwiftUI
import EventKit
import SwiftData
import DSKit

// MARK: - View mode

enum CalendarViewMode: String, CaseIterable {
    case month  = "Month"
    case week   = "Week"
    case day    = "Day"
    case list   = "List"
}

// MARK: - CalendarView

struct CalendarView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
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
        ZStack {
            SettingsBackground()
            VStack(spacing: 0) {
                modePickerBar
                Divider().opacity(0.4)
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
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEventDetail, onDismiss: loadEvents) {
            if let event = selectedEvent {
                CalendarEventDetailSheet(event: event, date: selectedDate, context: context)
            }
        }
        .navigationDestination(isPresented: $showAddEvent) {
            AddCalendarEventView(defaultDate: selectedDate, calendarService: calendarService, onSave: loadEvents)
        }
        .task { await checkAuthAndLoad() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            Button { goToday() } label: { DSText("Today").dsTextStyle(.subheadline) }.buttonStyle(.plain)
            Button { showAddEvent = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func goToday() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDate = today
        displayedMonthStart = CalendarView.monthStart(for: today)
        displayedWeekStart = CalendarView.weekStart(for: today)
        loadEvents()
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
                .foregroundStyle(Color.secondary)
            Text("Calendar Access Needed")
                .font(appFont(17))
                .foregroundStyle(Color.primary)
            Text("Grant access so Human Program can display your calendar events.")
                .font(appFont(14))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Grant Calendar Access") {
                Task {
                    _ = await calendarService.requestAccess()
                    authStatus = calendarService.authorizationStatus
                    if calendarService.isAuthorized { loadEvents() }
                }
            }
            .font(appFont(16))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
            Spacer()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("Calendar Access Denied")
                .font(appFont(17))
                .foregroundStyle(Color.primary)
            Text("Open Settings to allow calendar access for Human Program.")
                .font(appFont(14))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(appFont(16))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
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
        case .list: agendaView
        }
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 0) {
            monthNavHeader
            weekdayHeaderRow
            Divider()
            monthGrid
                .horizontalSwipe { changeMonth($0) }   // swipe left = next month [#42]
            Divider()
            dayEventsListBelow
                .frame(maxHeight: .infinity)
        }
    }

    private var monthNavHeader: some View {
        HStack {
            Spacer()
            Text(displayedMonthStart, format: .dateTime.month(.wide).year())
                .font(appFont(20, bold: true))
                .foregroundStyle(Color.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func changeMonth(_ delta: Int) {
        displayedMonthStart = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonthStart) ?? displayedMonthStart
        loadEvents()
    }
    private func changeWeek(_ deltaDays: Int) {
        displayedWeekStart = Calendar.current.date(byAdding: .day, value: deltaDays, to: displayedWeekStart) ?? displayedWeekStart
        loadEvents()
    }
    private func changeDay(_ delta: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
        loadEvents()
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(appFont(13, bold: true))
                    .foregroundStyle(Color.secondary)
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
                        .font(appFont(17))
                        .foregroundStyle(Color.gray.opacity(0.4))
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
                    .font(appFont(15, bold: true))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            if dayEvents.isEmpty {
                Text("No events")
                    .font(appFont(14))
                    .foregroundStyle(Color.secondary)
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
            weekDayHeaderRow
            Divider()
            weekTimeline
        }
        .horizontalSwipe { changeWeek($0 * 7) }   // swipe left = next week [#42]
    }

    private var weekNavHeader: some View {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: displayedWeekStart) ?? displayedWeekStart
        return HStack {
            Spacer()
            Text("\(displayedWeekStart, format: .dateTime.month(.abbreviated).day()) – \(weekEnd, format: .dateTime.month(.abbreviated).day().year())")
                .font(appFont(20, bold: true))
                .foregroundStyle(Color.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // Day-of-week + date header aligned over the 7 columns (with a left time gutter).
    private var weekDayHeaderRow: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        let abbrevs = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 0) {
            Color.clear.frame(width: weekTimeColW)
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                let isToday = cal.isDate(day, inSameDayAs: today)
                VStack(spacing: 1) {
                    Text(abbrevs[idx]).font(appFont(11))
                        .foregroundStyle(isToday ? Color.red : Color.secondary)
                    Text("\(cal.component(.day, from: day))").font(appFont(13, bold: isToday))
                        .foregroundStyle(isToday ? Color.red : Color.primary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private let weekTimeColW: CGFloat = 38
    private let weekHourHeight: CGFloat = 44

    // 7-day time grid: left time column, 24 hour lines, red now-bar, events placed
    // in their day column by time. [#44]
    private var weekTimeline: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        let nowMin = minuteOfDay(Date())
        let totalH = weekHourHeight * 24

        return ScrollView {
            GeometryReader { geo in
                let colW = (geo.size.width - weekTimeColW) / 7
                ZStack(alignment: .topLeading) {
                    // Hour lines + labels.
                    ForEach(0..<24, id: \.self) { hour in
                        let y = CGFloat(hour) * weekHourHeight
                        Rectangle().fill(Color.primary.opacity(0.08))
                            .frame(height: 1).offset(x: weekTimeColW, y: y)
                        Text(hourLabel(hour)).font(appFont(10)).foregroundStyle(.secondary)
                            .frame(width: weekTimeColW - 4, alignment: .trailing)
                            .offset(x: 0, y: max(0, y - 5))
                    }
                    // Events per day column.
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                        ForEach(eventsForDay(day), id: \.eventIdentifier) { event in
                            let s = minuteOfDay(event.startDate)
                            let e = minuteOfDay(event.endDate)
                            let h = max(weekHourHeight / 3, CGFloat(max(e - s, 20)) / 60 * weekHourHeight)
                            Button {
                                selectedDate = day; selectedEvent = event; showEventDetail = true
                            } label: {
                                Text(event.title ?? "")
                                    .font(appFont(9)).foregroundStyle(.white)
                                    .lineLimit(2).padding(.horizontal, 3).padding(.vertical, 1)
                                    .frame(width: colW - 2, height: h, alignment: .topLeading)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(cgColor: event.calendar.cgColor)))
                            }.buttonStyle(.plain)
                            .offset(x: weekTimeColW + CGFloat(idx) * colW + 1,
                                    y: CGFloat(s) / 60 * weekHourHeight)
                        }
                    }
                    // Red now-bar across, if this week contains today.
                    if weekDays.contains(where: { cal.isDate($0, inSameDayAs: today) }) {
                        Rectangle().fill(Color.red).frame(height: 1)
                            .offset(x: weekTimeColW, y: CGFloat(nowMin) / 60 * weekHourHeight)
                    }
                }
                .frame(height: totalH)
            }
            .frame(height: totalH)
        }
    }

    // MARK: - Day View

    private var dayView: some View {
        VStack(spacing: 0) {
            dayNavHeader
            Divider()
            dayTimeline
        }
        .horizontalSwipe { changeDay($0) }   // swipe left = next day [#42]
    }

    private var dayNavHeader: some View {
        HStack {
            Spacer()
            Text(selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                .font(appFont(20, bold: true))
                .foregroundStyle(Color.primary)
            Spacer()
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
                    // Hour grid: time label + full-width horizontal line per hour. [#43]
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 8) {
                                Text(hourLabel(hour))
                                    .font(appFont(11))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                Rectangle().fill(Color.primary.opacity(0.08))
                                    .frame(height: 1)
                                    .padding(.top, 7)
                            }
                            .frame(height: hourHeight, alignment: .top)
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

                    // Current time line: red time pill (left) + full-width line. [#43]
                    if isToday {
                        let topOffset = CGFloat(nowMinute) / 60.0 * hourHeight
                        HStack(spacing: 4) {
                            Text(nowTimeString)
                                .font(appFont(10, bold: true)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                            Rectangle().fill(Color.red).frame(height: 1)
                        }
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity)
                        .offset(y: topOffset - 8)
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
                        .foregroundStyle(Color.secondary)
                    Text("No events in the next 30 days")
                        .font(appFont(14))
                        .foregroundStyle(Color.secondary)
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
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        } header: {
                            HStack {
                                Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                    .font(appFont(15, bold: true))
                                    .foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.clear)
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
        case .list:
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

    private var nowTimeString: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
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

// MARK: - Horizontal swipe (calendar navigation)

private extension View {
    /// Calls `action(+1)` on a left swipe (forward in time) and `action(-1)` on a
    /// right swipe. Only fires for clearly-horizontal drags so vertical scrolling
    /// still works.
    func horizontalSwipe(_ action: @escaping (Int) -> Void) -> some View {
        gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    action(v.translation.width < 0 ? 1 : -1)
                }
        )
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
                            .fill(Color.accentColor)
                            .frame(width: 30, height: 30)
                    } else if isToday {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 30, height: 30)
                    }
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(appFont(17))
                        .foregroundStyle(
                            isSelected ? .white :
                            isToday ? Color.accentColor :
                            Color.primary
                        )
                        .fontWeight(isToday ? .semibold : .regular)
                }
                if hasEvents {
                    Circle()
                        .fill(isSelected ? .white : Color.accentColor)
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
                        .font(appFont(17))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    if !event.isAllDay {
                        Text("\(event.startDate, format: .dateTime.hour().minute()) – \(event.endDate, format: .dateTime.hour().minute())")
                            .font(appFont(11))
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text("All day")
                            .font(appFont(11))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
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
                    .font(appFont(12))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !event.isAllDay {
                    Text("\(event.startDate, format: .dateTime.hour().minute())")
                        .font(appFont(11))
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

// Pushed DSKit page to add an Apple Calendar event. Covers every field EventKit
// supports (Invitees + Travel Time are impossible via EventKit, so omitted).
// Uses native date/time pickers; saves straight to Apple Calendar. [#40,#41]
struct AddCalendarEventView: View {
    @Environment(\.dismiss) private var dismiss
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
    }

    init(defaultDate: Date, calendarService: CalendarAdapterService, onSave: @escaping () -> Void) {
        self.defaultDate = defaultDate
        self.calendarService = calendarService
        self.onSave = onSave
        let cal = Calendar.current
        let baseHour = cal.component(.hour, from: Date()) + 1
        var sc = cal.dateComponents([.year, .month, .day], from: defaultDate)
        sc.hour = baseHour; sc.minute = 0
        let s = cal.date(from: sc) ?? defaultDate
        _startDate = State(initialValue: s)
        _endDate = State(initialValue: s.addingTimeInterval(3600))
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SettingsScreen(centered: true, trailing: {
            Button { saveEvent() } label: {
                Text("Add").font(appFont(18))
                    .foregroundStyle(canSave ? .primary : .secondary)
                    .frame(height: 44).padding(.horizontal, 6)
            }.disabled(!canSave)
        }) {
            SettingsSectionLabel(title: "Event")
            AppTextField(text: $title, placeholder: "Title", fontSize: appScaledSize(20))
            AppTextField(text: $location, placeholder: "Location", fontSize: 17)

            SettingsGroup(title: "Time") {
                HStack {
                    DSText("All-day").dsTextStyle(.body); Spacer()
                    Toggle("", isOn: $allDay).labelsHidden().tint(appToggleTint)
                }.frame(height: 34)
                HStack {
                    DSText("Starts").dsTextStyle(.body); Spacer()
                    DatePicker("", selection: $startDate,
                               displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                        .labelsHidden().tint(weekdaySelectedColor)
                        .onChange(of: startDate) { _, new in if endDate <= new { endDate = new.addingTimeInterval(3600) } }
                }.frame(height: 34)
                HStack {
                    DSText("Ends").dsTextStyle(.body); Spacer()
                    DatePicker("", selection: $endDate,
                               displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                        .labelsHidden().tint(weekdaySelectedColor)
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
            }.tint(.primary)
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
            try calendarService.createEvent(spec)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
