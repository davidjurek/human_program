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

    /// Delete the event with the given identifier (all future spans).
    /// Throws if the event is not found or cannot be deleted.
    public func deleteEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) else {
            throw CalendarAdapterError.eventNotFound(id)
        }
        try store.remove(event, span: .thisEvent)
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
