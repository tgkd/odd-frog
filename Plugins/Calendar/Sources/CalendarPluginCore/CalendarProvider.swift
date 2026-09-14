import Foundation
import OddFrogPluginAPI
import OddFrogHostServicesAPI

public enum CalendarProvider {
    private struct Agenda {
        let calendar: Calendar
        let start: Date
        let end: Date
        let filter: String
        let first: String
        let days: Int
        let bare: Bool
    }

    public static func range(for request: PluginQuery) -> CalendarRange {
        let agenda = agenda(for: request)
        return CalendarRange(start: agenda.start, end: agenda.end)
    }

    public static func isMonthRequest(_ request: PluginQuery) -> Bool {
        request.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "month"
    }

    public static func monthItem() -> PluginItem {
        PluginItem(id: "show-month", title: "Show month", subtitle: "Open a month calendar · cal month",
                   kind: "Calendar", symbol: "calendar", primary: PluginAction(.callback, "month"))
    }

    public static func monthView() -> PluginView {
        PluginView(month: "month", title: "Calendar")
    }

    public static func respond(to request: PluginQuery, snapshot: CalendarSnapshot) -> [PluginItem] {
        let agenda = agenda(for: request)
        let cap = max(1, min(request.maxResults, 50))
        let reserved = agenda.bare && cap >= 2
        let rows = agendaRows(request, agenda: agenda, snapshot: snapshot, limit: reserved ? cap - 1 : cap)
        if reserved {
            return rows + [monthItem()]
        }
        return rows
    }

    private static func agenda(for request: PluginQuery) -> Agenda {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .gmt
        let day = calendar.startOfDay(for: request.now)
        let words = request.query.split(whereSeparator: { $0.isWhitespace })
        let first = words.first?.lowercased() ?? ""
        let explicitDays = dayCount(first)
        let hasRange = explicitDays != nil || ["today", "tomorrow", "week"].contains(first)
        let filter = (hasRange ? words.dropFirst() : words[...]).joined(separator: " ")
        let offset = first == "tomorrow" ? 1 : 0
        let days = explicitDays ?? (first == "week" ? 7 : (hasRange || words.isEmpty ? 1 : 30))
        let start = calendar.date(byAdding: .day, value: offset, to: day)!
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        return Agenda(calendar: calendar, start: start, end: end, filter: filter, first: first, days: days,
                      bare: words.isEmpty)
    }

    private static func agendaRows(_ request: PluginQuery, agenda: Agenda, snapshot: CalendarSnapshot,
                                   limit: Int) -> [PluginItem] {
        let calendar = agenda.calendar, start = agenda.start, end = agenda.end
        let filter = agenda.filter, first = agenda.first, days = agenda.days
        switch snapshot.access {
        case .notDetermined, .writeOnly:
            return response(request, title: "Allow Calendar access", subtitle: "Press Return to let Odd Frog read your events.",
                            action: PluginAction(.service, "calendar.access@1"))
        case .denied:
            return response(request, title: "Calendar access is off", subtitle: "Press Return to open Calendar privacy settings.",
                            action: PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"))
        case .restricted:
            return response(request, title: "Calendar access is restricted", subtitle: "Your Mac's restrictions prevent reading events.")
        case .fullAccess: break
        }
        let matches = snapshot.events.filter { event in
            // Interval overlap includes ongoing, multi-day, and all-day events. Midnight end is exclusive.
            event.start < end && event.end > max(start, request.now)
                && (filter.isEmpty || [event.title, event.calendarName, event.location].contains {
                    $0.localizedStandardContains(filter)
                })
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
        let openCalendar = PluginAction(.openApplication, "com.apple.iCal")
        let items = matches.prefix(limit).map { event in
            let time = timeLabel(event, calendar: calendar)
            let details = [time, event.calendarName, event.location].filter { !$0.isEmpty }.joined(separator: " · ")
            let meeting = meetingURL(event).map { PluginAction(.openURL, $0.absoluteString) }
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return PluginItem(id: event.id, title: title.isEmpty ? "Untitled event" : title,
                              subtitle: details + (meeting == nil ? "" : " · ⌘↩ Join"), kind: "Calendar",
                              symbol: "calendar", primary: openCalendar, secondary: meeting)
        }
        if items.isEmpty {
            let period = first == "tomorrow" ? "tomorrow" : (days == 1 ? "today" : "in the next \(days) days")
            return response(request, title: filter.isEmpty ? "No more events \(period)" : "No matching events \(period)",
                            subtitle: "Press Return to open Calendar.", action: openCalendar)
        }
        return items
    }

    private static func dayCount(_ word: String) -> Int? {
        guard word.hasSuffix("d"), let value = Int(word.dropLast()), value > 0 else { return nil }
        return min(value, 30)
    }

    private static func response(_ request: PluginQuery, title: String, subtitle: String,
                                 action: PluginAction? = nil) -> [PluginItem] {
        [PluginItem(id: "status", title: title, subtitle: subtitle,
                                                         kind: "Calendar", symbol: "calendar", primary: action)]
    }

    private static func timeLabel(_ event: CalendarEvent, calendar: Calendar) -> String {
        let date = DateFormatter()
        date.timeZone = calendar.timeZone
        date.dateFormat = "EEE d MMM"
        let time = DateFormatter()
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        if event.allDay { return "\(date.string(from: event.start)) · All day" }
        let end = calendar.isDate(event.start, inSameDayAs: event.end)
            ? time.string(from: event.end)
            : "\(date.string(from: event.end)) \(time.string(from: event.end))"
        return "\(date.string(from: event.start)) · \(time.string(from: event.start))–\(end)"
    }

    /// Only recognized HTTPS meeting hosts become join actions; ordinary event links stay ordinary data.
    public static func meetingURL(_ event: CalendarEvent) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let candidates = [event.url, event.location].compactMap { $0 }.flatMap { text in
            detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url) ?? []
        }
        let hosts = ["zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
        return candidates.first { url in
            guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
