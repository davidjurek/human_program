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

    // Safety cap on how many days the fire-time loops walk forward. Sparse schedules
    // (e.g. a single weekday) may not gather maxPerReminder times within a short span,
    // so the day-walk needs an upper bound to stay bounded; 60 days is comfortably
    // beyond any realistic window for 20 fire times. [#98]
    private let maxDayWalk = 60

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
        let fireTimes = computeFireTimes(for: reminder)

        return fireTimes.enumerated().compactMap { index, date in
            guard date > Date() else { return nil }
            // Build a FRESH content (and a fresh image attachment, each with its own temp
            // file) per request. iOS MOVES an attachment's file into its store when the
            // request is added, so a single shared content/attachment reused across all
            // ~20 requests left every notification after the first with a dangling file —
            // they fired without the image. One attachment per request fixes that. [#image]
            let content = makeContent(for: reminder)
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

        // Attach the optional image (saved by ReminderImageStore). [#57]
        // UNNotificationAttachment takes OWNERSHIP of the file it's given (it moves
        // it into the system attachment store), which would destroy our stored
        // original and break later reschedules. So attach a temp COPY instead.
        if let filename = reminder.imageFilename {
            let src = ReminderImageStore.url(for: filename)
            if FileManager.default.fileExists(atPath: src.path) {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + filename)
                try? FileManager.default.removeItem(at: tmp)
                if (try? FileManager.default.copyItem(at: src, to: tmp)) != nil,
                   let attachment = try? UNNotificationAttachment(identifier: filename, url: tmp) {
                    content.attachments = [attachment]
                }
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

    /// Walk forward from today, day-by-day, calling `times` for each day to collect
    /// that day's fire times. Stops once maxPerReminder are gathered or the cap is hit.
    /// Centralises the day cursor and replaces the old force-unwrapped `date(byAdding:)`
    /// steps with a safe guard that ends the loop cleanly if date math ever fails. [#82][#94]
    private func walkDays(_ times: (_ startOfDay: Date) -> [Date]) -> [Date] {
        var results: [Date] = []
        let cal = Calendar.current
        var dayCursor = cal.startOfDay(for: Date())
        while results.count < maxPerReminder && results.count < maxDayWalk {
            for fireDate in times(dayCursor) where results.count < maxPerReminder {
                results.append(fireDate)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: dayCursor) else { break }
            dayCursor = next
        }
        return results
    }

    // Daily: next maxPerReminder days at fireHour:fireMinute
    private func dailyFireTimes(reminder: NotificationReminder) -> [Date] {
        let cal = Calendar.current
        let now = Date()
        return walkDays { startOfDay in
            guard let fireDate = cal.date(
                bySettingHour: reminder.fireHour,
                minute: reminder.fireMinute,
                second: 0,
                of: startOfDay
            ), fireDate > now else { return [] }
            return [fireDate]
        }
    }

    // Weekly on specific weekdays (1=Sun…7=Sat) at fireHour:fireMinute
    private func weekdayFireTimes(reminder: NotificationReminder, weekdays: [Int]) -> [Date] {
        guard !weekdays.isEmpty else { return [] }
        let cal = Calendar.current
        let now = Date()
        return walkDays { startOfDay in
            let weekday = cal.component(.weekday, from: startOfDay) // 1=Sun…7=Sat
            guard weekdays.contains(weekday),
                  let fireDate = cal.date(
                    bySettingHour: reminder.fireHour,
                    minute: reminder.fireMinute,
                    second: 0,
                    of: startOfDay
                  ), fireDate > now else { return [] }
            return [fireDate]
        }
    }

    // Every N minutes starting from now, within windowStartMinute..windowEndMinute
    private func everyNMinutesFireTimes(reminder: NotificationReminder) -> [Date] {
        let interval = max(5, reminder.intervalMinutes)
        let windowStart = reminder.windowStartMinute  // minutes from midnight
        let windowEnd = reminder.windowEndMinute

        var results: [Date] = []
        let cal = Calendar.current
        let now = Date()

        // Start at the next interval boundary measured FROM THE WINDOW START, not from
        // midnight — so fire times are windowStart, windowStart+interval, … every day
        // (e.g. an 08:00 window with a 25-min interval fires 08:00, 08:25, 08:50…), and
        // they don't drift to odd minutes or differ between the first day and later days. [#7]
        let secondsSinceMidnight = Int(now.timeIntervalSince(cal.startOfDay(for: now)))
        let minutesSinceMidnight = secondsSinceMidnight / 60
        let minutesFromWindow = max(minutesSinceMidnight, windowStart)
        let offsetIntoWindow = minutesFromWindow - windowStart
        let remainderIntoInterval = offsetIntoWindow % interval
        var nextMinute = remainderIntoInterval == 0
            ? minutesFromWindow
            : minutesFromWindow + (interval - remainderIntoInterval)

        // Walk forward collecting up to maxPerReminder times
        var dayOffset = 0
        while results.count < maxPerReminder && dayOffset < maxDayWalk {
            // Safe date math: stop cleanly if adding days ever fails instead of crashing. [#82]
            guard let dayDate = cal.date(byAdding: .day, value: dayOffset, to: now) else { break }
            let startOfDay = cal.startOfDay(for: dayDate)
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
        let cal = Calendar.current
        let now = Date()

        return walkDays { dayStart in
            let weekday = cal.component(.weekday, from: dayStart)
            guard weekdays.contains(weekday) else { return [] }
            // Walk hourly slots in the window
            var times: [Date] = []
            var minuteCursor = windowStart
            while minuteCursor <= windowEnd {
                if let fireDate = cal.date(byAdding: .minute, value: minuteCursor, to: dayStart),
                   fireDate > now {
                    times.append(fireDate)
                }
                minuteCursor += 60
            }
            return times
        }
    }
}
