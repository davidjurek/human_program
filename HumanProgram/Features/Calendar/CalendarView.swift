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

/// Identifiable wrapper so an EKEvent can drive a `.sheet(item:)` for editing.
private struct CalendarEditTarget: Identifiable {
    let event: EKEvent
    var id: String { event.eventIdentifier ?? UUID().uuidString }
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
    // Edit flow: tapping "Edit" in the detail sheet dismisses it, then (after the
    // dismiss completes) presents the editor pre-filled with this event.
    @State private var pendingEditEvent: EKEvent?
    @State private var editTarget: CalendarEditTarget?
    @State private var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var listScrollTick = 0   // bump to scroll the List back to today [#list]
    // Finger-tracked flip paging (Photos-style) for Month/Week/Day. [#5]
    private let monthBase = CalendarView.monthStart(for: Date())
    private let weekBase = CalendarView.weekStart(for: Date())
    private let dayBase = Calendar.current.startOfDay(for: Date())
    private let pageMid = 120
    private var pageCount: Int { 240 }
    @State private var monthPage = 120
    @State private var weekPage = 120
    @State private var dayPage = 120
    // The day whose all-day list popup is open (nil = closed). [#cal-allday]
    @State private var allDayPopupDate: Date?

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
        .enableSwipeBack()
        .sheet(isPresented: $showEventDetail, onDismiss: {
            loadEvents()
            // If the user tapped Edit, present the editor now that the detail
            // sheet has fully dismissed (can't stack two sheet transitions).
            if let ev = pendingEditEvent { pendingEditEvent = nil; editTarget = CalendarEditTarget(event: ev) }
        }) {
            if let event = selectedEvent {
                CalendarEventDetailSheet(event: event, date: selectedDate, context: context,
                                         onEdit: { pendingEditEvent = event; showEventDetail = false })
            }
        }
        .navigationDestination(isPresented: $showAddEvent) {
            AddCalendarEventView(defaultDate: selectedDate, calendarService: calendarService, onSave: loadEvents)
        }
        .sheet(item: $editTarget, onDismiss: loadEvents) { target in
            AddCalendarEventView(eventToEdit: target.event, defaultDate: selectedDate,
                                 calendarService: calendarService, onSave: loadEvents)
        }
        // All-day events list popup (Week/Day band tap). [#cal-allday]
        .overlay { allDayListPopup }
        .task { await checkAuthAndLoad() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            Button { goToday() } label: { DSText("Today").dsTextStyle(.subheadline).contentShape(Rectangle()) }
                .buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
            Button { showAddEvent = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private func goToday() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDate = today
        displayedMonthStart = CalendarView.monthStart(for: today)
        displayedWeekStart = CalendarView.weekStart(for: today)
        loadEvents()
        listScrollTick += 1   // scroll the List agenda back to today [#list]
        withAnimation { monthPage = pageMid; weekPage = pageMid; dayPage = pageMid }   // flip back to today [#5]
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
        .onAppear {
            // Apply the app font to the native segmented control. [#24]
            let attrs: [NSAttributedString.Key: Any] = [.font: appUIFont(15)]
            UISegmentedControl.appearance().setTitleTextAttributes(attrs, for: .normal)
            UISegmentedControl.appearance().setTitleTextAttributes(attrs, for: .selected)
        }
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
            // Finger-tracked flip between months (Photos-style paging). [#5]
            TabView(selection: $monthPage) {
                ForEach(0..<pageCount, id: \.self) { i in
                    monthGrid(for: monthStart(forPage: i)).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 290)
            .onChange(of: monthPage) { _, i in
                displayedMonthStart = monthStart(forPage: i); loadEvents()
            }
            Color.clear.frame(height: 16)              // [#29] small gap below grid
            dayEventsListBelow
                .frame(maxHeight: .infinity, alignment: .top)   // [#3]
        }
    }

    private func monthStart(forPage i: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: i - pageMid, to: monthBase) ?? monthBase
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

    private func monthGrid(for monthStart: Date) -> some View {
        let cal = Calendar.current
        let days = daysInMonthGrid(for: monthStart)
        let today = cal.startOfDay(for: Date())
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(days, id: \.self) { day in
                if cal.component(.month, from: day) == cal.component(.month, from: monthStart) {
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
                        }
                    }
                }
            }
        }
    }

    // MARK: - Week View

    private var weekView: some View {
        // Finger-tracked flip between weeks (Photos-style paging). One outer reader
        // for the column width (same across pages). [#5]
        GeometryReader { geo in
            let colW = (geo.size.width - weekTimeColW) / 7
            TabView(selection: $weekPage) {
                ForEach(0..<pageCount, id: \.self) { i in
                    let ws = weekStart(forPage: i)
                    VStack(spacing: 0) {
                        weekNavHeader(weekStart: ws)
                        weekDayHeaderRow(weekStart: ws)
                        weekAllDayBand(weekStart: ws, colW: colW)
                        Divider()
                        weekTimeline(weekStart: ws, colW: colW).frame(maxHeight: .infinity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: weekPage) { _, i in
                displayedWeekStart = weekStart(forPage: i); loadEvents()
            }
        }
    }

    private func weekStart(forPage i: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: (i - pageMid) * 7, to: weekBase) ?? weekBase
    }

    private func weekNavHeader(weekStart displayedWeekStart: Date) -> some View {
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
    private func weekDayHeaderRow(weekStart displayedWeekStart: Date) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        let abbrevs = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 0) {
            Color.clear.frame(width: weekTimeColW, height: 1)
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                let isToday = cal.isDate(day, inSameDayAs: today)
                VStack(spacing: 2) {
                    Text(abbrevs[idx]).font(appFont(11))
                        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                    // Today's date is circled (Google/month-view style). [#2]
                    Text("\(cal.component(.day, from: day))").font(appFont(13, bold: isToday))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isToday ? Color.accentColor : Color.clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private let weekTimeColW: CGFloat = 48   // wide enough for 00:00 [#23/#25]
    private let weekHourHeight: CGFloat = 44

    // 7-day time grid: left time column, 24 hour lines, red now-bar, events placed
    // in their day column by time. [#44]
    private func weekTimeline(weekStart displayedWeekStart: Date, colW: CGFloat) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        let nowMin = minuteOfDay(Date())
        let totalH = weekHourHeight * 24

        return ScrollView {
                ZStack(alignment: .topLeading) {
                    // Vertical day-column gridlines (Google-style). [#2]
                    ForEach(0...7, id: \.self) { i in
                        Rectangle().fill(Color.primary.opacity(0.06))
                            .frame(width: 1, height: totalH)
                            .offset(x: weekTimeColW + CGFloat(i) * colW)
                    }
                    // Hour lines + labels.
                    ForEach(0..<24, id: \.self) { hour in
                        let y = CGFloat(hour) * weekHourHeight
                        Rectangle().fill(Color.primary.opacity(0.08))
                            .frame(width: colW * 7, height: 1).offset(x: weekTimeColW, y: y)
                        Text(hourLabel(hour)).font(appFont(13)).foregroundStyle(.secondary)   // [#28]
                            .fixedSize()
                            .frame(width: weekTimeColW - 4, alignment: .trailing)
                            .offset(x: 0, y: max(0, y - 7))
                    }
                    // Timed events per day column (all-day events live in the band). [#cal-allday]
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                        ForEach(timedEventsForDay(day), id: \.eventIdentifier) { event in
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
                            .a11yTapBorder(RoundedRectangle(cornerRadius: 3))
                            .offset(x: weekTimeColW + CGFloat(idx) * colW + 1,
                                    y: CGFloat(s) / 60 * weekHourHeight)
                        }
                    }
                    // Red now-bar, if this week contains today: pill in the time
                    // column + line that STOPS at the grid's right edge. [#25/#27]
                    if weekDays.contains(where: { cal.isDate($0, inSameDayAs: today) }) {
                        let nowY = CGFloat(nowMin) / 60 * weekHourHeight
                        Rectangle().fill(Color.red).frame(width: colW * 7, height: 1)
                            .offset(x: weekTimeColW, y: nowY)
                        Text(nowTimeString)
                            .font(appFont(13, bold: true)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .fixedSize()
                            .frame(width: weekTimeColW, alignment: .center)   // centered in time column [#26]
                            .offset(x: 0, y: nowY - 11)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: totalH, alignment: .topLeading)
        }
    }

    // MARK: - Day View

    private var dayView: some View {
        // Finger-tracked flip between days (Photos-style paging). [#5]
        TabView(selection: $dayPage) {
            ForEach(0..<pageCount, id: \.self) { i in
                let d = dayStart(forPage: i)
                VStack(spacing: 0) {
                    dayNavHeader(day: d)
                    dayAllDayBand(day: d)
                    Divider()
                    dayTimeline(day: d)
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: dayPage) { _, i in
            selectedDate = dayStart(forPage: i); loadEvents()
        }
    }

    private func dayStart(forPage i: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: i - pageMid, to: dayBase) ?? dayBase
    }

    private func dayNavHeader(day selectedDate: Date) -> some View {
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

    private func dayTimeline(day selectedDate: Date) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let isToday = cal.isDate(selectedDate, inSameDayAs: today)
        let nowMinute: Int = {
            let comps = cal.dateComponents([.hour, .minute], from: Date())
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }()
        let dayEvents = timedEventsForDay(selectedDate).sorted { $0.startDate < $1.startDate }
        let hourHeight: CGFloat = 56

        return ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour grid: time label + full-width horizontal line per hour. [#43]
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 8) {
                                Text(hourLabel(hour))
                                    .font(appFont(13))                        // [#28]
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 48, alignment: .trailing)
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
                        .a11yTapBorder(RoundedRectangle(cornerRadius: 4))
                        .offset(x: 56, y: topOffset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 16)
                    }

                    // Current time: red pill centered in the time column + line
                    // attached to it. [#26/#28]
                    if isToday {
                        let topOffset = CGFloat(nowMinute) / 60.0 * hourHeight
                        HStack(spacing: 8) {
                            Text(nowTimeString)
                                .font(appFont(13, bold: true)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                                .fixedSize()
                                .frame(width: 48, alignment: .center)
                            Rectangle().fill(Color.red).frame(height: 1)
                        }
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity)
                        .offset(y: topOffset - 11)
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
        // Every day in the loaded ±2yr window that has events, sorted. Today (or
        // the next day with events) is the scroll anchor. [#list]
        let daysWithEvents = Set(events.map { cal.startOfDay(for: $0.startDate) }).sorted()
        let anchorDay = daysWithEvents.first(where: { $0 >= today }) ?? daysWithEvents.last

        return ScrollViewReader { proxy in
            ScrollView {
                if daysWithEvents.isEmpty {
                    Text("No events").font(appFont(14)).foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
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
                                        .foregroundStyle(cal.isDateInToday(day) ? Color.accentColor : Color.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.clear)
                            }
                            .id(day)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .onAppear { if let a = anchorDay { proxy.scrollTo(a, anchor: .top) } }
            .onChange(of: listScrollTick) { _, _ in
                if let a = anchorDay { withAnimation { proxy.scrollTo(a, anchor: .top) } }
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
            // Wide window so the agenda scrolls across years (today centred). [#list]
            let today = cal.startOfDay(for: Date())
            start = cal.date(byAdding: .year, value: -2, to: today) ?? today
            end = cal.date(byAdding: .year, value: 2, to: today) ?? today
        }

        // Only sync events from calendars the user checked in Settings → Calendar.
        // None checked → show nothing (an empty list means "all" to fetchEvents, so
        // we must guard here, exactly like Today does).
        guard !selectedCalendarIds.isEmpty else { events = []; return }
        events = calendarService.fetchEvents(from: start, to: end, calendarIds: selectedCalendarIds)
    }

    private func eventsForDay(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Timed (non-all-day) events that START on `date` — the ones placed in the
    /// 00:00–24:00 grid. All-day events are pulled out into the top band. [#cal-allday]
    private func timedEventsForDay(_ date: Date) -> [EKEvent] {
        eventsForDay(date).filter { !$0.isAllDay }
    }

    /// All-day events that OVERLAP `date` (so a multi-day holiday shows a chip on
    /// every day it covers — one chip per day, per spec). [#cal-allday]
    private func allDayEventsForDay(_ date: Date) -> [EKEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events
            .filter { $0.isAllDay && $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    // MARK: - All-day band (fixed-height row above the timeline) [#cal-allday]

    /// Fixed band height: ~1.4× the gap between two hour lines.
    private var weekAllDayBandHeight: CGFloat { weekHourHeight * 1.4 }
    private var dayAllDayBandHeight: CGFloat { 56 * 1.4 }

    /// Week all-day band: a fixed-height row with one column per day. Shown only
    /// when some day in the week has an all-day event; size never grows with count.
    @ViewBuilder
    private func weekAllDayBand(weekStart displayedWeekStart: Date, colW: CGFloat) -> some View {
        let cal = Calendar.current
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        if weekDays.contains(where: { !allDayEventsForDay($0).isEmpty }) {
            HStack(spacing: 0) {
                Color.clear.frame(width: weekTimeColW, height: weekAllDayBandHeight)
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    allDayColumn(allDayEventsForDay(day), height: weekAllDayBandHeight,
                                 font: 9, chipHeight: 15) { allDayPopupDate = day }
                        .frame(width: colW)
                }
            }
            .frame(height: weekAllDayBandHeight)
        }
    }

    /// Day all-day band: a single fixed-height column, aligned to the timeline's
    /// event area (gutter + trailing inset). Shown only when the day has all-day events.
    @ViewBuilder
    private func dayAllDayBand(day: Date) -> some View {
        let items = allDayEventsForDay(day)
        if !items.isEmpty {
            HStack(spacing: 8) {
                Color.clear.frame(width: 48, height: dayAllDayBandHeight)
                allDayColumn(items, height: dayAllDayBandHeight, font: 12, chipHeight: 22) {
                    allDayPopupDate = day
                }
                .padding(.trailing, 16)
            }
            .padding(.horizontal, 4)
        }
    }

    /// One day's stacked all-day chips (max 3), with a "+" badge at the bottom-right
    /// when there are more. Tapping the column opens the full scrollable list popup.
    private func allDayColumn(_ events: [EKEvent], height: CGFloat, font: CGFloat,
                              chipHeight: CGFloat, onTap: @escaping () -> Void) -> some View {
        let shown = Array(events.prefix(3))
        let overflow = events.count > 3
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 2) {
                ForEach(shown, id: \.eventIdentifier) { e in
                    Text(e.title ?? "")
                        .font(appFont(font)).foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: chipHeight)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(cgColor: e.calendar.cgColor)))
                }
                Spacer(minLength: 0)
            }
            .padding(2)
            if overflow {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .padding(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .a11yTapBorder(Rectangle())
        .onTapGesture { if !events.isEmpty { onTap() } }
    }

    /// Scrollable popup listing one day's all-day events; tap a row → event detail.
    @ViewBuilder
    private var allDayListPopup: some View {
        if let date = allDayPopupDate {
            let items = allDayEventsForDay(date)
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture { allDayPopupDate = nil }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items, id: \.eventIdentifier) { e in
                            Button {
                                allDayPopupDate = nil
                                selectedDate = date
                                selectedEvent = e
                                showEventDetail = true
                            } label: {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(cgColor: e.calendar.cgColor))
                                        .frame(width: 4, height: 20)
                                    Text(e.title ?? "").font(appFont(16)).foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 44).frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .a11yTapBorder(Rectangle())
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(width: 280).frame(maxHeight: 264)
                .popupGlass(cornerRadius: 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }

    private func daysInMonthGrid(for monthStart: Date) -> [Date] {
        let cal = Calendar.current
        guard let monthRange = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart) // 1=Sun
        let leadingBlanks = firstWeekday - 1

        var days: [Date] = []
        for offset in stride(from: -leadingBlanks, to: monthRange.count + (7 - ((leadingBlanks + monthRange.count) % 7)) % 7, by: 1) {
            if let day = cal.date(byAdding: .day, value: offset, to: monthStart) {
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
        // Week/Day timeline gutter is ALWAYS 24-hour (00:00 … 23:00), matching the
        // Today schedule, regardless of the time-format setting. [#cal-allday]
        String(format: "%02d:00", hour)
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
        .a11yTapBorder(Rectangle())
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
        .a11yTapBorder(Rectangle())
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
