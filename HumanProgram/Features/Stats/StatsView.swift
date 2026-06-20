import SwiftUI
import Charts
import SwiftData
import DSKit

// Stats, rebuilt on DSKit. Shows the fully-complete streak and the exercise
// streak (current + longest), and a week-based bar chart of tasks done per day
// (Screen-Time style) with prev/next week navigation. Pushed from the hub.

/// Number of week-pages in the Stats flip-pager (≈5 years). The current-week index
/// is `statsWeekPageCount - 1`; both read this one constant so they can't drift. [#175]
private let statsWeekPageCount = 260

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyPage.date, order: .forward) private var allPages: [DailyPage]

    @State private var weekOffset = 0   // 0 = current week, -1 = last week …
    // Current-week page index, derived from the page count so the two can't drift. [#175]
    @State private var statsPage = statsWeekPageCount - 1

    // Chart (default) ⇄ Calendar view, persisted across launches; cleared by a factory
    // reset (it's in DefaultsKey.allKeys, NOT in .hprgm backups), so a fresh install
    // and a reset both land on the chart view.
    @AppStorage(DefaultsKey.statsViewMode) private var viewMode = "chart"   // "chart" | "calendar"
    @State private var monthPage = 0                                        // selected month page (horizontal pager)
    @State private var pickerMonth = Calendar.current.startOfDay(for: Date()) // month/year wheel binding
    @State private var months: [Date] = []                                  // every month-start in range
    @State private var confirmDay: Date? = nil                              // day pending open-confirm
    @State private var openedDay: Date? = nil                               // archived day pushed within Stats
    @State private var showMonthYear = false                                // month/year jump popup
    @State private var showWeekPicker = false                               // chart week scroll-wheel
    @State private var pendingWeekPage = 0                                   // wheel selection, applied on Done

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: today) ?? today }

    /// The live streak run: one ending today, or failing that one ending yesterday — so
    /// an unfinished but still-in-progress today doesn't zero out a streak you kept
    /// through yesterday. It resets only once a day fully passes incomplete. [owner]
    private func currentRun(_ runs: [StreakRun]) -> StreakRun? {
        runs.first { $0.end == today } ?? runs.first { $0.end == yesterday }
    }

    private var pageByDate: [Date: DailyPage] {
        Dictionary(allPages.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let pageIndex = pageByDate          // build the date→page index ONCE per render
        return ZStack {
            SettingsBackground()
            if viewMode == "calendar" {
                calendarContent(pageIndex)
            } else {
                chartContent(pageIndex)
            }
            if let day = confirmDay { confirmPopup(day) }   // open-day confirmation
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        // Tapping a day pushes that archived day as the Today page, but WITHIN Stats —
        // its own back button pops right back here to the calendar.
        .navigationDestination(item: $openedDay) { day in
            TodayView(context: modelContext, initialDate: day)
        }
        .sheet(isPresented: $showWeekPicker) { weekPickerSheet }
    }

    private func chartContent(_ pageIndex: [Date: DailyPage]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                weekSection(pageIndex)                         // [#36] Tasks Done on top
                streakRow(title: "Completion Streak", runs: completionRuns)
                streakRow(title: "Exercise Streak", runs: exerciseRuns)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20).padding(.top, 28)   // [#39] small top gap
        }
    }

    private var topBar: some View {
        HStack {
            BackChevronButton { dismiss() }
            Spacer()
            Button { jumpToCurrent() } label: {  // jump to current week / month
                DSText("Today").dsTextStyle(.subheadline)
                    .frame(height: 44)   // full top-bar height, matches the icon button
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4).padding(.trailing, 18)
            // Toggles the view: calendar icon → calendar view; chart icon → back to chart.
            DSImageView(systemName: viewMode == "calendar" ? "chart.bar" : "calendar",
                        size: 18, tint: .color(.primary))   // [#199]
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) {
                    viewMode = (viewMode == "calendar") ? "chart" : "calendar"
                } }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    /// The top-bar "Today" button: chart view jumps to the current week; calendar view
    /// pages to the current month.
    private func jumpToCurrent() {
        if viewMode == "calendar" { withAnimation { monthPage = monthIndex(of: today) } }
        else { withAnimation { statsPage = statsPageIndex(forOffset: 0) } }
    }

    // MARK: - Streak cards

    private func streakRow(title: String, runs: [StreakRun]) -> some View {
        let current = currentRun(runs)
        let longest = runs.max(by: { $0.length < $1.length })
        return VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: title)
            HStack(spacing: 16) {
                NavigationLink {
                    CurrentStreakDetailView(title: title, run: current)
                } label: {
                    statCard("Current", current?.length ?? 0)
                }.buttonStyle(.plain)
                .a11yTapBorder(RoundedRectangle(cornerRadius: 16))
                NavigationLink {
                    LongestStreakListView(title: title, runs: runs)
                } label: {
                    statCard("Longest", longest?.length ?? 0)
                }.buttonStyle(.plain)
                .a11yTapBorder(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func statCard(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DSText(label).dsTextStyle(.caption1)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(value)").font(appFont(34, bold: true).monospacedDigit())
                    .foregroundStyle(.primary)
                DSText(value == 1 ? "day" : "days").dsTextStyle(.caption1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popupGlass(cornerRadius: 16)
    }

    // MARK: - Streak runs (consecutive qualifying days, with date ranges)

    private func runs(qualifies: (DailyPage) -> Bool) -> [StreakRun] {
        // allPages is already ascending by date (@Query sort), so iterate it directly —
        // no date→page dictionary and no re-sort needed.
        var result: [StreakRun] = []
        var start: Date?
        var last: Date?
        for page in allPages where qualifies(page) {
            let d = cal.startOfDay(for: page.date)
            if let l = last, cal.date(byAdding: .day, value: 1, to: l) == d {
                last = d
            } else {
                if let s = start, let e = last { result.append(StreakRun(start: s, end: e)) }
                start = d; last = d
            }
        }
        if let s = start, let e = last { result.append(StreakRun(start: s, end: e)) }
        return result
    }

    private var completionRuns: [StreakRun] {
        runs { $0.dayComplete }
    }

    private var exerciseRuns: [StreakRun] {
        // The qualifier lives on the model (`DailyPage.hadCompletedExercise`) so the
        // signal is named + documented in one place instead of an inline title scan.
        // (There is deliberately NO structural exercise source — exercise routines
        // never become page-tasks — so a user-named completed task is the only
        // signal a day "had exercise".) [#52]
        runs { $0.hadCompletedExercise }
    }

    // MARK: - Week section

    private func weekStart(offset: Int) -> Date {
        let base = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return cal.date(byAdding: .weekOfYear, value: offset, to: base)!
    }
    private var weekStart: Date { weekStart(offset: weekOffset) }

    private func weekDays(offset: Int, pageIndex: [Date: DailyPage]) -> [WeekBar] {
        let ws = weekStart(offset: offset)
        return (0..<7).map { off in
            let day = cal.date(byAdding: .day, value: off, to: ws)!
            let page = pageIndex[cal.startOfDay(for: day)]
            let done = page?.tasks.filter { $0.completed }.count ?? 0
            return WeekBar(date: day, count: done, future: day > today,
                           complete: page?.dayComplete ?? false)
        }
    }

    /// Week range in the user's chosen date format, with year (e.g. "Jun 7, 2026 –
    /// Jun 13, 2026" or "06/07/2026 – 06/13/2026"). Used for both the header label and
    /// the scroll-wheel rows.
    private func weekRangeLabel(forStatsPage i: Int) -> String {
        let ws = weekStart(offset: offset(forStatsPage: i))
        let end = cal.date(byAdding: .day, value: 6, to: ws) ?? ws
        return "\(AppDateFormat.userPreferred(ws)) – \(AppDateFormat.userPreferred(end))"
    }
    private var weekLabel: String { weekRangeLabel(forStatsPage: statsPage) }

    // Flip-paging: page index 0…(statsPageCount-1) maps to weekOffset (… -2,-1,0). [#5/#38]
    private let statsPageCount = statsWeekPageCount
    private func offset(forStatsPage i: Int) -> Int { i - (statsPageCount - 1) }
    private func statsPageIndex(forOffset o: Int) -> Int {
        min(max(0, o + (statsPageCount - 1)), statsPageCount - 1)
    }

    /// Page indices for the scroll-wheel: the floor week (earliest reachable / data) up
    /// to the current week. Floor = min(install, earliest page) via `navFloor`.
    private var weekPageRange: [Int] {
        let floorWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: navFloor)) ?? navFloor
        let currentWeek = weekStart(offset: 0)
        let back = min(0, cal.dateComponents([.weekOfYear], from: currentWeek, to: floorWeek).weekOfYear ?? 0)
        return Array(statsPageIndex(forOffset: back)...(statsPageCount - 1))
    }

    /// Bottom scroll-wheel sheet listing every week from the floor to the current week;
    /// selecting one navigates the chart (it's bound straight to `statsPage`).
    private var weekPickerSheet: some View {
        ZStack {
            SettingsBackground().ignoresSafeArea()
            VStack(spacing: 12) {
                Picker("", selection: $pendingWeekPage) {
                    ForEach(weekPageRange, id: \.self) { i in
                        Text(weekRangeLabel(forStatsPage: i)).font(appFont(18)).tag(i)
                    }
                }.pickerStyle(.wheel).frame(height: 160)
                Spacer(minLength: 0)
                // Navigate only on Go (bottom center). Spinning then tapping out leaves
                // the chart where it was.
                Button { statsPage = pendingWeekPage; showWeekPicker = false } label: {
                    DSText("Go").dsTextStyle(.headline)
                        .padding(.horizontal, 40).padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .contentShape(Capsule()).a11yTapBorder(Capsule())
                }.buttonStyle(.plain)
            }
            .padding(20)
        }
        .presentationDetents([.height(300)])
        .onAppear { pendingWeekPage = statsPage }
    }

    private func weekSection(_ pageIndex: [Date: DailyPage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsSectionLabel(title: "Tasks Done")
                Spacer(minLength: 8)
                // Tap → bottom scroll-wheel to jump to another week.
                Button { showWeekPicker = true } label: {
                    Text(weekLabel)
                        .font(appFont(15, bold: true)).foregroundStyle(Color.blue).underline()
                        .lineLimit(1).contentShape(Rectangle())
                }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
            }

            // Finger-tracked flip between weeks (Photos-style paging). [#5/#38]
            TabView(selection: $statsPage) {
                ForEach(0..<statsPageCount, id: \.self) { i in
                    weekChart(offset: offset(forStatsPage: i), pageIndex: pageIndex).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 176)
            .onChange(of: statsPage) { _, i in weekOffset = offset(forStatsPage: i) }
        }
    }

    private func weekChart(offset: Int, pageIndex: [Date: DailyPage]) -> some View {
        let bars = weekDays(offset: offset, pageIndex: pageIndex)
        return Chart(bars) { bar in
            BarMark(x: .value("Day", bar.shortDay), y: .value("Done", bar.count))
                // Green when the day is fully complete, blue when not (future days faded).
                .foregroundStyle(bar.future ? Color.secondary.opacity(0.25)
                                 : (bar.complete ? weekdayCompleteColor : weekdaySelectedColor))
                .cornerRadius(4)
                .annotation(position: .top) {
                    if bar.count > 0 {
                        Text("\(bar.count)").font(appFont(11)).foregroundStyle(.secondary)
                    }
                }
        }
        .chartXScale(domain: bars.map { $0.shortDay })
        .chartYAxis(.hidden)
        // Weekday label (Sun…Sat) + that day's date number underneath, app font. [owner]
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let day = value.as(String.self),
                       let bar = bars.first(where: { $0.shortDay == day }) {
                        VStack(spacing: 1) {
                            Text(day).font(appFont(14))
                            Text("\(cal.component(.day, from: bar.date))")
                                .font(appFont(12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        // Tap a bar → open that day's archived page (past, in-range days only). Reuses
        // the same confirm popup + in-Stats Today push as the calendar. [owner]
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = value.location.x - geo[plotFrame].origin.x
                        guard let day: String = proxy.value(atX: x),
                              let bar = bars.first(where: { $0.shortDay == day }) else { return }
                        let d = cal.startOfDay(for: bar.date)
                        if d >= navFloor && d < today { confirmDay = d }
                    })
            }
        }
        .padding(.vertical, 8)   // [#37] no card around the chart
    }

    // MARK: - Calendar view (continuous week-snapping scroll; circles on past days)

    private let calCols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// Floor for the CIRCLES: the earliest day with data, or the install date if that's
    /// earlier — i.e. `min(install, earliest page)`, matching the Today screen's floor.
    /// Circles begin at your oldest saved day; days before it (and the future) are blank.
    /// (Relies on stray junk pages having been purged, else circles would reach back to
    /// them — see the one-time cleanup in AppStartup.)
    private var navFloor: Date {
        let install = (UserDefaults.standard.object(forKey: DefaultsKey.installDate) as? Date)
            .map { cal.startOfDay(for: $0) } ?? today
        if let earliest = allPages.first.map({ cal.startOfDay(for: $0.date) }) {
            return min(install, earliest)
        }
        return install
    }

    private var completionCurrent: Int { currentRun(completionRuns)?.length ?? 0 }
    private var exerciseCurrent: Int { currentRun(exerciseRuns)?.length ?? 0 }

    // ── Month-pager range + math ─────────────────────────────────────────────────
    private func monthStart(_ date: Date) -> Date { cal.dateInterval(of: .month, for: date)?.start ?? date }
    /// Every month-start from ~5 years back to ~5 years ahead of today.
    private func buildMonths() -> [Date] {
        let first = monthStart(cal.date(byAdding: .year, value: -5, to: today) ?? today)
        let last = monthStart(cal.date(byAdding: .year, value: 5, to: today) ?? today)
        var out: [Date] = []
        var d = first
        while d <= last {
            out.append(d)
            guard let next = cal.date(byAdding: .month, value: 1, to: d) else { break }
            d = next
        }
        return out
    }
    /// Index of `date`'s month within `months` (fallback: the middle of the range).
    private func monthIndex(of date: Date) -> Int {
        months.firstIndex(of: monthStart(date)) ?? max(0, months.count / 2)
    }
    /// The month the pager is currently showing.
    private var displayedMonth: Date {
        months.indices.contains(monthPage) ? months[monthPage] : monthStart(today)
    }

    private func calendarContent(_ pageIndex: [Date: DailyPage]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current streaks only (no longest), pinned above the calendar — each card
            // taps through to its current-streak detail, like the chart view.
            HStack(spacing: 16) {
                NavigationLink {
                    CurrentStreakDetailView(title: "Completion Streak",
                                            run: currentRun(completionRuns))
                } label: { statCard("Completion", completionCurrent) }
                    .buttonStyle(.plain).a11yTapBorder(RoundedRectangle(cornerRadius: 16))
                NavigationLink {
                    CurrentStreakDetailView(title: "Exercise Streak",
                                            run: currentRun(exerciseRuns))
                } label: { statCard("Exercise", exerciseCurrent) }
                    .buttonStyle(.plain).a11yTapBorder(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.top, 28).padding(.bottom, 88)   // big gap before the calendar
            calHeader
            weekdayHeader.padding(.top, 16)           // doubled title → calendar gap
            monthPager(pageIndex).padding(.top, 14)   // gap between S M T W T F S and week 1
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity, alignment: .top)   // pin to top (calendar is fixed-height)
        .overlay {
            if showMonthYear {
                // Unbounded — jump to any month/year, past or future.
                MonthYearWheelPopup(month: $pickerMonth, minDate: nil, maxDate: nil) {
                    showMonthYear = false
                    withAnimation { monthPage = monthIndex(of: pickerMonth) }
                }
            }
        }
        .onAppear {
            if months.isEmpty {
                months = buildMonths()
                monthPage = monthIndex(of: today)   // start on the current month
            }
        }
    }

    /// Month label (tap → month/year wheel). No ‹ › buttons — you swipe the calendar
    /// left/right to change months. The title's left edge is inset to the first
    /// day-circle's left edge. [#1]
    private var calHeader: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Button {
                    pickerMonth = displayedMonth
                    showMonthYear = true
                } label: {
                    Text(AppDateFormat.monthYear(displayedMonth))
                        .font(appFont(24, bold: true)).foregroundStyle(Color.blue).underline()
                        .frame(height: 36, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
                // Circle centre = colW/2, radius 18 → its left edge = geo.width/14 − 18.
                .padding(.leading, max(0, geo.size.width / 14 - 18))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 36)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: calCols, spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                DSText(Weekday.shortLetters[i]).dsTextStyle(.caption1).frame(maxWidth: .infinity)
            }
        }
    }

    /// Horizontal pager of month grids — swipe left/right to change months, snapping
    /// one month per page. The shown page drives the header month. [#4]
    private func monthPager(_ pageIndex: [Date: DailyPage]) -> some View {
        // 6 rows of 44 + 5 gaps of 6 = a fixed-height month grid (no jump between
        // 5- and 6-week months).
        let rowH: CGFloat = 44, gap: CGFloat = 6
        return TabView(selection: $monthPage) {
            ForEach(months.indices, id: \.self) { i in
                monthGrid(months[i], pageIndex).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: rowH * 6 + gap * 5)
    }

    /// One month's 6-row grid (leading/trailing days outside the month are blank).
    private func monthGrid(_ monthStartDate: Date, _ pageIndex: [Date: DailyPage]) -> some View {
        LazyVGrid(columns: calCols, spacing: 6) {
            ForEach(Array(gridDays(for: monthStartDate).enumerated()), id: \.offset) { _, day in
                if let day { calDayCell(day, pageIndex) } else { Color.clear.frame(height: 44) }
            }
        }
    }

    /// 42-slot grid (leading blanks + the month's days), reusing the shared
    /// `monthGridLayout` so it matches the app's other calendars. [#196]
    private func gridDays(for monthStartDate: Date) -> [Date?] {
        let layout = monthGridLayout(monthStart: monthStartDate, calendar: cal)
        var out: [Date?] = Array(repeating: nil, count: layout.leadingBlanks)
        for d in 0..<layout.dayCount { out.append(cal.date(byAdding: .day, value: d, to: monthStartDate)) }
        while out.count < 42 { out.append(nil) }
        return out
    }

    private func calDayCell(_ day: Date, _ pageIndex: [Date: DailyPage]) -> some View {
        let d = cal.startOfDay(for: day)
        // Only past days at/after the install floor are tappable and get a circle.
        let clickable = d >= navFloor && d < today
        let complete = pageIndex[d]?.dayComplete ?? true   // empty past day counts as done → green
        let isToday = d == today
        // Number is black only for past days that have a saved page; today, empty past
        // days, and the future are grey.
        let black = d < today && pageIndex[d] != nil
        return Button {
            if clickable { confirmDay = d }   // today is never clickable (not a past day)
        } label: {
            ZStack {
                if clickable {
                    Circle().fill(complete ? weekdayCompleteColor : weekdaySelectedColor)
                        .frame(width: 36, height: 36)
                } else if isToday {
                    // Hollow grey ring marks today (not filled, not tappable).
                    Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                }
                Text("\(cal.component(.day, from: day))")
                    .font(appFont(15))
                    .foregroundStyle(black ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!clickable)
        .a11yTapBorder(Rectangle())
    }

    private func confirmPopup(_ day: Date) -> some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { confirmDay = nil }
            VStack(spacing: 20) {
                DSText(AppDateFormat.weekdayMonthDayYear(day)).dsTextStyle(.headline)
                HStack(spacing: 14) {
                    Button { confirmDay = nil } label: {
                        DSText("Back").dsTextStyle(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .contentShape(Capsule()).a11yTapBorder(Capsule())
                    }.buttonStyle(.plain)
                    Button { openDay(day) } label: {
                        DSText("Go").dsTextStyle(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.10), in: Capsule())
                            .contentShape(Capsule()).a11yTapBorder(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(width: 300)
            .popupGlass(cornerRadius: 22)
        }
    }

    /// Push the chosen archived day WITHIN Stats — the same Today page (lock pill,
    /// schedule, tasks), but its back button returns here to the calendar, not the hub.
    private func openDay(_ day: Date) {
        confirmDay = nil
        openedDay = day
    }
}

private struct WeekBar: Identifiable {
    let date: Date
    let count: Int
    let future: Bool
    let complete: Bool
    var id: Date { date }
    var shortDay: String {
        AppDateFormat.weekdayShort(date)   // Sun…Sat (unique within a week)
    }
}

// MARK: - Streak run + detail pages

struct StreakRun: Identifiable {
    let start: Date
    let end: Date
    var id: Date { start }
    var length: Int {
        (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }
}

private func streakDateString(_ date: Date) -> String {
    AppDateFormat.monthDayYear(date)
}

private func streakRangeString(_ run: StreakRun) -> String {
    Calendar.current.isDate(run.start, inSameDayAs: run.end)
        ? streakDateString(run.start)
        : "\(streakDateString(run.start)) – \(streakDateString(run.end))"
}

/// Current-streak detail: the day count + the date range of the ongoing streak.
struct CurrentStreakDetailView: View {
    let title: String
    let run: StreakRun?

    var body: some View {
        SettingsScreen(centered: true) {
            SettingsSectionLabel(title: title)
            if let run {
                DSText("\(run.length) \(run.length == 1 ? "day" : "days")").dsTextStyle(.title2)
                DSText(streakRangeString(run)).dsTextStyle(.body)
            } else {
                DSText("0 days").dsTextStyle(.title2)
            }
        }
    }
}

/// Longest-streak detail: every streak, longest first, with its date range.
struct LongestStreakListView: View {
    let title: String
    let runs: [StreakRun]

    var body: some View {
        SettingsScreen(centered: true) {
            SettingsSectionLabel(title: title)
            ForEach(runs.sorted { $0.length > $1.length }) { run in
                HStack {
                    DSText("\(run.length) \(run.length == 1 ? "day" : "days")").dsTextStyle(.body)
                    Spacer(minLength: 8)
                    DSText(streakRangeString(run)).dsTextStyle(.subheadline)
                }
                .frame(minHeight: 34)
            }
        }
    }
}

