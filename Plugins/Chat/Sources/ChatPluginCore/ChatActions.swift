import Foundation
import OddFrogPluginAPI
import OddFrogHostServicesAPI

public enum ChatNotesSource: String, Sendable {
    case oddFrog = "Odd Frog"
    case apple = "Apple Notes"

    var service: String {
        self == .apple ? "applenotes" : "notes"
    }

    var noun: String {
        self == .apple ? "Apple Note" : "note"
    }
}

public struct ChatToolContext: Sendable {
    public typealias Call = @Sendable (String, JSONValue) async throws -> JSONValue
    public let call: Call
    public let now: Date
    public let timeZone: TimeZone
    public let notes: ChatNotesSource

    public init(now: Date = Date(), timeZone: TimeZone = .current, notes: ChatNotesSource = .oddFrog,
                call: @escaping Call) {
        self.call = call
        self.now = now
        self.timeZone = timeZone
        self.notes = notes
    }
}

public struct ChatOutcome: Sendable, Equatable {
    public var reply: String
    public var activity: String?

    public init(reply: String, activity: String? = nil) {
        self.reply = reply
        self.activity = activity
    }
}

public struct ChatActions: Sendable {
    private let context: ChatToolContext
    private let dates: ChatDates

    public init(context: ChatToolContext) {
        self.context = context
        dates = ChatDates(now: context.now, timeZone: context.timeZone)
    }

    public var instructions: String {
        """
        Now it is \(dates.describeNow()). Use the tools to read or change the user's calendar, \
        reminders and notes when the user asks about them. Give dates to tools as YYYY-MM-DD and \
        times as HH:MM in 24-hour form, in the user's local time. After a change, say in one short \
        sentence what you did. Never invent events, reminders or notes; use only what tools return. \
        When the user names a time, always pass it in the time field.
        """
    }

    public func events(from start: String?, days: Int?) async -> ChatOutcome {
        let count = min(max(days ?? 1, 1), 31)
        let first: Date
        if let start, !start.isEmpty {
            guard let parsed = dates.parse(start) else { return dateError(start) }
            first = dates.startOfDay(parsed.date)
        } else {
            first = dates.startOfDay(context.now)
        }
        let lower = max(first, context.now.addingTimeInterval(-2 * 86400 + 60))
        let upper = min(dates.adding(days: count, to: first), context.now.addingTimeInterval(32 * 86400 - 60))
        guard upper > lower else {
            return ChatOutcome(reply: "The calendar can be read from 2 days ago up to 32 days ahead only.")
        }
        do {
            guard case .ready(let snapshot) = try await calendar(CalendarRange(start: lower, end: upper)) else {
                return Self.calendarDenied
            }
            guard !snapshot.events.isEmpty else {
                return ChatOutcome(reply: "No events from \(dates.describe(lower, time: false)) to \(dates.describe(upper, time: false)).")
            }
            let lines = snapshot.events.sorted { $0.start < $1.start }.prefix(40).map(describe)
            return ChatOutcome(reply: lines.joined(separator: "\n"))
        } catch {
            return failure(error, doing: "read the calendar")
        }
    }

    public func createEvent(title: String, date: String, time: String?, endDate: String?, endTime: String?,
                            location: String?) async -> ChatOutcome {
        guard let begin = dates.combine(date: date, time: time) else { return dateError(date, time) }
        let finish: Date
        if (endDate ?? "").isEmpty, (endTime ?? "").isEmpty {
            finish = begin.hasTime ? begin.date.addingTimeInterval(3600) : dates.adding(days: 1, to: begin.date)
        } else {
            let day = (endDate ?? "").isEmpty ? date : endDate ?? date
            guard let parsed = dates.combine(date: day, time: begin.hasTime ? endTime : nil) else {
                return dateError(day, endTime)
            }
            finish = parsed.hasTime ? parsed.date : dates.adding(days: 1, to: parsed.date)
        }
        let draft = CalendarEventDraft(title: title, start: begin.date, end: finish, allDay: !begin.hasTime,
                                       location: location ?? "")
        guard draft.isValid(relativeTo: context.now) else {
            return ChatOutcome(reply: "Not added: the event needs a title and an end after its start, at most 31 days long.")
        }
        do {
            let probe = CalendarRange(start: context.now, end: context.now.addingTimeInterval(3600))
            guard case .ready = try await calendar(probe) else { return Self.calendarDenied }
            let effects = try await context.call("calendar.create@1", .encode(draft)).decode(PluginEffects.self)
            let when = dates.describe(begin.date, time: begin.hasTime)
            return ChatOutcome(reply: effects.notification ?? "Event added.",
                               activity: "Added event “\(draft.title)”, \(when)")
        } catch {
            return failure(error, doing: "add the event")
        }
    }

    public func reminders(search: String?) async -> ChatOutcome {
        do {
            guard case .ready(let snapshot) = try await reminders() else { return Self.remindersDenied }
            let filter = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let items = snapshot.reminders.filter { filter.isEmpty || $0.title.localizedStandardContains(filter) }
            guard !items.isEmpty else {
                return ChatOutcome(reply: filter.isEmpty ? "No open reminders." : "No open reminders match “\(filter)”.")
            }
            var lines = items.prefix(30).map(describe)
            if items.count > 30 { lines.append("…and \(items.count - 30) more.") }
            return ChatOutcome(reply: lines.joined(separator: "\n"))
        } catch {
            return failure(error, doing: "read reminders")
        }
    }

    public func addReminder(title: String, date: String?, time: String?) async -> ChatOutcome {
        var draft = ReminderDraft(title: title)
        if let date, !date.isEmpty {
            guard let parsed = dates.combine(date: date, time: time) else { return dateError(date, time) }
            draft.due = parsed.date
            draft.allDay = !parsed.hasTime
        } else if let time, !time.isEmpty {
            guard let parsed = dates.combine(date: dates.today, time: time) else { return dateError(dates.today, time) }
            draft.due = parsed.date
        }
        guard draft.isValid() else { return ChatOutcome(reply: "Not added: a reminder needs a title.") }
        do {
            guard case .ready = try await reminders() else { return Self.remindersDenied }
            let effects = try await context.call("reminders.create@1", .encode(draft)).decode(PluginEffects.self)
            let when = draft.due.map { ", due " + dates.describe($0, time: !draft.allDay) } ?? ""
            return ChatOutcome(reply: effects.notification ?? "Reminder added.",
                               activity: "Added reminder “\(draft.trimmedTitle)”\(when)")
        } catch {
            return failure(error, doing: "add the reminder")
        }
    }

    public func completeReminder(title: String) async -> ChatOutcome {
        do {
            guard case .ready(let snapshot) = try await reminders() else { return Self.remindersDenied }
            switch Self.match(snapshot.reminders, query: title, title: \.title) {
            case .none:
                return ChatOutcome(reply: "No open reminder matches “\(title)”.")
            case .many(let items):
                return ChatOutcome(reply: "Several reminders match. Ask the user which one: "
                                   + items.prefix(5).map { "“\($0.title)”" }.joined(separator: ", "))
            case .one(let item):
                _ = try await context.call("reminders.complete@1", .object(["id": .string(item.id)]))
                return ChatOutcome(reply: "Completed “\(item.title)”.", activity: "Completed reminder “\(item.title)”")
            }
        } catch {
            return failure(error, doing: "complete the reminder")
        }
    }

    public func notes(search: String?) async -> ChatOutcome {
        do {
            let filter = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let snapshot = try await context.call("\(notesService).read@1", .encode(NotesQuery(query: filter, limit: 5)))
                .decode(NotesSnapshot.self)
            guard !snapshot.notes.isEmpty else {
                return ChatOutcome(reply: filter.isEmpty ? "There are no unlocked notes." : "No notes contain “\(filter)”.")
            }
            let blocks = snapshot.notes.map { note in
                let body = note.text.count > 800 ? String(note.text.prefix(800)) + "…" : note.text
                return "\(context.notes.noun.capitalizedFirst) “\(Self.title(of: note.text))” (\(dates.describe(note.modified, time: true))):\n\(body)"
            }
            return ChatOutcome(reply: blocks.joined(separator: "\n\n"))
        } catch {
            return failure(error, doing: "read notes")
        }
    }

    public func createNote(text: String) async -> ChatOutcome {
        guard NoteText.isValid(text) else { return ChatOutcome(reply: "Not added: the note is empty.") }
        do {
            let effects = try await context.call("\(notesService).create@1", .object(["text": .string(text)]))
                .decode(PluginEffects.self)
            return ChatOutcome(reply: effects.notification ?? "Note added.",
                               activity: "Added \(context.notes.noun) “\(Self.title(of: text))”")
        } catch {
            return failure(error, doing: "add the note")
        }
    }

    public func appendToNote(title: String, text: String) async -> ChatOutcome {
        guard NoteText.isValid(text) else { return ChatOutcome(reply: "Nothing to add.") }
        do {
            let snapshot = try await context.call("\(notesService).read@1", .encode(NotesQuery(query: "", limit: 200)))
                .decode(NotesSnapshot.self)
            switch Self.match(snapshot.notes, query: title, title: { Self.title(of: $0.text) }) {
            case .none:
                return ChatOutcome(reply: "No note is titled like “\(title)”.")
            case .many(let notes):
                return ChatOutcome(reply: "Several notes match. Ask the user which one: "
                                   + notes.prefix(5).map { "“\(Self.title(of: $0.text))”" }.joined(separator: ", "))
            case .one(let note):
                _ = try await context.call("\(notesService).append@1", .encode(NoteAppend(id: note.id, text: text)))
                let name = Self.title(of: note.text)
                return ChatOutcome(reply: "Added to the \(context.notes.noun) “\(name)”.",
                                   activity: "Added to \(context.notes.noun) “\(name)”")
            }
        } catch {
            return failure(error, doing: "update the note")
        }
    }

    private var notesService: String {
        context.notes.service
    }

    public enum Match<Item> {
        case none
        case one(Item)
        case many([Item])
    }

    public static func match<Item>(_ items: [Item], query: String, title: (Item) -> String) -> Match<Item> {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return .none }
        let exact = items.filter { title($0).compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        let candidates = exact.isEmpty ? items.filter { title($0).localizedStandardContains(wanted) } : exact
        switch candidates.count {
        case 0: return .none
        case 1: return .one(candidates[0])
        default: return .many(candidates)
        }
    }

    public static func title(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map { String($0.prefix(80)) } ?? "Untitled"
    }

    private enum Access<Snapshot> {
        case ready(Snapshot)
        case denied
    }

    private func calendar(_ range: CalendarRange) async throws -> Access<CalendarSnapshot> {
        var snapshot = try await context.call("calendar.read@1", .encode(range)).decode(CalendarSnapshot.self)
        if snapshot.access == .notDetermined {
            _ = try await context.call("calendar.access@1", .object([:]))
            snapshot = try await context.call("calendar.read@1", .encode(range)).decode(CalendarSnapshot.self)
        }
        return snapshot.access == .fullAccess ? .ready(snapshot) : .denied
    }

    private func reminders() async throws -> Access<RemindersSnapshot> {
        let scope = RemindersScope(limit: 2000)
        var snapshot = try await context.call("reminders.read@1", .encode(scope)).decode(RemindersSnapshot.self)
        if snapshot.access == .notDetermined {
            _ = try await context.call("reminders.access@1", .object([:]))
            snapshot = try await context.call("reminders.read@1", .encode(scope)).decode(RemindersSnapshot.self)
        }
        return snapshot.access == .fullAccess ? .ready(snapshot) : .denied
    }

    private static let calendarDenied = ChatOutcome(
        reply: "Calendar access is off. Tell the user to allow Odd Frog in System Settings › Privacy & Security › Calendars.")
    private static let remindersDenied = ChatOutcome(
        reply: "Reminders access is off. Tell the user to allow Odd Frog in System Settings › Privacy & Security › Reminders.")

    private func describe(_ event: CalendarEvent) -> String {
        let when = event.allDay
            ? dates.describe(event.start, time: false) + ", all day"
            : dates.describe(event.start, time: true) + "–" + dates.clock(event.end)
        let details = [event.calendarName, event.location].filter { !$0.isEmpty }.joined(separator: ", ")
        return "- \(when): \(event.title.isEmpty ? "Untitled event" : event.title)" + (details.isEmpty ? "" : " (\(details))")
    }

    private func describe(_ item: ReminderItem) -> String {
        var parts = ["- \(item.title.isEmpty ? "Untitled reminder" : item.title)"]
        if let due = item.due { parts.append("due " + dates.describe(due, time: !item.allDay)) }
        if !item.listName.isEmpty { parts.append(item.listName) }
        return parts.joined(separator: " · ")
    }

    private func dateError(_ date: String, _ time: String? = nil) -> ChatOutcome {
        let given = [date, time ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return ChatOutcome(reply: "“\(given)” is not a valid date and time. Use YYYY-MM-DD and HH:MM.")
    }

    private func failure(_ error: any Error, doing action: String) -> ChatOutcome {
        let message = (error as? RPCError)?.message ?? error.localizedDescription
        return ChatOutcome(reply: "Could not \(action): \(message)", activity: "Could not \(action): \(message)")
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
