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
    // `events` indexed for O(1) per-day lookups, rebuilt by indexEvents() whenever
    // `events` changes. eventsByStartDay: bucketed by start-of-day(startDate), sorted by
    // start. allDayByDay: all-day events under EVERY day they overlap, sorted by title.
    @State private var eventsByStartDay: [Date: [EKEvent]] = [:]
    @State private var allDayByDay: [Date: [EKEvent]] = [:]
    @State private var displayedMonthStart: Date = CalendarView.monthStart(for: Date())
    @State private var displayedWeekStart: Date = CalendarView.weekStart(for: Date())
    @State private var selectedEvent: EKEvent? = nil
    @State private var showEventDetail = false
    @State private var showAddEvent = false
    @State private var showReconciliation = false
    @State private var syncDiffCount = 0
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
        UserDefaults.standard.stringArray(forKey: DefaultsKey.selectedCalendarIds) ?? []
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
        .navigationDestination(isPresented: $showReconciliation) {
            CalendarReconciliationView()
        }
        .onChange(of: showReconciliation) { _, shown in
            if !shown { refreshSyncCount() }   // count may have changed via Restore
        }
        .sheet(item: $editTarget, onDismiss: loadEvents) { target in
            AddCalendarEventView(eventToEdit: target.event, defaultDate: selectedDate,
                                 calendarService: calendarService, onSave: loadEvents)
        }
        // All-day events list popup (Week/Day band tap). [#cal-allday]
        .overlay { allDayListPopup }
        .task { await checkAuthAndLoad(); refreshSyncCount() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            Button { goToday() } label: {
                DSText("Today").dsTextStyle(.subheadline)
                    .frame(height: 44)   // same height as the + button
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
            Button { showAddEvent = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }.buttonStyle(.plain)
        }
        // Centered sync status — blue when in sync, orange when there are differences.
        .overlay { syncCenterButton }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private var syncCenterButton: some View {
        Button { showReconciliation = true } label: {
            Text("Sync: \(syncDiffCount) \(syncDiffCount == 1 ? "difference" : "differences")")
                .font(appFont(19))
                .foregroundStyle(syncDiffCount == 0 ? appOnboardingBlue : Color.orange)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(cornerRadius: 4)
    }

    private func refreshSyncCount() {
        syncDiffCount = CalendarReconciliation.discrepancies(
            calendarService: calendarService,
            stateRepo: CalendarLocalStateRepository(context: context),
            selectedCalendarIds: selectedCalendarIds).count
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
        CalendarMessageState(
            icon: "calendar.badge.exclamationmark",
            title: "Calendar Access Needed",
            message: "Grant access so Human Program can display your calendar events.",
            actionTitle: "Grant Calendar Access",
            action: {
                Task {
                    _ = await calendarService.requestAccess()
                    authStatus = calendarService.authorizationStatus
                    if calendarService.isAuthorized { loadEvents() }
                }
            }
        )
    }

    private var permissionDeniedView: some View {
        CalendarMessageState(
            icon: "calendar.badge.exclamationmark",
            title: "Calendar Access Denied",
            message: "Open Settings to allow calendar access for Human Program.",
            actionTitle: "Open Settings",
            action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
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
            DSText(displayedMonthStart.formatted(.dateTime.month(.wide).year()))
                .dsTextStyle(.title3)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                DSText(day)
                    .dsTextStyle(.caption1)
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
                    let hasEvents = eventsByStartDay[cal.startOfDay(for: day)] != nil
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
                    DSText(String(Calendar.current.component(.day, from: day)))
                        .dsTextStyle(.body, Color.gray.opacity(0.4))
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
                DSText(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .dsTextStyle(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if dayEvents.isEmpty {
                DSText("No events")
                    .dsTextStyle(.subheadline)
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
            DSText("\(displayedWeekStart.formatted(.dateTime.month(.abbreviated).day())) – \(weekEnd.formatted(.dateTime.month(.abbreviated).day().year()))")
                .dsTextStyle(.title3)
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
            DSText(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                .dsTextStyle(.title3)
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

                    // Current time: red pill in the time column + line attached to
                    // its right edge. [#26/#28]
                    if isToday {
                        let topOffset = CGFloat(nowMinute) / 60.0 * hourHeight
                        // spacing 0 + the pill trailing-aligned in the time column so
                        // the line starts exactly at the pill's right edge (attached),
                        // not after the column gap.
                        HStack(spacing: 0) {
                            Text(nowTimeString)
                                .font(appFont(13, bold: true)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                                .fixedSize()
                                // 48 (time-column width) + 5 (the capsule's right
                                // padding) so the pill's DIGITS land on the column's
                                // trailing edge — aligned with the hour labels — while
                                // the capsule's right edge (and the attached line) sit
                                // just past it.
                                .frame(width: 53, alignment: .trailing)
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
        let daysWithEvents = eventsByStartDay.keys.sorted()
        let anchorDay = daysWithEvents.first(where: { $0 >= today }) ?? daysWithEvents.last

        return ScrollViewReader { proxy in
            ScrollView {
                if daysWithEvents.isEmpty {
                    DSText("No events").dsTextStyle(.subheadline)
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
                                    DSText(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                        .dsTextStyle(.headline, cal.isDateInToday(day) ? Color.accentColor : Color.primary)
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
        guard !selectedCalendarIds.isEmpty else { events = []; indexEvents(); return }
        events = calendarService.fetchEvents(from: start, to: end, calendarIds: selectedCalendarIds)
        indexEvents()
    }

    /// Rebuilds the per-day lookup indexes from `events` so the grid/columns do O(1)
    /// lookups instead of re-filtering the whole array per cell/column.
    private func indexEvents() {
        let cal = Calendar.current
        var byStart: [Date: [EKEvent]] = [:]
        var allDay: [Date: [EKEvent]] = [:]
        for event in events {
            byStart[cal.startOfDay(for: event.startDate), default: []].append(event)
            guard event.isAllDay else { continue }
            // An all-day event shows on every day it overlaps, so bucket it under each
            // day in [startDay, endDate) — matching the old overlap filter exactly.
            var day = cal.startOfDay(for: event.startDate)
            while day < event.endDate {
                allDay[day, default: []].append(event)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        eventsByStartDay = byStart.mapValues { $0.sorted { $0.startDate < $1.startDate } }
        allDayByDay = allDay.mapValues { $0.sorted { ($0.title ?? "") < ($1.title ?? "") } }
    }

    private func eventsForDay(_ date: Date) -> [EKEvent] {
        eventsByStartDay[Calendar.current.startOfDay(for: date)] ?? []
    }

    /// Timed (non-all-day) events that START on `date` — the ones placed in the
    /// 00:00–24:00 grid. All-day events are pulled out into the top band. [#cal-allday]
    private func timedEventsForDay(_ date: Date) -> [EKEvent] {
        eventsForDay(date).filter { !$0.isAllDay }
    }

    /// All-day events that OVERLAP `date` (so a multi-day holiday shows a chip on
    /// every day it covers — one chip per day, per spec). [#cal-allday]
    private func allDayEventsForDay(_ date: Date) -> [EKEvent] {
        allDayByDay[Calendar.current.startOfDay(for: date)] ?? []
    }

    // MARK: - All-day band (fixed-height row above the timeline) [#cal-allday]

    /// Fixed band height: ~1.4× the gap between two hour lines.
    private var weekAllDayBandHeight: CGFloat { weekHourHeight * 1.4 }
    private var dayAllDayBandHeight: CGFloat { 56 * 1.4 }

    /// Week all-day band: a fixed-height row with one column per day. ALWAYS shown at
    /// its fixed height (even when empty) so the timeline below doesn't jump as events
    /// come and go. [owner: all-day section stays even if empty]
    private func weekAllDayBand(weekStart displayedWeekStart: Date, colW: CGFloat) -> some View {
        let cal = Calendar.current
        let weekDays = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: displayedWeekStart) }
        return HStack(spacing: 0) {
            Color.clear.frame(width: weekTimeColW, height: weekAllDayBandHeight)
            ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                allDayColumn(allDayEventsForDay(day), height: weekAllDayBandHeight,
                             font: 9, chipHeight: 15) { allDayPopupDate = day }
                    .frame(width: colW)
            }
        }
        .frame(height: weekAllDayBandHeight)
        // Vertical day-column separators, matching the timeline gridlines below. [#cal-allday]
        .overlay(alignment: .topLeading) {
            ForEach(0...7, id: \.self) { i in
                Rectangle().fill(Color.primary.opacity(0.06))
                    .frame(width: 1, height: weekAllDayBandHeight)
                    .offset(x: weekTimeColW + CGFloat(i) * colW)
            }
        }
    }

    /// Day all-day band: a single fixed-height column, aligned to the timeline's event
    /// area. ALWAYS shown at its fixed height (even when empty). [owner]
    private func dayAllDayBand(day: Date) -> some View {
        let items = allDayEventsForDay(day)
        return HStack(spacing: 8) {
            Color.clear.frame(width: 48, height: dayAllDayBandHeight)
            allDayColumn(items, height: dayAllDayBandHeight, font: 12, chipHeight: 22) {
                allDayPopupDate = day
            }
            // Vertical separators framing the all-day cell (parallels the Week band). [#cal-allday]
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
            }
            .padding(.trailing, 16)
        }
        .padding(.horizontal, 4)
        .frame(height: dayAllDayBandHeight)
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
                                    DSText(e.title ?? "").dsTextStyle(.body)
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
