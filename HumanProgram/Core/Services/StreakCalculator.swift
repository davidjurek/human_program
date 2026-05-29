import Foundation

public struct DailyCompletionSnapshot: Sendable {
    public let date: Date
    public let dayComplete: Bool

    public init(date: Date, dayComplete: Bool) {
        self.date = date
        self.dayComplete = dayComplete
    }
}

public struct StreakStats: Sendable {
    public let currentStreak: Int
    public let longestStreak: Int
    public let totalCompleteDays: Int
    public let totalTrackedDays: Int

    public init(
        currentStreak: Int,
        longestStreak: Int,
        totalCompleteDays: Int,
        totalTrackedDays: Int
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalCompleteDays = totalCompleteDays
        self.totalTrackedDays = totalTrackedDays
    }
}

// Pure service — no SwiftData.
public struct StreakCalculator: Sendable {

    public init() {}

    // today: the current date (start of day)
    // snapshots: all DailyPage records (may include future pages; this service ignores them)
    //
    // currentStreak: count backward from today while dayComplete==true.
    //   If today's page doesn't exist or isn't complete, currentStreak=0.
    //   Each consecutive complete day adds 1.
    //
    // longestStreak: longest consecutive run of complete days up to and including today.
    //
    // totalCompleteDays: count of days where dayComplete==true (up to today).
    // totalTrackedDays: count of all pages with date <= today.
    public func calculate(
        snapshots: [DailyCompletionSnapshot],
        today: Date,
        calendar: Calendar = .current
    ) -> StreakStats {
        let todayStart = calendar.startOfDay(for: today)

        // Build a lookup dictionary: normalized date -> dayComplete
        // Only include pages with date <= today
        var completionByDay: [Date: Bool] = [:]
        for snapshot in snapshots {
            let dayStart = calendar.startOfDay(for: snapshot.date)
            if dayStart <= todayStart {
                // If multiple snapshots for the same day exist, last write wins (shouldn't happen)
                completionByDay[dayStart] = snapshot.dayComplete
            }
        }

        let totalTrackedDays = completionByDay.count
        let totalCompleteDays = completionByDay.values.filter { $0 }.count

        // Sort all tracked dates ascending for longest-streak calculation
        let sortedDates = completionByDay.keys.sorted()

        // Calculate current streak: walk backward from today
        var currentStreak = 0
        var cursor = todayStart
        while true {
            if let complete = completionByDay[cursor], complete {
                currentStreak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                    break
                }
                cursor = previousDay
            } else {
                break
            }
        }

        // Calculate longest streak: iterate sorted dates, detect consecutive complete runs
        var longestStreak = 0
        var runLength = 0
        var previousDate: Date? = nil

        for date in sortedDates {
            let isComplete = completionByDay[date] ?? false

            if isComplete {
                // Check if this day is consecutive with the previous tracked complete day
                var isConsecutive = false
                if let prev = previousDate {
                    if let expectedNext = calendar.date(byAdding: .day, value: 1, to: prev),
                       calendar.startOfDay(for: expectedNext) == date {
                        isConsecutive = true
                    }
                }

                if isConsecutive {
                    runLength += 1
                } else {
                    runLength = 1
                }

                if runLength > longestStreak {
                    longestStreak = runLength
                }
                previousDate = date
            } else {
                // Break in the run — reset tracking for next potential run
                runLength = 0
                previousDate = nil
            }
        }

        return StreakStats(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalCompleteDays: totalCompleteDays,
            totalTrackedDays: totalTrackedDays
        )
    }
}
