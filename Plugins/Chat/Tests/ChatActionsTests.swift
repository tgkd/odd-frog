import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI
import OddFrogHostServicesAPI

private actor FakeHost {
    private var responses: [String: [JSONValue]]
    private(set) var calls: [(capability: String, params: JSONValue)] = []

    init(_ responses: [String: [JSONValue]]) {
        self.responses = responses
    }

    func call(_ capability: String, _ params: JSONValue) throws -> JSONValue {
        calls.append((capability, params))
        guard var queue = responses[capability], !queue.isEmpty else {
            throw RPCError("test", "Unexpected call \(capability)")
        }
        let value = queue.count > 1 ? queue.removeFirst() : queue[0]
        responses[capability] = queue
        return value
    }

    var capabilities: [String] { calls.map(\.capability) }
}

struct ChatActionsTests {
    private let zone = TimeZone(identifier: "Europe/Berlin")!
    private var now: Date { ChatDates(now: Date(), timeZone: zone).parse("2026-11-17T14:00")!.date }

    private func actions(_ host: FakeHost, notes: ChatNotesSource = .oddFrog) -> ChatActions {
        ChatActions(context: ChatToolContext(now: now, timeZone: zone, notes: notes) { capability, params in
            try await host.call(capability, params)
        })
    }

    private func effects(_ notification: String) throws -> JSONValue {
        try .encode(PluginEffects(notification: notification, refreshQuery: true))
    }

    @Test func datesParseLocalDayAndTimeFormsOnly() throws {
        let dates = ChatDates(now: now, timeZone: zone)
        let timed = try #require(dates.parse("2026-11-18T09:30"))
        #expect(timed.hasTime)
        #expect(dates.describe(timed.date, time: true) == "Wed 2026-11-18 09:30")
        #expect(dates.parse(" 2026-11-18 ")?.hasTime == false)
        #expect(dates.parse("2026-11-18 09:30")?.hasTime == true)
        #expect(dates.parse("tomorrow") == nil)
        #expect(dates.parse("2026-02-30") == nil)
    }

    @Test func addReminderSendsTheDueDateAndReportsIt() async throws {
        let host = FakeHost(["reminders.read@1": [try .encode(RemindersSnapshot(access: .fullAccess))],
                             "reminders.create@1": [try effects("Added to Inbox: Call Bob")]])
        let outcome = await actions(host).addReminder(title: " Call Bob ", date: "2026-11-18", time: "09:00")
        #expect(outcome.reply == "Added to Inbox: Call Bob")
        #expect(outcome.activity == "Added reminder “Call Bob”, due Wed 2026-11-18 09:00")
        let create = try #require(await host.calls.last)
        #expect(create.capability == "reminders.create@1")
        let draft = try create.params.decode(ReminderDraft.self)
        #expect(draft.allDay == false)
        #expect(draft.due == ChatDates(now: now, timeZone: zone).parse("2026-11-18T09:00")?.date)
    }

    @Test func undeterminedAccessIsRequestedOnceAndDeniedAccessStopsTheWrite() async throws {
        let host = FakeHost(["reminders.read@1": [try .encode(RemindersSnapshot(access: .notDetermined)),
                                                  try .encode(RemindersSnapshot(access: .denied))],
                             "reminders.access@1": [try .encode(PluginEffects())]])
        let outcome = await actions(host).addReminder(title: "Call Bob", date: nil, time: nil)
        #expect(outcome.reply.contains("Privacy & Security › Reminders"))
        #expect(outcome.activity == nil)
        #expect(await host.capabilities == ["reminders.read@1", "reminders.access@1", "reminders.read@1"])
    }

    @Test func completeReminderNeedsOneMatch() async throws {
        let items = [ReminderItem(id: "1", title: "Call Bob"), ReminderItem(id: "2", title: "Call Bobby"),
                     ReminderItem(id: "3", title: "Buy milk")]
        let host = FakeHost(["reminders.read@1": [try .encode(RemindersSnapshot(access: .fullAccess, reminders: items))],
                             "reminders.complete@1": [try effects("Completed: Call Bob")]])
        let ambiguous = await actions(host).completeReminder(title: "call")
        #expect(ambiguous.reply.hasPrefix("Several reminders match"))
        let exact = await actions(host).completeReminder(title: "call bob")
        #expect(exact.activity == "Completed reminder “Call Bob”")
        let missing = await actions(host).completeReminder(title: "walk dog")
        #expect(missing.activity == nil)
        let completed = await host.calls.filter { $0.capability == "reminders.complete@1" }
        #expect(completed.map { $0.params["id"].string } == ["1"])
    }

    @Test func eventsAreClampedToTheReadableWindowAndListedInOrder() async throws {
        let dates = ChatDates(now: now, timeZone: zone)
        let events = [
            CalendarEvent(id: "b", title: "Review", start: dates.parse("2026-11-18T15:00")!.date,
                          end: dates.parse("2026-11-18T16:00")!.date, calendarName: "Work"),
            CalendarEvent(id: "a", title: "Holiday", start: dates.parse("2026-11-18")!.date,
                          end: dates.parse("2026-11-19")!.date, allDay: true),
        ]
        let host = FakeHost(["calendar.read@1": [try .encode(CalendarSnapshot(access: .fullAccess, events: events))]])
        let outcome = await actions(host).events(from: "2026-11-18", days: 90)
        #expect(outcome.reply == "- Wed 2026-11-18, all day: Holiday\n- Wed 2026-11-18 15:00–16:00: Review (Work)")
        let range = try #require(await host.calls.first).params.decode(CalendarRange.self)
        #expect(range.isValid(relativeTo: now))
        let old = await actions(host).events(from: "2026-01-01", days: 3)
        #expect(old.reply.contains("2 days ago"))
    }

    @Test func createEventDefaultsToOneHourAndAllDayToOneDay() async throws {
        let host = FakeHost(["calendar.read@1": [try .encode(CalendarSnapshot(access: .fullAccess))],
                             "calendar.create@1": [try effects("Added to Home: Dentist")]])
        let timed = await actions(host).createEvent(title: "Dentist", date: "2026-11-20", time: "10:00", endDate: nil,
                                                    endTime: nil, location: nil)
        #expect(timed.activity == "Added event “Dentist”, Fri 2026-11-20 10:00")
        let allDay = await actions(host).createEvent(title: "Trip", date: "2026-11-21", time: nil, endDate: "2026-11-22",
                                                     endTime: nil, location: "Rome")
        #expect(allDay.activity == "Added event “Trip”, Sat 2026-11-21")
        let drafts = try await host.calls.filter { $0.capability == "calendar.create@1" }
            .map { try $0.params.decode(CalendarEventDraft.self) }
        #expect(drafts.map { $0.end.timeIntervalSince($0.start) } == [3600, 2 * 86400])
        #expect(drafts.map(\.allDay) == [false, true])
        #expect(drafts.last?.location == "Rome")
    }

    @Test func appendToNoteFindsTheNoteByItsFirstLine() async throws {
        let notes = [NoteRecord(id: "n1", text: "Groceries\nmilk", modified: now),
                     NoteRecord(id: "n2", text: "Ideas\nlauncher", modified: now)]
        let host = FakeHost(["notes.read@1": [try .encode(NotesSnapshot(notes: notes))],
                             "notes.append@1": [try effects("Note updated: Groceries")]])
        let outcome = await actions(host).appendToNote(title: "groceries", text: "eggs")
        #expect(outcome.activity == "Added to note “Groceries”")
        let append = try #require(await host.calls.last).params.decode(NoteAppend.self)
        #expect(append == NoteAppend(id: "n1", text: "eggs"))
    }

    @Test func clockTimesAcceptTwentyFourHourAndAmPmForms() {
        #expect(ChatDates.minutes(of: "07:00") == 420)
        #expect(ChatDates.minutes(of: "7am") == 420)
        #expect(ChatDates.minutes(of: "7:30 PM") == 1170)
        #expect(ChatDates.minutes(of: "12am") == 0)
        #expect(ChatDates.minutes(of: "12 p.m.") == 720)
        #expect(ChatDates.minutes(of: "24:00") == nil)
        #expect(ChatDates.minutes(of: "13pm") == nil)
        #expect(ChatDates.minutes(of: "soon") == nil)
    }

    @Test func aReminderWithASeparateTimeKeepsTheTime() async throws {
        let host = FakeHost(["reminders.read@1": [try .encode(RemindersSnapshot(access: .fullAccess))],
                             "reminders.create@1": [try effects("Added to Inbox: Meeting")]])
        let dated = await actions(host).addReminder(title: "Meeting", date: "2026-11-18", time: "7am")
        #expect(dated.activity == "Added reminder “Meeting”, due Wed 2026-11-18 07:00")
        let timeOnly = await actions(host).addReminder(title: "Stretch", date: nil, time: "18:00")
        #expect(timeOnly.activity == "Added reminder “Stretch”, due Tue 2026-11-17 18:00")
        let bad = await actions(host).addReminder(title: "Meeting", date: "2026-11-18", time: "later")
        #expect(bad.activity == nil)
        let drafts = try await host.calls.filter { $0.capability == "reminders.create@1" }
            .map { try $0.params.decode(ReminderDraft.self) }
        #expect(drafts.map(\.allDay) == [false, false])
    }

    @Test func appleNotesSourceUsesTheAppleNotesServices() async throws {
        let host = FakeHost(["applenotes.read@1": [try .encode(NotesSnapshot(notes: [NoteRecord(id: "x", text: "Trip\nRome", modified: now)]))],
                             "applenotes.create@1": [try effects("Apple Note added: Packing")],
                             "applenotes.append@1": [try effects("Apple Note updated: Trip")]])
        let apple = actions(host, notes: .apple)
        #expect(await apple.notes(search: "rome").reply.hasPrefix("Apple Note “Trip”"))
        #expect(await apple.createNote(text: "Packing\nsocks").activity == "Added Apple Note “Packing”")
        #expect(await apple.appendToNote(title: "trip", text: "Florence").activity == "Added to Apple Note “Trip”")
        #expect(await host.capabilities == ["applenotes.read@1", "applenotes.create@1", "applenotes.read@1", "applenotes.append@1"])
    }

    @Test func hostErrorsBecomeVisibleActivity() async throws {
        let host = FakeHost(["notes.create@1": []])
        let outcome = await actions(host).createNote(text: "Plan\nstep one")
        #expect(outcome.activity == "Could not add the note: Unexpected call notes.create@1")
    }
}
