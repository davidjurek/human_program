import Foundation
import Observation

@Observable
@MainActor
public final class AppState {
    public var selectedTab: AppTab = .today
    public var viewingDate: Date = Calendar.current.startOfDay(for: Date())
    public var isLocked: Bool = false
    public var streakStats: StreakStats = StreakStats(currentStreak: 0, longestStreak: 0, totalCompleteDays: 0, totalTrackedDays: 0)
    public var showProgramDrawer: Bool = false
    public init() {}
}

public enum AppTab: String, CaseIterable {
    case today, backlog, calendar, routines, stats, settings
    public var label: String { rawValue.capitalized }
    public var systemImage: String {
        switch self {
        case .today: return "checkmark.circle"
        case .backlog: return "tray.full"
        case .calendar: return "calendar"
        case .routines: return "repeat"
        case .stats: return "chart.bar"
        case .settings: return "gear"
        }
    }
}
