import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

private actor FakeBackend: ChatBackend {
    private let chunks: [String]
    private let failure: RPCError?
    private(set) var lastRequest: ChatRequest?
    private(set) var calls = 0
    init(chunks: [String] = [], failure: RPCError? = nil) {
        self.chunks = chunks
        self.failure = failure
    }
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error> {
        lastRequest = request
        calls += 1
        if let failure {
            throw failure
        }
        let values = chunks
        return AsyncThrowingStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}

private struct Event: Sendable {
    let method: String
    let params: JSONValue
}

private actor Recorder {
    private(set) var events: [Event] = []
    func record(_ method: String, _ params: JSONValue) {
        events.append(Event(method: method, params: params))
    }
}

struct ChatHandlerTests {
    private func existing() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("odd-frog-chat-handler-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func operation(_ recorder: Recorder) -> ProviderOperation {
        ProviderOperation(id: "test", service: { _, _ in throw RPCError("test", "No host services.") },
                          emit: { method, params in await recorder.record(method, params) })
    }

    private func activation(_ actionID: String, payload: JSONValue = .object([:]), text: String? = nil) -> PluginActivation {
        PluginActivation(actionID: actionID, payload: payload,
                         item: PluginItem(id: "new", title: "New chat"), argument: nil, text: text)
    }

    private func settings(baseURL: String = "http://localhost:11434/v1", model: String = "llama3.2",
                          systemPrompt: String = "Be brief.") -> [String: JSONValue] {
        ["base_url": .string(baseURL), "api_key": .string(""), "model": .string(model),
         "system_prompt": .string(systemPrompt)]
    }

    private func params(_ input: PluginActivation, storage: URL,
                        settings values: [String: JSONValue]? = nil) throws -> JSONValue {
        .object(["apiVersion": .number(2),
                 "context": try .encode(PluginContext(settings: values ?? settings(), storagePath: storage.path)),
                 "input": try .encode(input)])
    }

    @Test func createReturnsADraftViewAndWritesNothing() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ChatHandler(backend: FakeBackend())
        let created = try await handler.handle(
            "activate", params: params(activation("create", payload: .object(["text": .string("hi")])), storage: root),
            operation: operation(Recorder())).decode(PluginEffects.self)
        let view = try #require(created.view)
        #expect(view.kind == .chat)
        #expect(view.title == "New chat")
        #expect(view.messages == [])
        #expect(view.prompt == "hi")
        #expect(view.placeholder == "Message…")
        #expect(view.send == PluginAction(.callback, "send", payload: .object(["id": .string(view.id)])))
        #expect(UUID(uuidString: view.id) != nil)
        #expect(created.refreshQuery == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func sendStreamsDeltasThenPersistsTheConversation() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let backend = FakeBackend(chunks: ["Hel", "lo"])
        let handler = ChatHandler(backend: backend)
        let recorder = Recorder()
        let created = try await handler.handle(
            "activate", params: params(activation("create", payload: .object(["text": .string("hi")])), storage: root),
            operation: operation(recorder)).decode(PluginEffects.self)
        let id = try #require(created.view?.id)
        let sent = try await handler.handle(
            "activate", params: params(activation("send", payload: .object(["id": .string(id)]), text: " hi "), storage: root),
            operation: operation(recorder)).decode(PluginEffects.self)
        let events = await recorder.events
        #expect(events.map(\.method) == ["messageDelta", "messageDelta"])
        let deltas = try events.map { try $0.params.decode(PluginMessageDelta.self) }
        #expect(deltas.map(\.delta) == ["Hel", "lo"])
        #expect(deltas.allSatisfy { $0.viewID == id })
        #expect(Set(deltas.map(\.messageID)).count == 1)
        #expect(sent.refreshQuery)
        let view = try #require(sent.view)
        #expect(view.id == id)
        #expect(view.title == "hi")
        #expect(view.messages?.map(\.role) == [.user, .assistant])
        #expect(view.messages?.map(\.text) == ["hi", "Hello"])
        #expect(view.messages?.last?.id == deltas.first?.messageID)
        let request = try #require(await backend.lastRequest)
        #expect(request.model == "llama3.2")
        #expect(request.systemPrompt == "Be brief.")
        #expect(request.apiKey == "")
        #expect(request.baseURL.absoluteString == "http://localhost:11434/v1")
        #expect(request.messages.map(\.text) == ["hi"])
        let stored = try ConversationStore(directory: root).list()
        #expect(stored.map(\.id) == [id])
        #expect(stored.first?.title == "hi")
        #expect(stored.first?.messages.map(\.text) == ["hi", "Hello"])
        let listed = try await handler.handle(
            "query", params: .object(["apiVersion": .number(2),
                                      "context": try .encode(PluginContext(storagePath: root.path)),
                                      "input": try .encode(PluginQuery(query: "", fullQuery: "chat"))]),
            operation: operation(recorder)).decode([PluginItem].self)
        #expect(listed.map(\.title) == ["hi", "New chat"])
    }

    @Test func aFailingBackendPropagatesAndLeavesNoFile() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ChatHandler(backend: FakeBackend(failure: RPCError("chat", "Connection refused.")))
        let recorder = Recorder()
        let created = try await handler.handle(
            "activate", params: params(activation("create"), storage: root),
            operation: operation(recorder)).decode(PluginEffects.self)
        let id = try #require(created.view?.id)
        await #expect(throws: RPCError("chat", "Connection refused.")) {
            try await handler.handle(
                "activate", params: params(activation("send", payload: .object(["id": .string(id)]), text: "hi"), storage: root),
                operation: operation(recorder))
        }
        #expect(await recorder.events.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func emptyTextUnknownConversationsAndBadSettingsAreRejected() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let backend = FakeBackend(chunks: ["Hello"])
        let handler = ChatHandler(backend: backend)
        let recorder = Recorder()
        let created = try await handler.handle(
            "activate", params: params(activation("create"), storage: root),
            operation: operation(recorder)).decode(PluginEffects.self)
        let id = try #require(created.view?.id)
        await #expect(throws: RPCError("params", "Nothing to send.")) {
            try await handler.handle(
                "activate", params: params(activation("send", payload: .object(["id": .string(id)]), text: "  \n "), storage: root),
                operation: operation(recorder))
        }
        await #expect(throws: RPCError("chat", "This conversation no longer exists.")) {
            try await handler.handle(
                "activate",
                params: params(activation("send", payload: .object(["id": .string(UUID().uuidString.lowercased())]), text: "hi"),
                               storage: root),
                operation: operation(recorder))
        }
        await #expect(throws: RPCError("chat", "Set a valid API base URL in Chat settings.")) {
            try await handler.handle(
                "activate",
                params: params(activation("send", payload: .object(["id": .string(id)]), text: "hi"), storage: root,
                               settings: settings(baseURL: "not a url")),
                operation: operation(recorder))
        }
        await #expect(throws: RPCError("chat", "Set a model name in Chat settings.")) {
            try await handler.handle(
                "activate",
                params: params(activation("send", payload: .object(["id": .string(id)]), text: "hi"), storage: root,
                               settings: settings(model: "  ")),
                operation: operation(recorder))
        }
        #expect(await backend.calls == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func openDeleteAndUnknownMethodsBehaveAsDocumented() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ChatHandler(backend: FakeBackend(chunks: ["Hello"]))
        let recorder = Recorder()
        let store = ConversationStore(directory: root)
        let id = store.newID()
        try store.write(Conversation(id: id, title: "Alpha", created: Date(), modified: Date(),
                                     messages: [PluginMessage(id: "m0", role: .user, text: "hi")]))
        let opened = try await handler.handle(
            "activate", params: params(activation("open", payload: .object(["id": .string(id)])), storage: root),
            operation: operation(recorder)).decode(PluginEffects.self)
        #expect(opened.view?.title == "Alpha")
        #expect(opened.view?.messages?.map(\.text) == ["hi"])
        #expect(opened.view?.prompt == nil)
        let deleted = try await handler.handle(
            "activate", params: params(activation("delete", payload: .object(["id": .string(id)])), storage: root),
            operation: operation(recorder)).decode(PluginEffects.self)
        #expect(deleted.notification == "Conversation deleted.")
        #expect(deleted.refreshQuery)
        #expect(try store.list().isEmpty)
        await #expect(throws: RPCError("params", "A conversation ID is required.")) {
            try await handler.handle("activate", params: params(activation("open"), storage: root),
                                     operation: operation(recorder))
        }
        await #expect(throws: RPCError("action", "Unknown action: archive")) {
            try await handler.handle("activate", params: params(activation("archive"), storage: root),
                                     operation: operation(recorder))
        }
        await #expect(throws: RPCError("method", "Unsupported method: catalog")) {
            try await handler.handle("catalog", params: .object([:]), operation: operation(recorder))
        }
        #expect(try await handler.handle("initialize", params: .object([:]), operation: operation(recorder))
                == .object(["apiVersion": .number(2)]))
        #expect(try await handler.handle("settings", params: .object([:]), operation: operation(recorder)) == .object([:]))
    }
}
