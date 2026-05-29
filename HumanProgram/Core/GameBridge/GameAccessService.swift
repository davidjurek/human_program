import Foundation

// The ONLY connection between the planner and the game.
// The game asks this service if it can open today.
// This service NEVER lets the game inspect task tables directly.
public struct GameAccessService: Sendable {

    public init() {}

    /// Returns true if todayPage exists, dayComplete == true, and date matches today.
    public func canAccessGame(
        todayPage: DailyPage?,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let page = todayPage else { return false }
        guard page.dayComplete else { return false }
        let pageDay = calendar.startOfDay(for: page.date)
        let todayDay = calendar.startOfDay(for: today)
        return pageDay == todayDay
    }

    /// Human-readable reason why the game is locked.
    /// For internal logging only — never shown in UI if locked.
    public func lockReason(
        todayPage: DailyPage?,
        today: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let page = todayPage else {
            return "No daily page exists for today."
        }
        let pageDay = calendar.startOfDay(for: page.date)
        let todayDay = calendar.startOfDay(for: today)
        guard pageDay == todayDay else {
            return "Today's page date does not match the current date."
        }
        guard page.dayComplete else {
            return "Today's page is not marked complete."
        }
        return "Access granted."
    }
}
