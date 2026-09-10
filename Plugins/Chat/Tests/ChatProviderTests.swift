import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

struct ChatProviderTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var now: Date { date("2026-09-09T12:00:00Z") }

    private func request(_ query: String = "", maxResults: Int = 50) -> PluginQuery {
        PluginQuery(query: query, fullQuery: "chat " + query, now: now,
                    timeZoneIdentifier: "UTC", maxResults: maxResults)
    }

    private func conversation(_ id: String, _ title: String, messages: [String] = [],
                              modified: String = "2026-09-09T11:00:00Z") -> Conversation {
        let values = messages.enumerated().map { index, text in
            PluginMessage(id: "\(id)-\(index)", role: index.isMultiple(of: 2) ? .user : .assistant, text: text)
        }
        return Conversation(id: id, title: title, created: date("2026-09-01T08:00:00Z"),
                            modified: date(modified), messages: values)
    }

    @Test func emptyQueryListsEveryConversationAndEndsWithTheCreationRow() {
        let items = ChatProvider.respond(to: request(), conversations: [
            conversation("a", "Alpha", messages: ["hi", "hello"], modified: "2026-09-09T11:00:00Z"),
            conversation("b", "Beta", modified: "2026-09-08T22:00:00Z"),
            conversation("c", "Gamma", modified: "2026-09-01T08:00:00Z"),
        ])
        #expect(items.map(\.id) == ["a", "b", "c", "new"])
        #expect(items[0].title == "Alpha")
        #expect(items[0].kind == "Chat")
        #expect(items[0].symbol == "bubble.left.and.bubble.right")
        #expect(items[0].subtitle?.hasPrefix("Today ") == true)
        #expect(items[0].subtitle?.hasSuffix(" · 2 messages") == true)
        #expect(items[1].subtitle?.hasPrefix("Yesterday ") == true)
        #expect(items[2].subtitle == "Tue 1 Sep · 0 messages")
        #expect(items[0].primary == PluginAction(.callback, "open", payload: .object(["id": .string("a")])))
        #expect(items[0].secondary == PluginAction(.callback, "delete", payload: .object(["id": .string("a")])))
        #expect(items[3].title == "New chat")
        #expect(items[3].subtitle == "Press Return to start a conversation.")
        #expect(items[3].symbol == "plus.bubble")
        #expect(items[3].kind == "Chat")
        #expect(items[3].primary == PluginAction(.callback, "create", payload: .object([:])))
        #expect(items[3].secondary == nil)
    }

    @Test func filtersMatchTitlesAndMessageBodiesCaseInsensitively() {
        let conversations = [conversation("groceries", "Shopping list", messages: ["milk and eggs", "noted"]),
                             conversation("meeting", "Budget review", messages: ["what is the plan"])]
        #expect(ChatProvider.respond(to: request("MILK"), conversations: conversations).map(\.id) == ["groceries", "new"])
        #expect(ChatProvider.respond(to: request("budget"), conversations: conversations).map(\.id) == ["meeting", "new"])
        #expect(ChatProvider.respond(to: request("zzz"), conversations: conversations).map(\.id) == ["new"])
        let items = ChatProvider.respond(to: request("  what is the plan  "), conversations: conversations)
        #expect(items.map(\.id) == ["meeting", "new"])
        #expect(items[1].title == "Ask “what is the plan”")
        #expect(items[1].subtitle == "Press Return to send this message.")
        #expect(items[1].primary == PluginAction(.callback, "create",
                                                 payload: .object(["text": .string("what is the plan")])))
    }

    @Test func capsAlwaysLeaveRoomForTheCreationRow() {
        let five = (0..<5).map { conversation("c\($0)", "Chat \($0)") }
        #expect(ChatProvider.respond(to: request(maxResults: 3), conversations: five).map(\.id) == ["c0", "c1", "new"])
        #expect(ChatProvider.respond(to: request(maxResults: 1), conversations: five).map(\.id) == ["new"])
        let many = (0..<60).map { conversation("c\($0)", "Chat \($0)") }
        let items = ChatProvider.respond(to: request(maxResults: 50), conversations: many)
        #expect(items.count == 50)
        #expect(items.dropLast().map(\.id) == (0..<49).map { "c\($0)" })
        #expect(items.last?.id == "new")
    }

    @Test func viewCarriesTheTranscriptAndASendCallback() {
        let value = conversation("a", "Alpha", messages: ["hi", "hello"])
        let view = ChatProvider.view(for: value)
        #expect(view.kind == .chat)
        #expect(view.id == "a")
        #expect(view.title == "Alpha")
        #expect(view.messages == value.messages)
        #expect(view.placeholder == "Message…")
        #expect(view.prompt == nil)
        #expect(view.save == nil)
        #expect(view.send == PluginAction(.callback, "send", payload: .object(["id": .string("a")])))
        #expect(ChatProvider.view(for: value, prompt: "hi there").prompt == "hi there")
    }

    @Test func titlesFallBackCollapseWhitespaceAndTruncate() {
        #expect(Conversation.title(from: "   \n\t  \n") == "New chat")
        #expect(Conversation.title(from: "") == "New chat")
        #expect(Conversation.title(from: "\n\n  Second   line  title  \nbody") == "Second line title")
        #expect(Conversation.title(from: String(repeating: "x", count: 100)) == String(repeating: "x", count: 60))
    }

    @Test func effectsWithAChatViewRoundTrip() throws {
        let value = conversation("a", "Alpha", messages: ["hi", "hello"])
        let effects = PluginEffects(refreshQuery: true, view: ChatProvider.view(for: value, prompt: "next"))
        let decoded = try JSONValue.encode(effects).decode(PluginEffects.self)
        #expect(decoded.refreshQuery)
        #expect(decoded.view == effects.view)
        let items = ChatProvider.respond(to: request(), conversations: [value])
        #expect(try JSONValue.encode(items).decode([PluginItem].self) == items)
    }
}
