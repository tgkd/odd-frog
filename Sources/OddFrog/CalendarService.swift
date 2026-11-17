import Foundation
import EventKit
import OddFrogPluginAPI
import OddFrogHostServicesAPI

/// EKObjects never leave this actor. Plugins receive plain, immutable event snapshots.
actor CalendarService {
    private lazy var store = EKEventStore()
    private var cached: (range: CalendarRange, snapshot: CalendarSnapshot, fetched: Date)?

    func invalidate() { cached = nil }

    func requestAccess() async throws -> Bool {
        try Task.checkCancellation()
        cached = nil
        return try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func snapshot(for range: CalendarRange) throws -> CalendarSnapshot {
        guard range.isValid(relativeTo: Date()) else { throw CalendarServiceError.invalidRange }
        let access: CalendarSnapshot.Access
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        case .writeOnly: access = .writeOnly
        case .fullAccess: access = .fullAccess
        @unknown default: access = .restricted
        }
        guard access == .fullAccess else { cached = nil; return CalendarSnapshot(access: access) }
        if let cached, cached.range == range, Date().timeIntervalSince(cached.fetched) < 30 { return cached.snapshot }
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: predicate).filter { $0.status != .canceled }.map { event in
            CalendarEvent(
                id: "\(event.calendarItemIdentifier):\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "", start: event.startDate, end: event.endDate,
                allDay: event.isAllDay, calendarName: event.calendar.title,
                location: event.location ?? "", url: event.url?.absoluteString
            )
        }
        // EventKit may return duplicate occurrences after a store update.
        var seen = Set<String>()
        let snapshot = CalendarSnapshot(access: access, events: events.filter { seen.insert($0.id).inserted })
        cached = (range, snapshot, Date())
        return snapshot
    }
}

extension CalendarService {
    func create(_ draft: CalendarEventDraft) throws -> String {
        try Task.checkCancellation()
        guard draft.isValid(relativeTo: Date()) else { throw CalendarServiceError.invalidEvent }
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .writeOnly else { throw CalendarServiceError.noAccess }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarServiceError.noDefaultCalendar }
        let event = EKEvent(eventStore: store)
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.allDay
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { event.location = location }
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        cached = nil
        return calendar.title
    }
}

private enum CalendarServiceError: LocalizedError {
    case invalidRange, invalidEvent, noAccess, noDefaultCalendar

    var errorDescription: String? {
        switch self {
        case .invalidRange: "Invalid calendar range."
        case .invalidEvent: "The event needs a title, an end after its start, and a duration up to 31 days."
        case .noAccess: "Calendar access is not granted."
        case .noDefaultCalendar: "No default calendar for new events."
        }
    }
}
