import Foundation
import OddFrogPluginAPI

public enum ChatProvider {
    public static func respond(to request: PluginQuery, conversations: [Conversation]) -> [PluginItem] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .gmt
        let filter = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = filter.isEmpty ? conversations : conversations.filter { conversation in
            if conversation.title.localizedStandardContains(filter) {
                return true
            }
            return conversation.messages.contains { $0.text.localizedStandardContains(filter) }
        }
        let cap = max(1, min(request.maxResults, 50))
        let rows = matches.prefix(cap > 1 ? cap - 1 : 0).map { conversation in
            let details = [dateLabel(conversation.modified, calendar: calendar, now: request.now),
                           "\(conversation.messages.count) messages"]
            return PluginItem(id: conversation.id, title: conversation.title,
                              subtitle: details.joined(separator: " · "), kind: "Chat",
                              symbol: "bubble.left.and.bubble.right",
                              primary: PluginAction(.callback, "open", payload: .object(["id": .string(conversation.id)])),
                              secondary: PluginAction(.callback, "delete", payload: .object(["id": .string(conversation.id)])))
        }
        return rows + [creation(filter)]
    }

    public static func view(for conversation: Conversation, prompt: String? = nil) -> PluginView {
        PluginView(id: conversation.id, title: conversation.title, messages: conversation.messages,
                   placeholder: "Message…", prompt: prompt,
                   send: PluginAction(.callback, "send", payload: .object(["id": .string(conversation.id)])))
    }

    private static func creation(_ filter: String) -> PluginItem {
        guard !filter.isEmpty else {
            return PluginItem(id: "new", title: "New chat", subtitle: "Press Return to start a conversation.",
                              kind: "Chat", symbol: "plus.bubble",
                              primary: PluginAction(.callback, "create", payload: .object([:])))
        }
        return PluginItem(id: "new", title: "Ask “\(filter)”", subtitle: "Press Return to send this message.",
                          kind: "Chat", symbol: "plus.bubble",
                          primary: PluginAction(.callback, "create", payload: .object(["text": .string(filter)])))
    }

    private static func dateLabel(_ modified: Date, calendar: Calendar, now: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: modified),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 || days == 1 {
            let time = DateFormatter()
            time.timeZone = calendar.timeZone
            time.dateStyle = .none
            time.timeStyle = .short
            return "\(days == 0 ? "Today" : "Yesterday") \(time.string(from: modified))"
        }
        let date = DateFormatter()
        date.timeZone = calendar.timeZone
        date.dateFormat = "EEE d MMM"
        return date.string(from: modified)
    }
}
