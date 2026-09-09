import Foundation
import Testing
import CalendarPluginCore
import OddFrogPluginAPI
import OddFrogHostServicesAPI

struct CalendarProviderTests {
    private struct Input: Codable { var query: PluginQuery; var snapshot: CalendarSnapshot }
    private struct Output: Codable { var items: [PluginItem] }
    private func respond(to input: Input) -> Output { Output(items: CalendarProvider.respond(to: input.query, snapshot: input.snapshot)) }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-09-09T12:00:00Z") }

    private func request(_ query: String = "", events: [CalendarEvent] = [], access: CalendarSnapshot.Access = .fullAccess) -> Input {
        Input(query: PluginQuery(query: query, fullQuery: "cal " + query, now: now,
                                timeZoneIdentifier: "UTC", maxResults: 50), snapshot: CalendarSnapshot(access: access, events: events))
    }

    private func event(_ id: String, _ start: String, _ end: String, title: String = "Meeting", allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: date(start), end: date(end), allDay: allDay, calendarName: "Work")
    }

    @Test func todayIncludesOngoingAllDayAndMultidayButNotEndedOrTomorrow() {
        let events = [
            event("future", "2026-09-09T14:00:00Z", "2026-09-09T15:00:00Z"),
            event("ended", "2026-09-09T10:00:00Z", "2026-09-09T12:00:00Z"),
            event("ongoing", "2026-09-09T11:00:00Z", "2026-09-09T13:00:00Z"),
            event("all-day", "2026-09-09T00:00:00Z", "2026-09-10T00:00:00Z", allDay: true),
            event("multi", "2026-09-08T00:00:00Z", "2026-09-10T00:00:00Z", allDay: true),
            event("tomorrow", "2026-09-10T00:00:00Z", "2026-09-10T01:00:00Z"),
        ]
        let response = respond(to: request(events: events))
        #expect(response.items.map(\.id) == ["multi", "all-day", "ongoing", "future"])
        #expect(response.items[1].subtitle?.contains("All day") == true)
        #expect(response.items.last?.primary == PluginAction(.openApplication, "com.apple.iCal"))
    }

    @Test func blankTitlesBecomeUntitled() {
        let events = [
            event("blank", "2026-09-09T14:00:00Z", "2026-09-09T15:00:00Z", title: " \n"),
            event("padded", "2026-09-09T16:00:00Z", "2026-09-09T17:00:00Z", title: "  Flight  "),
        ]
        #expect(respond(to: request(events: events)).items.map(\.title) == ["Untitled event", "Flight"])
    }

    @Test func tomorrowAndSearchRangesAreBounded() {
        for (query, start, end) in [
            ("", "2026-09-09T00:00:00Z", "2026-09-10T00:00:00Z"),
            ("tomorrow", "2026-09-10T00:00:00Z", "2026-09-11T00:00:00Z"),
            ("week design", "2026-09-09T00:00:00Z", "2026-09-16T00:00:00Z"),
            ("design", "2026-09-09T00:00:00Z", "2026-10-09T00:00:00Z"),
            ("12d", "2026-09-09T00:00:00Z", "2026-09-21T00:00:00Z"),
            ("3d design", "2026-09-09T00:00:00Z", "2026-09-12T00:00:00Z"),
            ("90d", "2026-09-09T00:00:00Z", "2026-10-09T00:00:00Z"),
            ("0d", "2026-09-09T00:00:00Z", "2026-10-09T00:00:00Z"),
        ] {
            let input = request(query)
            #expect(CalendarProvider.range(for: input.query) == CalendarRange(start: date(start), end: date(end)))
        }
    }

    @Test func rangesUseLocalMidnightAcrossDST() {
        let input = PluginQuery(query: "tomorrow", fullQuery: "cal tomorrow", now: date("2026-03-07T18:00:00Z"),
                                  timeZoneIdentifier: "America/New_York")
        let range = CalendarProvider.range(for: input)
        #expect(range.start == date("2026-03-08T05:00:00Z"))
        #expect(range.end == date("2026-03-09T04:00:00Z"))
        #expect(range.isValid(relativeTo: input.now))
    }

    @Test func searchMatchesTitleCalendarAndLocationAndRespectsRange() {
        var location = event("location", "2026-09-12T14:00:00Z", "2026-09-12T15:00:00Z")
        location.location = "Design studio"
        let title = event("title", "2026-09-10T14:00:00Z", "2026-09-10T15:00:00Z", title: "Design review")
        let tooLate = event("late", "2026-10-10T14:00:00Z", "2026-10-10T15:00:00Z", title: "Design review")
        let events = [location, title, tooLate]
        #expect(respond(to: request("DESIGN", events: events)).items.map(\.id) == ["title", "location"])
        #expect(respond(to: request("tomorrow work", events: events)).items.map(\.id) == ["title"])
    }

    @Test func permissionAndEmptyStatesHaveIntentionalActions() {
        for access in [CalendarSnapshot.Access.notDetermined, .writeOnly] {
            #expect(respond(to: request(access: access)).items.first?.primary?.kind == .service)
        }
        #expect(respond(to: request(access: .denied)).items.first?.primary?.kind == .openURL)
        #expect(respond(to: request(access: .restricted)).items.first?.primary == nil)
        #expect(respond(to: request()).items.first?.title == "No more events today")
        #expect(respond(to: request("12d")).items.first?.title == "No more events in the next 12 days")
        #expect(respond(to: request("12d design")).items.first?.title == "No matching events in the next 12 days")
    }

    @Test func onlyRecognizedHTTPSMeetingHostsBecomeJoinActions() {
        var event = event("join", "2026-09-09T14:00:00Z", "2026-09-09T15:00:00Z")
        for text in ["https://zoom.us.evil.example/j/123", "https://evilzoom.us/j/123", "http://zoom.us/j/123", "https://example.com"] {
            event.url = text
            #expect(CalendarProvider.meetingURL(event) == nil)
        }
        event.url = nil
        event.location = "Join: https://us02web.zoom.us/j/123"
        #expect(CalendarProvider.meetingURL(event)?.host == "us02web.zoom.us")
        let item = respond(to: request(events: [event])).items[0]
        #expect(item.secondary?.value == "https://us02web.zoom.us/j/123")
    }

    @Test func requestAndResponseRoundTripWithUnixDates() throws {
        let input = request("tomorrow")
        let encoded = try PluginProtocol.encoder().encode(input)
        let decoded = try PluginProtocol.decoder().decode(Input.self, from: encoded)
        #expect(decoded.query.now == input.query.now)
        #expect(decoded.snapshot == input.snapshot)
        let response = respond(to: input)
        let output = try PluginProtocol.encoder().encode(response)
        #expect(try PluginProtocol.decoder().decode(Output.self, from: output).items == response.items)
    }
}
