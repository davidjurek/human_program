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
    @Query(sort: \DailyPage.date, order: .forward) private var allPages: [DailyPage]

    @State private var weekOffset = 0   // 0 = current week, -1 = last week …
    // Current-week page index, derived from the page count so the two can't drift. [#175]
    @State private var statsPage = statsWeekPageCount - 1
    @State private var showWeekPicker = false

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    private var pageByDate: [Date: DailyPage] {
        Dictionary(allPages.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let pageIndex = pageByDate          // build the date→page index ONCE per render
        return ZStack {
            SettingsBackground()
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
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .sheet(isPresented: $showWeekPicker) {
            StatsWeekPicker(date: cal.date(byAdding: .day, value: 3, to: weekStart) ?? today) { setWeek(containing: $0) }
        }
    }

    private var topBar: some View {
        HStack {
            BackChevronButton { dismiss() }
            Spacer()
            Button { withAnimation { statsPage = statsPageIndex(forOffset: 0) } } label: {  // jump to current week
                DSText("Today").dsTextStyle(.subheadline)
                    .frame(height: 44)   // full top-bar height, matches the calendar button
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4).padding(.trailing, 18)
            DSImageView(systemName: "calendar", size: 18, tint: .color(.primary))   // [#199]
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
                .onTapGesture { showWeekPicker = true }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private func setWeek(containing date: Date) {
        let base = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let target = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        let weeks = cal.dateComponents([.weekOfYear], from: base, to: target).weekOfYear ?? 0
        statsPage = statsPageIndex(forOffset: min(0, weeks))   // onChange syncs weekOffset [#5]
    }

    // MARK: - Streak cards

    private func streakRow(title: String, runs: [StreakRun]) -> some View {
        let current = runs.first(where: { $0.end == today })
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
                Text("\(value)").font(.system(size: 34, weight: .bold).monospacedDigit())
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
            return WeekBar(date: day, count: done, future: day > today)
        }
    }

    private var weekLabel: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        return AppDateFormat.monthDayRange(weekStart, end)
    }

    // Flip-paging: page index 0…(statsPageCount-1) maps to weekOffset (… -2,-1,0). [#5/#38]
    private let statsPageCount = statsWeekPageCount
    private func offset(forStatsPage i: Int) -> Int { i - (statsPageCount - 1) }
    private func statsPageIndex(forOffset o: Int) -> Int {
        min(max(0, o + (statsPageCount - 1)), statsPageCount - 1)
    }

    private func weekSection(_ pageIndex: [Date: DailyPage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsSectionLabel(title: "Tasks Done")
                Spacer()
                DSText(weekLabel).dsTextStyle(.caption1)
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
                .foregroundStyle(bar.future ? Color.secondary.opacity(0.25) : weekdaySelectedColor)
                .cornerRadius(4)
                .annotation(position: .top) {
                    if bar.count > 0 {
                        Text("\(bar.count)").font(appFont(11)).foregroundStyle(.secondary)
                    }
                }
        }
        .chartXScale(domain: bars.map { $0.shortDay })
        .chartYAxis(.hidden)
        .padding(.vertical, 8)   // [#37] no card around the chart
    }
}

private struct WeekBar: Identifiable {
    let date: Date
    let count: Int
    let future: Bool
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

/// Week jump picker — tapping a date jumps to the week containing it.
private struct StatsWeekPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Date
    let onSelect: (Date) -> Void

    init(date: Date, onSelect: @escaping (Date) -> Void) {
        _selected = State(initialValue: date)
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            VStack(spacing: 16) {
                DSCalendarView(date: $selected)            // [#13/#40] custom DSKit calendar
                    .padding()
                Button {
                    onSelect(selected); dismiss()
                } label: {
                    DSText("Go").dsTextStyle(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                        .a11yTapBorder(Capsule())
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 20)
        }
        .presentationDetents([.medium])
    }
}
