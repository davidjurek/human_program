import Foundation

// Controls whether the hidden gate (Sudoku puzzle) should be presented.
// The gate is reached by double-tapping the developer name on the About page.
// If today is not complete, the gesture fails quietly (no text, just a subtle haptic).
public struct EasterEggGateService: Sendable {

    public init() {}

    /// Returns true only when todayPage.dayComplete == true.
    /// The gate must not reveal itself or explain why it failed if false.
    public func shouldRevealGate(
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
}
