import Foundation
import EventKit
import OddFrogPluginAPI
import OddFrogHostServicesAPI

actor RemindersService {
    private lazy var store = EKEventStore()
    private var cached: (scope: RemindersScope, snapshot: RemindersSnapshot, fetched: Date)?

    func invalidate() { cached = nil }

    func requestAccess() async throws -> Bool {
        try Task.checkCancellation()
        cached = nil
        return try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func snapshot(for scope: RemindersScope) async throws -> RemindersSnapshot {
        guard scope.isValid() else { throw RemindersServiceError.invalidScope }
        let access: RemindersSnapshot.Access
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        case .writeOnly: access = .writeOnly
        case .fullAccess: access = .fullAccess
        @unknown default: access = .restricted
        }
        guard access == .fullAccess else { cached = nil; return RemindersSnapshot(access: access) }
        if let cached, cached.scope == scope, Date().timeIntervalSince(cached.fetched) < 30 { return cached.snapshot }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let items: [ReminderItem] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.item))
            }
        }.sorted(by: Self.precedes)
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let snapshot = RemindersSnapshot(access: access, reminders: Array(unique.prefix(scope.limit)),
                                         truncated: unique.count > scope.limit,
                                         defaultListName: store.defaultCalendarForNewReminders()?.title)
        cached = (scope, snapshot, Date())
        return snapshot
    }

    func complete(id: String) throws -> String {
        try Task.checkCancellation()
        try requireAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, !reminder.isCompleted else {
            throw RemindersServiceError.notFound
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        cached = nil
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled reminder" : title
    }

    func create(title: String) throws -> String {
        try Task.checkCancellation()
        try requireAccess()
        guard let list = store.defaultCalendarForNewReminders() else { throw RemindersServiceError.noDefaultList }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        try store.save(reminder, commit: true)
        cached = nil
        return list.title
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw RemindersServiceError.noAccess
        }
    }
}

extension RemindersService {
    private static func item(_ reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let due = components.flatMap { $0.calendar?.date(from: $0) ?? Calendar.current.date(from: $0) }
        return ReminderItem(
            id: reminder.calendarItemIdentifier, title: reminder.title ?? "", due: due,
            allDay: components != nil && components?.hour == nil,
            listName: reminder.calendar.title, priority: reminder.priority,
            url: reminder.url?.absoluteString
        )
    }

    private static func precedes(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.due, rhs.due) {
        case let (left?, right?) where left != right: return left < right
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }
}

private enum RemindersServiceError: LocalizedError {
    case invalidScope, notFound, noDefaultList, noAccess

    var errorDescription: String? {
        switch self {
        case .invalidScope: "Invalid reminders scope."
        case .notFound: "Reminder not found."
        case .noDefaultList: "No default Reminders list."
        case .noAccess: "Reminders access is not granted."
        }
    }
}
