import Foundation
import OddFrogPluginAPI

public enum RemindersProvider {
    public static func respond(to request: PluginRequest) -> PluginResponse {
        if request.operation == .prepare {
            return PluginResponse(id: request.id, remindersRequest: RemindersScope(limit: 2000))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .gmt
        let day = calendar.startOfDay(for: request.now)
        let words = request.query.split(whereSeparator: { $0.isWhitespace })
        let word = words.first?.lowercased() ?? ""
        let explicitDays = dayCount(word)
        let adding = ["add", "new"].contains(word)
        let hasRange = words.isEmpty || explicitDays != nil || ["today", "tomorrow", "week", "all"].contains(word)
        let filter = (hasRange ? words.dropFirst() : words[...]).joined(separator: " ")
        let days = explicitDays ?? (word == "week" ? 7 : 1)
        let unbounded = word == "all" || (!words.isEmpty && !hasRange)
        let start = calendar.date(byAdding: .day, value: 1, to: day)!
        let end = calendar.date(byAdding: .day, value: word == "tomorrow" ? 2 : days, to: day)!
        guard let snapshot = request.reminders else {
            return response(request, title: "Reminders unavailable", subtitle: "The host did not supply reminders data.")
        }
        switch snapshot.access {
        case .notDetermined, .writeOnly:
            return response(request, title: "Allow Reminders access", subtitle: "Press Return to let Odd Frog read your reminders.",
                            action: PluginAction(.requestRemindersAccess))
        case .denied:
            return response(request, title: "Reminders access is off", subtitle: "Press Return to open Reminders privacy settings.",
                            action: PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"))
        case .restricted:
            return response(request, title: "Reminders access is restricted", subtitle: "Your Mac's restrictions prevent reading reminders.")
        case .fullAccess: break
        }
        if adding {
            let title = words.dropFirst().joined(separator: " ")
            guard !title.isEmpty else {
                return response(request, title: "Add a reminder", subtitle: "Type a title after rem add.")
            }
            return PluginResponse(id: request.id, items: [addItem(title, list: snapshot.defaultListName, prefix: "")])
        }
        let matches = snapshot.reminders.filter { item in
            guard filter.isEmpty || [item.title, item.listName].contains(where: { $0.localizedStandardContains(filter) }) else {
                return false
            }
            if unbounded { return true }
            guard let due = item.due else { return false }
            if word == "tomorrow" { return due >= start && due < end }
            return due < end
        }.sorted(by: precedes)
        let openReminders = PluginAction(.openApplication, "com.apple.reminders")
        let items = matches.prefix(max(1, min(request.maxResults, 50))).map { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = [dateLabel(item, calendar: calendar, now: request.now), item.listName,
                           (1...4).contains(item.priority) ? "High priority" : ""].filter { !$0.isEmpty }
            return PluginItem(id: item.id, title: title.isEmpty ? "Untitled reminder" : title,
                              subtitle: (details + ["⌘↩ Complete"]).joined(separator: " · "), kind: "Reminder",
                              symbol: "checklist", primary: openReminders,
                              secondary: PluginAction(.completeReminder, item.id))
        }
        if items.isEmpty {
            if !hasRange, !filter.isEmpty {
                return PluginResponse(id: request.id,
                                      items: [addItem(filter, list: snapshot.defaultListName, prefix: "No matches · ")])
            }
            let period = word == "tomorrow" ? "due tomorrow"
                : (unbounded ? "" : (days == 1 ? "due today" : "due in the next \(days) days"))
            let subject = filter.isEmpty ? "No reminders" : "No matching reminders"
            let title = period.isEmpty ? subject : "\(subject) \(period)"
            return response(request, title: title + (snapshot.truncated ? " (list truncated)" : ""),
                            subtitle: "Press Return to open Reminders.", action: openReminders)
        }
        return PluginResponse(id: request.id, items: items)
    }

    private static func addItem(_ title: String, list: String?, prefix: String) -> PluginItem {
        let destination = list.map { "Press Return to add to \($0)" } ?? "Press Return to add a reminder"
        return PluginItem(id: "add", title: title, subtitle: prefix + destination, kind: "Reminder",
                          symbol: "plus.circle", primary: PluginAction(.createReminder, title))
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

    private static func dayCount(_ word: String) -> Int? {
        guard word.hasSuffix("d"), let value = Int(word.dropLast()), value > 0 else { return nil }
        return min(value, 30)
    }

    private static func response(_ request: PluginRequest, title: String, subtitle: String,
                                 action: PluginAction? = nil) -> PluginResponse {
        PluginResponse(id: request.id, items: [PluginItem(id: "status", title: title, subtitle: subtitle,
                                                          kind: "Reminder", symbol: "checklist", primary: action)])
    }

    private static func dateLabel(_ item: ReminderItem, calendar: Calendar, now: Date) -> String {
        guard let due = item.due else { return "No date" }
        let date = DateFormatter()
        date.timeZone = calendar.timeZone
        date.dateFormat = "EEE d MMM"
        let time = DateFormatter()
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        let stamp = item.allDay ? date.string(from: due) : "\(date.string(from: due)) \(time.string(from: due))"
        let limit = item.allDay ? calendar.startOfDay(for: now) : now
        return due < limit ? "Overdue · \(stamp)" : stamp
    }
}
