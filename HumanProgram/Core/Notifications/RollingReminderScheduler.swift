import Foundation
import UserNotifications

// MARK: - RollingReminderScheduler
//
// iOS allows a maximum of ~64 pending local notifications per app.
// Strategy: compute the next N concrete fire times for each enabled reminder
// and schedule them as one-shot UNCalendarNotificationTrigger requests.
// Call reschedule() on app launch and after any reminder change.
//
// Identifier format: "humanprogram.<reminderId>.<index>"
// This lets us cancel all notifications for a single reminder by prefix.

public struct RollingReminderScheduler: Sendable {

    // Maximum fire times to schedule per reminder (keeps total under 64 for ~6 reminders).
    private let maxPerReminder = 20

    // MARK: - Permission

    /// Request notification authorisation. Returns true if granted.
    public func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Reschedule

    /// Remove all pending notifications then schedule all enabled reminders.
    /// Call on app launch and after any reminder change.
    public func reschedule(reminders: [NotificationReminder]) async {
        // Remove everything this app has scheduled so we start clean.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let enabled = reminders.filter { $0.isEnabled }
        for reminder in enabled {
            let requests = buildRequests(for: reminder)
            for request in requests {
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }

    // MARK: - Cancel all

    /// Cancel every pending notification for this app.
    public func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Cancel by reminder ID

    /// Cancel all pending notifications whose identifier starts with the reminder's prefix.
    public func cancel(reminderId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let prefix = "humanprogram.\(reminderId)."
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Build UNNotificationRequests

    private func buildRequests(for reminder: NotificationReminder) -> [UNNotificationRequest] {
        let content = makeContent(for: reminder)
        let fireTimes = computeFireTimes(for: reminder)

        return fireTimes.enumerated().compactMap { index, date in
            guard date > Date() else { return nil }
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = "humanprogram.\(reminder.id).\(index)"
            return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        }
    }

    // MARK: - Content

    private func makeContent(for reminder: NotificationReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.message
        switch reminder.soundMode {
        case .defaultSound, .chimeOnly:
            content.sound = .default
        case .silent:
            content.sound = nil
        }

        // Attach the optional image (saved by ReminderImageStore).
        if let filename = reminder.imageFilename {
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ReminderImages", isDirectory: true)
            let url = dir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path),
               let attachment = try? UNNotificationAttachment(identifier: filename, url: url) {
                content.attachments = [attachment]
            }
        }

        return content
    }

    // MARK: - Fire time computation

    private func computeFireTimes(for reminder: NotificationReminder) -> [Date] {
        switch reminder.recurrenceMode {
        case .daily:
            return dailyFireTimes(reminder: reminder)
        case .weekdays:
            return weekdayFireTimes(reminder: reminder, weekdays: [2, 3, 4, 5, 6]) // Mon–Fri
        case .selectedWeekdays:
            let days = reminder.weekdays.isEmpty ? [2, 3, 4, 5, 6] : reminder.weekdays
            return weekdayFireTimes(reminder: reminder, weekdays: days)
        case .everyNMinutes:
            return everyNMinutesFireTimes(reminder: reminder)
        case .hourlyWindow:
            return hourlyWindowFireTimes(reminder: reminder)
        }
    }

    // Daily: next maxPerReminder days at fireHour:fireMinute
    private func dailyFireTimes(reminder: NotificationReminder) -> [Date] {
        var results: [Date] = []
        let cal = Calendar.current
        let now = Date()
        var candidate = nextOccurrence(
            after: now,
            hour: reminder.fireHour,
            minute: reminder.fireMinute,
            calendar: cal
        )
        while results.count < maxPerReminder {
            results.append(candidate)
            candidate = cal.date(byAdding: .day, value: 1, to: candidate)!
        }
        return results
    }

    // Weekly on specific weekdays (1=Sun…7=Sat) at fireHour:fireMinute
    private func weekdayFireTimes(reminder: NotificationReminder, weekdays: [Int]) -> [Date] {
        guard !weekdays.isEmpty else { return [] }
        var results: [Date] = []
        let cal = Calendar.current
        let now = Date()
        // Walk forward day-by-day collecting matching weekdays
        var dayCursor = cal.startOfDay(for: now)
        while results.count < maxPerReminder {
            let weekday = cal.component(.weekday, from: dayCursor) // 1=Sun…7=Sat
            if weekdays.contains(weekday) {
                if let fireDate = cal.date(
                    bySettingHour: reminder.fireHour,
                    minute: reminder.fireMinute,
                    second: 0,
                    of: dayCursor
                ), fireDate > now {
                    results.append(fireDate)
                }
            }
            dayCursor = cal.date(byAdding: .day, value: 1, to: dayCursor)!
        }
        return results
    }

    // Every N minutes starting from now, within windowStartMinute..windowEndMinute
    private func everyNMinutesFireTimes(reminder: NotificationReminder) -> [Date] {
        let interval = max(5, reminder.intervalMinutes)
        let windowStart = reminder.windowStartMinute  // minutes from midnight
        let windowEnd = reminder.windowEndMinute

        var results: [Date] = []
        let cal = Calendar.current
        let now = Date()

        // Start at the next interval boundary from now
        let secondsSinceMidnight = Int(now.timeIntervalSince(cal.startOfDay(for: now)))
        let minutesSinceMidnight = secondsSinceMidnight / 60
        // Round up to next interval boundary
        let minutesFromWindow = max(minutesSinceMidnight, windowStart)
        let remainderIntoInterval = minutesFromWindow % interval
        var nextMinute = remainderIntoInterval == 0
            ? minutesFromWindow
            : minutesFromWindow + (interval - remainderIntoInterval)

        // Walk forward collecting up to maxPerReminder times
        var dayOffset = 0
        while results.count < maxPerReminder && dayOffset < 60 {
            let startOfDay = cal.startOfDay(for: cal.date(byAdding: .day, value: dayOffset, to: now)!)
            var minuteCursor = dayOffset == 0 ? nextMinute : windowStart

            while minuteCursor <= windowEnd && results.count < maxPerReminder {
                if let fireDate = cal.date(
                    byAdding: .minute,
                    value: minuteCursor,
                    to: startOfDay
                ), fireDate > now {
                    results.append(fireDate)
                }
                minuteCursor += interval
            }
            dayOffset += 1
            nextMinute = windowStart
        }
        return results
    }

    // Hourly between windowStartMinute and windowEndMinute on specified weekdays
    private func hourlyWindowFireTimes(reminder: NotificationReminder) -> [Date] {
        let weekdays = reminder.weekdays.isEmpty ? [2, 3, 4, 5, 6] : reminder.weekdays
        let windowStart = reminder.windowStartMinute // minutes from midnight
        let windowEnd = reminder.windowEndMinute

        var results: [Date] = []
        let cal = Calendar.current
        let now = Date()
        var dayCursor = cal.startOfDay(for: now)

        while results.count < maxPerReminder {
            let weekday = cal.component(.weekday, from: dayCursor)
            if weekdays.contains(weekday) {
                // Walk hourly slots in the window
                var minuteCursor = windowStart
                while minuteCursor <= windowEnd && results.count < maxPerReminder {
                    if let fireDate = cal.date(
                        byAdding: .minute,
                        value: minuteCursor,
                        to: dayCursor
                    ), fireDate > now {
                        results.append(fireDate)
                    }
                    minuteCursor += 60
                }
            }
            dayCursor = cal.date(byAdding: .day, value: 1, to: dayCursor)!
        }
        return results
    }

    // MARK: - Helpers

    /// Returns the next Date at hour:minute that is strictly after `after`.
    private func nextOccurrence(after: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        // Try today first
        if let todayFire = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: after
        ), todayFire > after {
            return todayFire
        }
        // Otherwise tomorrow
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: after))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
            ?? tomorrow
    }
}
