import Foundation
import EventKit

/// Wraps EventKit. All methods must be called on the main actor.
@MainActor
public final class CalendarAdapterService {

    private let store = EKEventStore()

    // MARK: - Authorization

    /// Request full-access calendar permission. Returns true when granted.
    public func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    /// Current authorization status without triggering a prompt.
    public var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// True when the app has full or write-only access (granted).
    public var isAuthorized: Bool {
        switch authorizationStatus {
        case .fullAccess, .writeOnly, .authorized:
            return true
        default:
            return false
        }
    }

    // MARK: - Fetching

    /// Fetch all EKEvents in [start, end] from the given calendar IDs.
    /// Pass an empty array to fetch from all calendars.
    public func fetchEvents(from start: Date, to end: Date, calendarIds: [String]) -> [EKEvent] {
        let calendars: [EKCalendar]?
        if calendarIds.isEmpty {
            calendars = nil   // all calendars
        } else {
            let all = store.calendars(for: .event)
            let filtered = all.filter { calendarIds.contains($0.calendarIdentifier) }
            calendars = filtered.isEmpty ? nil : filtered
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }

    /// Fetch all EKCalendar objects on the device (event type only).
    public func fetchAllCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    // MARK: - Creating / Deleting

    /// Create an event and return its persistent identifier.
    /// - Parameters:
    ///   - calendarId: Optional calendar ID. Falls back to the default event calendar if nil.
    /// - Throws: If save fails.
    @discardableResult
    public func createEvent(title: String, start: Date, end: Date, calendarId: String?) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end

        if let calendarId = calendarId,
           let cal = store.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarId }) {
            event.calendar = cal
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    /// Create a fully-specified event (title, location, all-day, repeat, alert,
    /// notes, URL) and save it straight into Apple Calendar.
    @discardableResult
    public func createEvent(_ spec: NewEventSpec) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = spec.title
        event.location = (spec.location?.isEmpty == false) ? spec.location : nil
        event.isAllDay = spec.isAllDay
        event.startDate = spec.start
        event.endDate = spec.end
        event.notes = (spec.notes?.isEmpty == false) ? spec.notes : nil
        event.url = spec.url
        if let rule = spec.recurrence { event.addRecurrenceRule(rule) }
        if let minutes = spec.alarmMinutesBefore {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }
        if let calendarId = spec.calendarId,
           let cal = store.calendars(for: .event).first(where: { $0.calendarIdentifier == calendarId }) {
            event.calendar = cal
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    /// Delete the event with the given identifier (all future spans).
    /// Throws if the event is not found or cannot be deleted.
    public func deleteEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) else {
            throw CalendarAdapterError.eventNotFound(id)
        }
        try store.remove(event, span: .thisEvent)
    }
}

// MARK: - New event spec

/// Everything the expanded event editor can set on a new Apple Calendar event.
/// (Invitees and Travel Time are intentionally absent — EventKit can't set them.)
public struct NewEventSpec {
    public var title: String
    public var location: String?
    public var isAllDay: Bool
    public var start: Date
    public var end: Date
    public var calendarId: String?
    public var recurrence: EKRecurrenceRule?
    public var alarmMinutesBefore: Int?
    public var notes: String?
    public var url: URL?

    public init(title: String, location: String? = nil, isAllDay: Bool = false,
                start: Date, end: Date, calendarId: String? = nil,
                recurrence: EKRecurrenceRule? = nil, alarmMinutesBefore: Int? = nil,
                notes: String? = nil, url: URL? = nil) {
        self.title = title; self.location = location; self.isAllDay = isAllDay
        self.start = start; self.end = end; self.calendarId = calendarId
        self.recurrence = recurrence; self.alarmMinutesBefore = alarmMinutesBefore
        self.notes = notes; self.url = url
    }
}

// MARK: - Errors

public enum CalendarAdapterError: LocalizedError {
    case eventNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .eventNotFound(let id):
            return "Calendar event not found: \(id)"
        }
    }
}
