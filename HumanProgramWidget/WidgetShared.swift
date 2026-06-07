import Foundation

// Shared by BOTH the app and the widget extension (added to both targets in
// project.yml). The app OWNS the SwiftData store; rather than let the widget open the
// same store (migration + cross-process locking risk), the app publishes this tiny
// summary of TODAY to the App Group whenever it changes, and the widget just reads it.

/// Lightweight snapshot of today the widget renders from.
struct WidgetSnapshot: Codable {
    var dayStart: Date            // the day this snapshot represents
    var completed: Int            // completed task count
    var total: Int                // total task count
    var isComplete: Bool          // today's dayComplete (an empty today counts as complete)
    var outstandingTitles: [String]   // incomplete task titles, in display order

    static let empty = WidgetSnapshot(dayStart: .distantPast, completed: 0, total: 0,
                                      isComplete: true, outstandingTitles: [])
}

enum WidgetShared {
    /// App Group shared between the app and the widget extension. Must match the
    /// `com.apple.security.application-groups` entry in both targets' entitlements.
    static let appGroupId = "group.app.humanprogram"
    static let snapshotKey = "widget.todaySnapshot"
    /// The deep link a widget tap opens; the app routes it to the Today screen.
    static let todayURL = URL(string: "humanprogram://today")!

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupId) }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
