import SwiftUI
import Charts
import SwiftData

// MARK: - StatsView

struct StatsView: View {
    @Environment(AppState.self) private var appState

    // Fetch all daily pages, sorted ascending by date
    @Query(sort: \DailyPage.date, order: .forward)
    private var allPages: [DailyPage]

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: Derived data

    private var last7Days: [DayCell] {
        let cal = Calendar.current
        let pageByDate: [Date: DailyPage] = Dictionary(
            uniqueKeysWithValues: allPages.map { (cal.startOfDay(for: $0.date), $0) }
        )
        return (0..<7).reversed().map { offset -> DayCell in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let page = pageByDate[date]
            return DayCell(date: date, page: page)
        }
    }

    private var last30DaysData: [DailyBarDatum] {
        let cal = Calendar.current
        let pageByDate: [Date: DailyPage] = Dictionary(
            uniqueKeysWithValues: allPages.map { (cal.startOfDay(for: $0.date), $0) }
        )
        return (0..<30).reversed().map { offset -> DailyBarDatum in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let page = pageByDate[date]
            return DailyBarDatum(date: date, complete: page?.dayComplete ?? false, hasData: page != nil)
        }
    }

    private var last8WeeksData: [WeeklyBarDatum] {
        let cal = Calendar.current
        var result: [WeeklyBarDatum] = []
        for weekOffset in (0..<8).reversed() {
            let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: today)!
            let weekStartNorm = cal.date(
                from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
            )!
            var completedCount = 0
            var trackedCount = 0
            for dayOffset in 0..<7 {
                let day = cal.date(byAdding: .day, value: dayOffset, to: weekStartNorm)!
                if day > today { break }
                if let page = allPages.first(where: { cal.startOfDay(for: $0.date) == day }) {
                    trackedCount += 1
                    if page.dayComplete { completedCount += 1 }
                }
            }
            result.append(WeeklyBarDatum(weekStart: weekStartNorm, completedDays: completedCount, trackedDays: trackedCount))
        }
        return result
    }

    private var todayPage: DailyPage? {
        allPages.last(where: { Calendar.current.startOfDay(for: $0.date) == today })
    }

    private var completionRate: Double {
        guard appState.streakStats.totalTrackedDays > 0 else { return 0 }
        return Double(appState.streakStats.totalCompleteDays) / Double(appState.streakStats.totalTrackedDays)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 1. Header Cards (2×2 grid)
                    headerCards

                    // 2. 7-Day Strip
                    sevenDayStrip

                    // 3. Completion Rate — Last 30 Days
                    completionRateChart

                    // 4. Weekly Summary
                    weeklySummaryChart

                    // 5. Task Stats for Today
                    todayTaskStats

                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section 1: Header Cards

    private var headerCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCardView(
                    label: "Current Streak",
                    value: "\(appState.streakStats.currentStreak)",
                    unit: "days",
                    color: AppColors.accentGreen
                )
                StatCardView(
                    label: "Longest Streak",
                    value: "\(appState.streakStats.longestStreak)",
                    unit: "days",
                    color: AppColors.accent
                )
            }
            HStack(spacing: 12) {
                StatCardView(
                    label: "Complete Days",
                    value: "\(appState.streakStats.totalCompleteDays)",
                    unit: "days",
                    color: AppColors.accentOrange
                )
                StatCardView(
                    label: "Days Tracked",
                    value: "\(appState.streakStats.totalTrackedDays)",
                    unit: "days",
                    color: AppColors.textSecondary
                )
            }
        }
    }

    // MARK: - Section 2: 7-Day Strip

    private var sevenDayStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderLabel(title: "Last 7 Days")
            HStack(spacing: 0) {
                ForEach(last7Days) { cell in
                    DayCellView(cell: cell)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(AppColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Section 3: Completion Rate Chart (30 days)

    private var completionRateChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderLabel(title: "Completion Rate — Last 30 Days")

            let completedDays = last30DaysData.filter { $0.complete }.count
            let trackedDays = last30DaysData.filter { $0.hasData }.count
            let rateText: String = {
                guard trackedDays > 0 else { return "No data yet" }
                let pct = Int(Double(completedDays) / Double(trackedDays) * 100)
                return "\(completedDays) of \(trackedDays) tracked days complete (\(pct)%)"
            }()

            Text(rateText)
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)

            Chart(last30DaysData) { datum in
                BarMark(
                    x: .value("Date", datum.date, unit: .day),
                    y: .value("Complete", datum.hasData ? 1.0 : 0.0)
                )
                .foregroundStyle(
                    datum.complete
                        ? AppColors.accentGreen
                        : (datum.hasData ? AppColors.accentRed.opacity(0.4) : AppColors.surfaceSunken)
                )
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(AppTypography.timeLabel())
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(AppColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Section 4: Weekly Summary Chart

    private var weeklySummaryChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderLabel(title: "Weekly Completion")
            Text("Complete days per week — last 8 weeks")
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)

            Chart(last8WeeksData) { datum in
                BarMark(
                    x: .value("Week", datum.weekStart, unit: .weekOfYear),
                    y: .value("Days", datum.completedDays)
                )
                .foregroundStyle(AppColors.accent)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 1)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(AppTypography.timeLabel())
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .stride(by: 1)) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(AppTypography.timeLabel())
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(AppColors.separator)
                }
            }
            .chartYScale(domain: 0...7)
            .frame(height: 140)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(AppColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Section 5: Today's Task Stats

    private var todayTaskStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderLabel(title: "Today")
            TodayTaskStatsCard(page: todayPage)
        }
    }
}

// MARK: - Supporting Views

private struct SectionHeaderLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(AppTypography.sectionHeader())
            .foregroundStyle(AppColors.sectionHeader)
            .tracking(0.6)
    }
}

struct StatCardView: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.caption())
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(unit)
                    .font(AppTypography.caption())
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Day Cell (7-day strip)

private struct DayCell: Identifiable {
    let date: Date
    let page: DailyPage?

    var id: Date { date }

    var dayAbbrev: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return String(fmt.string(from: date).prefix(3))
    }

    var dayNumber: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: date)
    }

    var state: CellState {
        guard let page else { return .noData }
        return page.dayComplete ? .complete : .incomplete
    }

    enum CellState {
        case complete, incomplete, noData
    }

    var dotColor: Color {
        switch state {
        case .complete:   return AppColors.accentGreen
        case .incomplete: return AppColors.accentRed
        case .noData:     return AppColors.textTertiary.opacity(0.3)
        }
    }
}

private struct DayCellView: View {
    let cell: DayCell

    private var isToday: Bool {
        Calendar.current.isDateInToday(cell.date)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(cell.dayAbbrev)
                .font(AppTypography.timeLabel())
                .foregroundStyle(isToday ? AppColors.accent : AppColors.textTertiary)
            Text(cell.dayNumber)
                .font(.system(size: 13, weight: isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? AppColors.accent : AppColors.textSecondary)
            Circle()
                .fill(cell.dotColor)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Today Task Stats Card

private struct TodayTaskStatsCard: View {
    let page: DailyPage?

    private var totalTasks: Int { page?.tasks.count ?? 0 }
    private var completedTasks: Int { page?.tasks.filter { $0.completed }.count ?? 0 }

    private var statusText: String {
        guard let page else { return "No page created yet today." }
        guard !page.tasks.isEmpty else { return "No tasks on today's page." }
        if page.dayComplete {
            return "All \(totalTasks) task\(totalTasks == 1 ? "" : "s") complete. Day done."
        }
        return "\(completedTasks) of \(totalTasks) task\(totalTasks == 1 ? "" : "s") complete"
    }

    private var progressFraction: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(AppTypography.bodySmallMedium)
                        .foregroundStyle(AppColors.textPrimary)

                    if totalTasks > 0 {
                        Text("\(Int(progressFraction * 100))% complete")
                            .font(AppTypography.caption())
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Spacer()

                if page?.dayComplete == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(AppColors.accentGreen)
                }
            }

            if totalTasks > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.surfaceSunken)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(page?.dayComplete == true ? AppColors.accentGreen : AppColors.accent)
                            .frame(width: geo.size.width * progressFraction, height: 8)
                            .animation(.easeOut(duration: 0.4), value: progressFraction)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(16)
        .background(AppColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Data Models (local to this file)

private struct DailyBarDatum: Identifiable {
    let date: Date
    let complete: Bool
    let hasData: Bool
    var id: Date { date }
}

private struct WeeklyBarDatum: Identifiable {
    let weekStart: Date
    let completedDays: Int
    let trackedDays: Int
    var id: Date { weekStart }
}
