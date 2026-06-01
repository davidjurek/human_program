import Foundation
import Observation

@Observable
@MainActor
public final class AppState {
    public var viewingDate: Date = Calendar.current.startOfDay(for: Date())
    public var streakStats: StreakStats = StreakStats(
        currentStreak: 0,
        longestStreak: 0,
        totalCompleteDays: 0,
        totalTrackedDays: 0
    )
    /// A full-screen interstitial to present at the app root (reset / restore done).
    public var pendingInterstitial: AppInterstitial? = nil
    public init() {}
}

public enum AppInterstitial: Equatable {
    case reset, restored
}
