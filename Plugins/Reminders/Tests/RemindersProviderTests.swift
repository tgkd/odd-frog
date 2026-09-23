import Foundation
import Testing
import RemindersPluginCore
import OddFrogPluginAPI
import OddFrogHostServicesAPI

struct RemindersProviderTests {
    private struct Input: Codable { var query: PluginQuery; var snapshot: RemindersSnapshot }
    private struct Output: Codable { var items: [PluginItem] }
    private func respond(to input: Input) -> Output { Output(items: RemindersProvider.respond(to: input.query, snapshot: input.snapshot)) }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-09-09T12:00:00Z") }

    private func request(_ query: String = "", reminders: [ReminderItem] = [],
                         access: RemindersSnapshot.Access = .fullAccess, truncated: Bool = false,
                         list: String? = "Inbox") -> Input {
        Input(query: PluginQuery(query: query, fullQuery: "rem " + query, now: now,
                                timeZoneIdentifier: "UTC", maxResults: 50),
              snapshot: RemindersSnapshot(access: access, reminders: reminders, truncated: truncated, defaultListName: list))
    }

    private func reminder(_ id: String, _ due: String? = nil, title: String = "Task",
                          allDay: Bool = false, list: String = "Inbox", priority: Int = 0) -> ReminderItem {
        ReminderItem(id: id, title: title, due: due.map(date), allDay: allDay, listName: list, priority: priority)
    }

    private var mixed: [ReminderItem] {
        [
            reminder("overdue", "2026-09-08T10:00:00Z", title: "Overdue task"),
            reminder("today-late", "2026-09-09T18:00:00Z", title: "Evening task"),
            reminder("today-early", "2026-09-09T10:00:00Z", title: "Morning task"),
            reminder("tomorrow", "2026-09-10T09:00:00Z", title: "Design review"),
            reminder("week-edge", "2026-09-15T23:00:00Z", title: "Week edge"),
            reminder("outside-week", "2026-09-16T00:00:00Z", title: "Just outside"),
            reminder("undated", title: "Someday", list: "Ideas"),
        ]
    }

    @Test func serviceScopeIsBounded() {
        #expect(RemindersScope(limit: 2000).isValid())
        #expect(!RemindersScope(limit: 2001).isValid())
    }

    @Test func bareKeywordListsEverythingWithUndatedLast() {
        #expect(respond(to: request(reminders: mixed)).items.map(\.id)
            == ["overdue", "today-early", "today-late", "tomorrow", "week-edge", "outside-week", "undated"])
    }

    @Test func todayIncludesOverdueButNotTomorrowOrUndated() {
        #expect(respond(to: request("today", reminders: mixed)).items.map(\.id)
            == ["overdue", "today-early", "today-late"])
    }

    @Test func tomorrowExcludesOverdueAndToday() {
        #expect(respond(to: request("tomorrow", reminders: mixed)).items.map(\.id) == ["tomorrow"])
    }

    @Test func weekAndExplicitDayRangesAreBounded() {
        #expect(respond(to: request("week", reminders: mixed)).items.map(\.id)
            == ["overdue", "today-early", "today-late", "tomorrow", "week-edge"])
        let twelve = [reminder("in", "2026-09-20T23:00:00Z"), reminder("out", "2026-09-21T00:00:00Z")]
        #expect(respond(to: request("12d", reminders: twelve)).items.map(\.id) == ["in"])
        let clamped = [reminder("far", "2026-10-08T00:00:00Z"), reminder("beyond", "2026-10-10T00:00:00Z")]
        #expect(respond(to: request("90d", reminders: clamped)).items.map(\.id) == ["far"])
    }

    @Test func allListsEverythingWithUndatedLast() {
        #expect(respond(to: request("all", reminders: mixed)).items.map(\.id)
            == ["overdue", "today-early", "today-late", "tomorrow", "week-edge", "outside-week", "undated"])
    }

    @Test func searchMatchesTitleAndListAndIncludesUndated() {
        #expect(respond(to: request("someday", reminders: mixed)).items.map(\.id) == ["undated"])
        #expect(respond(to: request("IDEAS", reminders: mixed)).items.map(\.id) == ["undated"])
        #expect(respond(to: request("task", reminders: mixed)).items.map(\.id)
            == ["overdue", "today-early", "today-late"])
        #expect(respond(to: request("week design", reminders: mixed)).items.map(\.id) == ["tomorrow"])
    }

    @Test func allDayRemindersAreNotOverdueOnTheirOwnDay() {
        let items = [reminder("all-day", "2026-09-09T00:00:00Z", allDay: true),
                     reminder("yesterday", "2026-09-08T00:00:00Z", allDay: true)]
        let response = respond(to: request(reminders: items))
        #expect(response.items.map(\.id) == ["yesterday", "all-day"])
        #expect(response.items[0].subtitle?.hasPrefix("Overdue · ") == true)
        #expect(response.items[1].subtitle?.contains("Overdue") == false)
        #expect(response.items[1].subtitle?.hasPrefix("Wed 9 Sep · Inbox") == true)
    }

    @Test func rowsCarryDateListPriorityAndOpenReminders() {
        let items = [reminder("urgent", "2026-09-09T18:00:00Z", title: "  Ship it  ", list: "Work", priority: 1),
                     reminder("normal", "2026-09-09T19:00:00Z", title: " \n", priority: 5)]
        let response = respond(to: request(reminders: items))
        #expect(response.items[0].title == "Ship it")
        #expect(response.items[0].subtitle?.contains("Work · High priority") == true)
        #expect(response.items[0].primary == PluginAction(.openApplication, "com.apple.reminders"))
        #expect(response.items[0].kind == "Reminder")
        #expect(response.items[1].title == "Untitled reminder")
        #expect(response.items[1].subtitle?.contains("High priority") == false)
    }

    @Test func permissionStatesHaveIntentionalActions() {
        for access in [RemindersSnapshot.Access.notDetermined, .writeOnly] {
            let item = respond(to: request(access: access)).items.first
            #expect(item?.title == "Allow Reminders access")
            #expect(item?.primary?.kind == .service)
        }
        #expect(respond(to: request(access: .denied)).items.first?.primary?.kind == .openURL)
        #expect(respond(to: request(access: .restricted)).items.first?.primary == nil)

    }

    @Test func emptyStatesNameThePeriodAndTruncation() {
        for (query, title) in [
            ("", "No reminders"),
            ("today", "No reminders due today"),
            ("tomorrow", "No reminders due tomorrow"),
            ("week", "No reminders due in the next 7 days"),
            ("12d", "No reminders due in the next 12 days"),
            ("all", "No reminders"),
            ("all zzz", "No matching reminders"),
            ("week zzz", "No matching reminders due in the next 7 days"),
        ] {
            let response = respond(to: request(query))
            #expect(response.items.first?.title == title)
            #expect(response.items.first?.primary == PluginAction(.openApplication, "com.apple.reminders"))
        }
        #expect(respond(to: request("all", truncated: true)).items.first?.title == "No reminders (list truncated)")
    }

    @Test func addBuildsACreateActionForTheDefaultList() {
        let response = respond(to: request("add Buy milk"))
        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Buy milk")
        #expect(response.items[0].primary == PluginAction(.service, "reminders.create@1", payload: .object(["title": .string("Buy milk")])))
        #expect(response.items[0].subtitle == "Press Return to add to Inbox")
        #expect(response.items[0].symbol == "plus.circle")
        #expect(respond(to: request("new Buy milk")).items[0].primary
            == PluginAction(.service, "reminders.create@1", payload: .object(["title": .string("Buy milk")])))
        #expect(respond(to: request("add Buy milk", list: nil)).items[0].subtitle
            == "Press Return to add a reminder")
    }

    @Test func addWithoutATitleIsAnInertStatusRow() {
        let response = respond(to: request("add"))
        #expect(response.items[0].title == "Add a reminder")
        #expect(response.items[0].primary == nil)
        #expect(respond(to: request("add", access: .notDetermined)).items[0].primary?.kind
            == .service)
        #expect(respond(to: request("add Buy milk", access: .notDetermined)).items[0].primary?.kind
            == .service)
    }

    @Test func theAddHintQuotesTheTypedKeyword() {
        let input = Input(query: PluginQuery(query: "add", fullQuery: "todo add", now: now,
                                             timeZoneIdentifier: "UTC", maxResults: 50),
                          snapshot: RemindersSnapshot(access: .fullAccess, reminders: [], truncated: false,
                                                      defaultListName: "Inbox"))
        #expect(respond(to: input).items[0].subtitle == "Type a title after todo add.")
    }

    @Test func reminderRowsCompleteOnTheSecondaryAction() {
        let response = respond(to: request(reminders: mixed))
        #expect(response.items[0].secondary == PluginAction(.service, "reminders.complete@1", payload: .object(["id": .string("overdue")])))
        #expect(response.items[0].subtitle?.hasSuffix(" · Inbox") == true)
    }

    @Test func aSearchWithNoMatchesOffersToAddIt() {
        let response = respond(to: request("call the plumber", reminders: mixed))
        #expect(response.items[0].title == "call the plumber")
        #expect(response.items[0].primary == PluginAction(.service, "reminders.create@1", payload: .object(["title": .string("call the plumber")])))
        #expect(response.items[0].subtitle == "No matches · Press Return to add to Inbox")
        #expect(respond(to: request("week zzz", reminders: mixed)).items[0].primary
            == PluginAction(.openApplication, "com.apple.reminders"))
    }

    @Test func requestAndResponseRoundTripWithUnixDates() throws {
        let input = request("all", reminders: mixed, truncated: true)
        let data = try PluginProtocol.encoder().encode(input)
        let decoded = try PluginProtocol.decoder().decode(Input.self, from: data)
        #expect(decoded.snapshot == input.snapshot)
        #expect(decoded.snapshot.reminders.first(where: { $0.id == "undated" })?.due == nil)
        let response = try PluginProtocol.decoder().decode(
            Output.self, from: PluginProtocol.encoder().encode(respond(to: decoded)))
        #expect(response.items.map(\.id) == respond(to: input).items.map(\.id))
    }
}
