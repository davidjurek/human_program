import SwiftUI
import Charts
import SwiftData
import DSKit

// Stats, rebuilt on DSKit. Shows the fully-complete streak and the exercise
// streak (current + longest), and a week-based bar chart of tasks done per day
// (Screen-Time style) with prev/next week navigation. Pushed from the hub.
struct StatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyPage.date, order: .forward) private var allPages: [DailyPage]

    @State private var weekOffset = 0   // 0 = current week, -1 = last week …
    @State private var showWeekPicker = false

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    private var pageByDate: [Date: DailyPage] {
        Dictionary(allPages.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    weekSection                                    // [#36] Tasks Done on top
                    streakRow(title: "Completion Streak", runs: completionRuns)
                    streakRow(title: "Exercise Streak", runs: exerciseRuns)
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showWeekPicker) {
            StatsWeekPicker(date: cal.date(byAdding: .day, value: 3, to: weekStart) ?? today) { setWeek(containing: $0) }
        }
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            Image(systemName: "calendar").font(.system(size: 18, weight: .medium))   // [#35]
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { showWeekPicker = true }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func setWeek(containing date: Date) {
        let base = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let target = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        let weeks = cal.dateComponents([.weekOfYear], from: base, to: target).weekOfYear ?? 0
        weekOffset = min(0, weeks)
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
                NavigationLink {
                    LongestStreakListView(title: title, runs: runs)
                } label: {
                    statCard("Longest", longest?.length ?? 0)
                }.buttonStyle(.plain)
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

    private func runs(qualifies: (Date) -> Bool) -> [StreakRun] {
        let dates = allPages.map { cal.startOfDay(for: $0.date) }.sorted()
        var result: [StreakRun] = []
        var start: Date?
        var last: Date?
        for d in dates where qualifies(d) {
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
        runs { pageByDate[$0]?.dayComplete == true }
    }

    private var exerciseRuns: [StreakRun] {
        runs { d in
            guard let page = pageByDate[d] else { return false }
            return page.tasks.contains { $0.completed && $0.title.lowercased().contains("exercise") }
        }
    }

    // MARK: - Week section

    private var weekStart: Date {
        let base = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: base)!
    }

    private var weekDays: [WeekBar] {
        (0..<7).map { off in
            let day = cal.date(byAdding: .day, value: off, to: weekStart)!
            let page = pageByDate[cal.startOfDay(for: day)]
            let done = page?.tasks.filter { $0.completed }.count ?? 0
            return WeekBar(date: day, count: done, future: day > today)
        }
    }

    private var weekLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let end = cal.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(f.string(from: weekStart)) – \(f.string(from: end))"
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsSectionLabel(title: "Tasks Done")
                Spacer()
                DSText(weekLabel).dsTextStyle(.caption1)
            }

            Chart(weekDays) { bar in
                BarMark(
                    x: .value("Day", bar.shortDay),
                    y: .value("Done", bar.count)
                )
                .foregroundStyle(bar.future ? Color.secondary.opacity(0.25) : weekdaySelectedColor)
                .cornerRadius(4)
                .annotation(position: .top) {
                    if bar.count > 0 {
                        Text("\(bar.count)").font(appFont(11)).foregroundStyle(.secondary)
                    }
                }
            }
            .chartXScale(domain: weekDays.map { $0.shortDay })
            .chartYAxis(.hidden)
            .frame(height: 160)
            .padding(14)
            .popupGlass(cornerRadius: 16)
            // Swipe the whole card: left = newer week (capped at current), right = older. [#38]
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        if v.translation.width < 0 { if weekOffset < 0 { weekOffset += 1 } }
                        else { weekOffset -= 1 }
                    }
            )
        }
    }
}

private struct WeekBar: Identifiable {
    let date: Date
    let count: Int
    let future: Bool
    var id: Date { date }
    var shortDay: String {
        let f = DateFormatter(); f.dateFormat = "EEE"   // Sun…Sat (unique within a week)
        return f.string(from: date)
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
    let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
    return f.string(from: date)
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
                DatePicker("", selection: $selected, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(weekdaySelectedColor)
                    .padding()
                Button {
                    onSelect(selected); dismiss()
                } label: {
                    DSText("Go").dsTextStyle(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 20)
        }
        .presentationDetents([.medium])
    }
}
