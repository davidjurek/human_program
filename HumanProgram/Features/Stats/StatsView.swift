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
                    streakRow(title: "Completion Streak",
                              current: appState.streakStats.currentStreak,
                              longest: appState.streakStats.longestStreak)
                    streakRow(title: "Exercise Streak",
                              current: exerciseStreak.current,
                              longest: exerciseStreak.longest)
                    weekSection
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    // MARK: - Streak cards

    private func streakRow(title: String, current: Int, longest: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: title)
            HStack(spacing: 16) {
                statCard("Current", current)
                statCard("Longest", longest)
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
                Button { weekOffset -= 1 } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                }.buttonStyle(.plain)
                DSText(weekLabel).dsTextStyle(.caption1)
                Button { if weekOffset < 0 { weekOffset += 1 } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(weekOffset < 0 ? .primary : .secondary)
                }.buttonStyle(.plain).disabled(weekOffset >= 0)
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
        }
    }
}

// MARK: - Exercise streak

private extension StatsView {
    var exerciseStreak: (current: Int, longest: Int) {
        func qualifies(_ page: DailyPage?) -> Bool {
            guard let page else { return false }
            return page.tasks.contains { $0.completed && $0.title.lowercased().contains("exercise") }
        }
        var current = 0
        var d = today
        while qualifies(pageByDate[d]) {
            current += 1
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        let dates = allPages.map { cal.startOfDay(for: $0.date) }.sorted()
        var longest = 0, run = 0
        var prev: Date?
        for date in dates {
            if qualifies(pageByDate[date]) {
                if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == date { run += 1 } else { run = 1 }
                longest = max(longest, run)
            } else {
                run = 0
            }
            prev = date
        }
        return (current, max(longest, current))
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
