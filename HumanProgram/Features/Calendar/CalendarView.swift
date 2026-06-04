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
        HStack(spacing: 12) {
            BackChevronButton { dismiss() }
            Spacer()
            Button { goToday() } label: {
                DSText("Today").dsTextStyle(.subheadline)
                    .frame(height: 44)   // same height as the + button
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
            Button { showAddEvent = true } label: {
                DSImageView(systemName: "plus", size: 18, tint: .color(.primary))
                    .fontWeight(.medium)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
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
            Text("\(syncDiffCount) \(syncDiffCount <= 1 ? "difference" : "differences")")
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
            // Fixed height = the max 6 rows × 44pt cell height, so the grid (and the
            // day-events header below it) sit at the SAME position whether a month
            // spans 4, 5, or 6 weeks. Pinned tight to 6 rows so there's no slack gap
            // even on a 6-week month. [#29]
            .frame(height: 264)
            .onChange(of: monthPage) { _, i in
                displayedMonthStart = monthStart(forPage: i); loadEvents()
            }
            Color.clear.frame(height: 8)               // [#29] small gap below grid
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
            ForEach(Array(Self.weekdayAbbreviations.enumerated()), id: \.offset) { _, day in
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
        // Pin rows to the top of the fixed-height page so 4-/5-week months don't
        // float their rows down toward the center. [#29]
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dayEventsListBelow: some View {
        let dayEvents = eventsForDay(selectedDate)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSText(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
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
            // Reserve the shared left inset AND right gap so the 7 columns don't
            // stretch to the screen edge — the gutter sits at the left margin and
            // an empty gap is left to the right of Saturday. [owner]
            let colW = (geo.size.width - TimelineMetrics.leadingInset - TimelineMetrics.trailingInset - weekTimeColW) / 7
            TabView(selection: $weekPage) {
                ForEach(0..<pageCount, id: \.self) { i in
                    let ws = weekStart(forPage: i)
                    let days = weekDays(from: ws)
                    VStack(spacing: 0) {
                        weekNavHeader(weekStart: ws)
                        weekDayHeaderRow(weekStart: ws)
                        multiDayAllDayBand(days: days, colW: colW, showVerticals: true)
                        multiDayTimeline(days: days, colW: colW, showVerticals: true)
                            .frame(maxHeight: .infinity)
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
        let weekDays = weekDays(from: displayedWeekStart)
        let abbrevs = Self.weekdayAbbreviations
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
        // Match the timeline's fixed columns: reserve the same left margin AND
        // right gap so the flexible header columns line up with the grid. [owner]
        .padding(.leading, TimelineMetrics.leadingInset)
        .padding(.trailing, TimelineMetrics.trailingInset)
        .padding(.vertical, 4)
    }

    private let weekTimeColW: CGFloat = TimelineMetrics.gutterW   // shared with Today + Day [owner]
    private let weekHourHeight: CGFloat = 44

    // Shared N-day time grid (1 day = Day view, 7 days = Week view). Rendered by the
    // `MultiDayTimeline` view so each Week page / Day page owns its own scroll-offset
    // state. The ONLY differences between Week and Day are `days.count` and
    // `showVerticals` (Day hides the column gridlines) — one change updates both. [#44]
    private func multiDayTimeline(days: [Date], colW: CGFloat, showVerticals: Bool) -> some View {
        MultiDayTimeline(
            days: days, colW: colW, showVerticals: showVerticals,
            hourHeight: weekHourHeight, gutterW: weekTimeColW, bandHeight: weekAllDayBandHeight,
            timedEvents: { timedEventsForDay($0) },
            onTap: { day, event in
                selectedDate = day; selectedEvent = event; showEventDetail = true
            }
        )
    }

    // MARK: - Day View

    private var dayView: some View {
        // Same template as Week, rendered for ONE full-width day: no S M T W header
        // row and no vertical column dividers (showVerticals: false). [owner]
        GeometryReader { geo in
            let colW = geo.size.width - TimelineMetrics.leadingInset - TimelineMetrics.trailingInset - weekTimeColW
            // Finger-tracked flip between days (Photos-style paging). [#5]
            TabView(selection: $dayPage) {
                ForEach(0..<pageCount, id: \.self) { i in
                    let d = dayStart(forPage: i)
                    VStack(spacing: 0) {
                        dayNavHeader(day: d)
                        multiDayAllDayBand(days: [d], colW: colW, showVerticals: false)
                        multiDayTimeline(days: [d], colW: colW, showVerticals: false)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: dayPage) { _, i in
                selectedDate = dayStart(forPage: i); loadEvents()
            }
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

    /// Shared all-day band (1 day = Day view, 7 days = Week view): a fixed-height row
    /// with one column per day. ALWAYS shown at its fixed height (even when empty) so
    /// the timeline below doesn't jump as events come and go. Day view passes
    /// showVerticals=false (no column dividers). [owner: all-day section stays even if empty]
    private func multiDayAllDayBand(days: [Date], colW: CGFloat, showVerticals: Bool) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: weekTimeColW, height: weekAllDayBandHeight)
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                allDayColumn(allDayEventsForDay(day), height: weekAllDayBandHeight,
                             font: 9, chipHeight: 15) { allDayPopupDate = day }
                    .frame(width: colW)
            }
        }
        .frame(height: weekAllDayBandHeight)
        // Vertical day-column separators so the all-day section is divided into the
        // day columns. They line up with the grid's columns below and meet the grid
        // verticals at the 12:00 AM line. No bottom line here — the grid's 12:00 AM
        // line is the section's bottom edge (it moves with the grid). [owner]
        .overlay(alignment: .topLeading) {
            if showVerticals {
                ForEach(0...days.count, id: \.self) { i in
                    Rectangle().fill(Color.primary.opacity(0.06))
                        .frame(width: 1, height: weekAllDayBandHeight)
                        .offset(x: weekTimeColW + CGFloat(i) * colW)
                }
            }
        }
        .padding(.leading, TimelineMetrics.leadingInset)
        // The band has a fixed width; without this the VStack CENTERS it, shifting
        // it ~8pt right of the header/timeline. Pin it leading so it lines up. [owner]
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(e.displayTitle)
                        .font(appFont(font)).foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: chipHeight)
                        .background(RoundedRectangle(cornerRadius: 3).fill(e.displayColor))
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
                                        .fill(e.displayColor)
                                        .frame(width: 4, height: 20)
                                    DSText(e.displayTitle).dsTextStyle(.body)
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
        // Shared layout math (#196); this view fills leading/trailing cells with the
        // real adjacent-month dates by walking day offsets from the month start.
        let layout = monthGridLayout(monthStart: monthStart, calendar: cal)
        let totalCells = layout.leadingBlanks + layout.dayCount + layout.trailingBlanks
        return (0..<totalCells).compactMap { i in
            cal.date(byAdding: .day, value: i - layout.leadingBlanks, to: monthStart)
        }
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        // Week/Day timeline gutter honors the 12h/24h setting, matching Today. [owner]
        clockString(minutesOfDay: hour * 60)
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

    // MARK: - Week math (shared) [#124]

    /// Single-letter weekday headers, Sunday-first (matches the 1=Sun encoding).
    static let weekdayAbbreviations = ["S", "M", "T", "W", "T", "F", "S"]

    /// The 7 consecutive days starting at `weekStart` (Sun…Sat for a normalized start).
    private func weekDays(from weekStart: Date) -> [Date] {
        let cal = Calendar.current
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }
}

// MARK: - Shared multi-day timeline (Calendar Week + Day)

/// One scrollable hour grid: 1 day = Calendar Day view, 7 days = Calendar Week view.
/// Extracted into its own view so each Week page / Day page owns its own scroll state.
/// The 00:00 gutter label rides INSIDE the scroll (so a pull-down carries it down with the
/// grid) and a small top content inset keeps it centred on its line and uncut. The
/// day-column lines extend up past 00:00 and the scroll clip reveals them on a pull so the
/// columns stay connected to the day-header (clip-based — survives the rubber-band bounce,
/// which SwiftUI scroll-offset tracking does not). [owner]
private struct MultiDayTimeline: View {
    let days: [Date]
    let colW: CGFloat
    let showVerticals: Bool
    let hourHeight: CGFloat
    let gutterW: CGFloat
    let bandHeight: CGFloat
    let timedEvents: (Date) -> [EKEvent]
    let onTap: (Date, EKEvent) -> Void

    private func minute(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let nDays = days.count
        let nowMin = minute(Date())
        let totalH = hourHeight * 24
        // How far the day-column lines extend ABOVE 00:00. Generous so they always reach the
        // day-header through the largest rubber-band pull. Kept ≤ totalH so it adds no extra
        // scrollable slack below the grid.
        let aboveExtent: CGFloat = totalH
        // The bottom gutter label is centred on the last line (top = line − 7 via the label's
        // own offset), so its lower half sits below `totalH`. Reserve its half-height + a small
        // margin so it isn't clipped at the content's bottom edge. [owner]
        let bottomLabelPad: CGFloat = 14

        // Split into per-layer @ViewBuilder methods below: the combined ZStack was one
        // expression too large for the Swift type-checker ("unable to type-check in
        // reasonable time"). Each layer now type-checks independently. [owner]
        return ScrollView {
            ZStack(alignment: .topLeading) {
                verticalGridlines(nDays: nDays, totalH: totalH, aboveExtent: aboveExtent)
                hourLinesAndLabels(nDays: nDays)
                allDayDivider(nDays: nDays)
                timedEventsLayer()
                nowBar(cal: cal, today: today, nowMin: nowMin, nDays: nDays)
            }
            // FIXED height (min == max): the day-column lines are `totalH + aboveExtent` tall,
            // and `.offset` is purely visual — it does NOT shrink their layout size — so a plain
            // `minHeight` ZStack grew to ~2× a day, leaving a dead empty scroll zone BELOW the
            // 00:00 row. Pinning the content to one day (+ `bottomLabelPad`) removes that slack so
            // the last row rests at the pane bottom when fully scrolled; the lines still draw their
            // upward extension (it overflows the frame, revealed by the rubber-band pull). The
            // `bottomLabelPad` is just enough room for the bottom (24:00 / 12:00 AM) label — which
            // is centred on the last line and would otherwise be clipped at the content edge — and
            // is far too small to read as scrollable slack. [owner]
            .frame(maxWidth: .infinity, minHeight: totalH + bottomLabelPad, maxHeight: totalH + bottomLabelPad, alignment: .topLeading)
        }
        // Small top inset so the grid rests with 00:00 a few points below the pane edge —
        // enough that the centred 00:00 label clears the clip and isn't cut. The gap it
        // leaves above 00:00 is filled by the day-column line extensions, so it reads as the
        // grid continuing up to the day-header rather than an empty gap.
        .contentMargins(.top, 10, for: .scrollContent)
        .padding(.leading, TimelineMetrics.leadingInset)   // align gutter with Today [owner]
    }

    // Vertical day-column gridlines (Week only; Day passes showVerticals=false). Each line
    // extends UP past 00:00 by `aboveExtent`. The scroll clips it at rest (the extension is
    // hidden above the pane edge / under the day-header); a rubber-band pull slides the
    // extension into the exposed gap so the columns stay connected to the header. The
    // clip-based reveal is the only approach that survives the bounce (SwiftUI scroll-offset
    // tracking does not). [owner]
    @ViewBuilder
    private func verticalGridlines(nDays: Int, totalH: CGFloat, aboveExtent: CGFloat) -> some View {
        if showVerticals {
            ForEach(0...nDays, id: \.self) { i in
                Rectangle().fill(Color.primary.opacity(0.06))
                    .frame(width: 1, height: totalH + aboveExtent)
                    .offset(x: gutterW + CGFloat(i) * colW, y: -aboveExtent)
            }
        }
    }

    // Hour lines + labels (0...24), 00:00 included. The small top content inset (see
    // .contentMargins) keeps the 00:00 label clear of the pane edge so it's centred on its
    // line and never cut.
    @ViewBuilder
    private func hourLinesAndLabels(nDays: Int) -> some View {
        ForEach(0...24, id: \.self) { hour in
            let y = CGFloat(hour) * hourHeight
            // Bottom (end-of-day) row reads "24:00" in 24h mode, "12:00 AM" in 12h. [owner]
            let override: String? = (hour == 24 && TimeFormatSetting.is24Hour) ? "24:00" : nil
            Rectangle().fill(Color.primary.opacity(0.08))
                .frame(width: colW * CGFloat(nDays), height: 1).offset(x: gutterW, y: y)
            TimelineGutterLabel(minutesOfDay: hour * 60, textOverride: override)
                .offset(x: 0, y: y - 7)
        }
    }

    // All-day ↔ timeline divider: rides with the grid on a pull, pins at the pane edge once
    // scrolled. visualEffect reads the live scroll position. [owner]
    private func allDayDivider(nDays: Int) -> some View {
        Rectangle().fill(Color.primary.opacity(0.08))
            .frame(width: colW * CGFloat(nDays), height: 1).offset(x: gutterW)
            .visualEffect { content, proxy in
                content.offset(y: max(0, -proxy.frame(in: .scrollView).minY))
            }
    }

    // Timed events per day column (all-day events live in the band).
    private func timedEventsLayer() -> some View {
        ForEach(Array(days.enumerated()), id: \.offset) { idx, day in
            ForEach(timedEvents(day), id: \.eventIdentifier) { event in
                let s = minute(event.startDate)
                let e = minute(event.endDate)
                let minHeight = hourHeight / 3
                let rawHeight = CGFloat(max(e - s, 20)) / 60 * hourHeight
                let h = max(minHeight, rawHeight)
                Button { onTap(day, event) } label: {
                    Text(event.displayTitle)
                        .font(appFont(9)).foregroundStyle(.white)
                        .lineLimit(2).padding(.horizontal, 3).padding(.vertical, 1)
                        .frame(width: colW - 2, height: h, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 3).fill(event.displayColor))
                }.buttonStyle(.plain)
                .a11yTapBorder(RoundedRectangle(cornerRadius: 3))
                .offset(x: gutterW + CGFloat(idx) * colW + 1, y: CGFloat(s) / 60 * hourHeight)
            }
        }
    }

    // Red now-bar, if the range contains today.
    @ViewBuilder
    private func nowBar(cal: Calendar, today: Date, nowMin: Int, nDays: Int) -> some View {
        if days.contains(where: { cal.isDate($0, inSameDayAs: today) }) {
            let nowY = CGFloat(nowMin) / 60 * hourHeight
            let rightEdge = gutterW + colW * CGFloat(nDays)
            Rectangle().fill(Color.red)
                .frame(width: max(0, rightEdge - TimelineMetrics.pillTrailingEdge), height: 1)
                .offset(x: TimelineMetrics.pillTrailingEdge, y: nowY)
            NowPill(minutesOfDay: nowMin, width: TimelineMetrics.dynamicPillW)
                .frame(width: gutterW, alignment: .center)
                .offset(x: 0, y: nowY - TimelineMetrics.pillH / 2)
        }
    }
}
