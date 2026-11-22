import Foundation
import Testing
import NotesPluginCore
import OddFrogCore
import OddFrogPluginAPI

@MainActor struct NotesHandlerTests {
    private func existing() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func operation(_ root: URL) -> ProviderOperation {
        let registry = HostServiceRegistry()
        NotesService(directory: root).register(in: registry)
        let context = HostServiceRegistry.Context(pluginID: "notes", generation: UUID(), activated: true)
        let declared = ["notes.read@1", "notes.get@1", "notes.write@1"]
        return ProviderOperation(id: "test", service: { capability, params in
            try await registry.invoke(capability, params: params, context: context, declared: declared)
        }, emit: { _, _ in })
    }

    private func activation(_ actionID: String, payload: JSONValue = .object([:]), text: String? = nil) -> PluginActivation {
        PluginActivation(actionID: actionID, payload: payload,
                         item: PluginItem(id: "new", title: "New note"), argument: nil, text: text)
    }

    private func params(_ input: PluginActivation) throws -> JSONValue {
        .object(["apiVersion": .number(2), "context": try .encode(PluginContext()), "input": try .encode(input)])
    }

    @Test func blankDraftsLeaveNoFileButRealEditsAreSaved() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = NotesHandler()
        let created = try await handler.handle("activate", params: params(activation("create")),
                                               operation: operation(root)).decode(PluginEffects.self)
        let view = try #require(created.view)
        #expect(view.title == "New note")
        #expect(view.text == "")
        #expect(UUID(uuidString: view.id) != nil)
        let blank = try await handler.handle(
            "activate", params: params(activation("save", payload: .object(["id": .string(view.id)]), text: "  \n ")), operation: operation(root)).decode(PluginEffects.self)
        #expect(blank.refreshQuery == false)
        #expect(blank.view?.title == "New note")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let saved = try await handler.handle(
            "activate", params: params(activation("save", payload: .object(["id": .string(view.id)]), text: "Kept\nbody")), operation: operation(root)).decode(PluginEffects.self)
        #expect(saved.refreshQuery)
        #expect(saved.view?.title == "Kept")
        #expect(try NoteStore(directory: root).list().map(\.text) == ["Kept\nbody"])
    }

    @Test func createPrefillsFromThePayloadAndQueriesListTheNote() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = NotesHandler()
        let created = try await handler.handle(
            "activate", params: params(activation("create", payload: .object(["text": .string("milk")]))),
            operation: operation(root)).decode(PluginEffects.self)
        let view = try #require(created.view)
        #expect(view.text == "milk")
        #expect(view.title == "milk")
        _ = try await handler.handle(
            "activate", params: params(activation("save", payload: .object(["id": .string(view.id)]), text: "milk")), operation: operation(root))
        let query = PluginQuery(query: "milk", fullQuery: "note milk", timeZoneIdentifier: "UTC", maxResults: 8)
        let items = try await handler.handle(
            "query", params: .object(["apiVersion": .number(2), "context": try .encode(PluginContext()),
                                      "input": try .encode(query)]),
            operation: operation(root)).decode([PluginItem].self)
        #expect(items.map(\.title) == ["milk", "New note “milk”"])
        let opened = try await handler.handle(
            "activate", params: params(activation("open", payload: .object(["id": .string(view.id)]))),
            operation: operation(root)).decode(PluginEffects.self)
        #expect(opened.view?.text == "milk")
    }

    @Test func unknownActionsAndMethodsAreRejected() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = NotesHandler()
        await #expect(throws: RPCError("notes", "This note no longer exists.")) {
            try await handler.handle("activate",
                                     params: params(activation("open", payload: .object(["id": .string(UUID().uuidString.lowercased())]))),
                                     operation: operation(root))
        }
        await #expect(throws: RPCError("params", "A note ID is required.")) {
            try await handler.handle("activate", params: params(activation("open")), operation: operation(root))
        }
        await #expect(throws: RPCError("params", "Invalid note ID.")) {
            try await handler.handle("activate",
                                     params: params(activation("open", payload: .object(["id": .string("../escape")]))),
                                     operation: operation(root))
        }
        await #expect(throws: RPCError("action", "Unknown action: delete")) {
            try await handler.handle("activate", params: params(activation("delete")), operation: operation(root))
        }
        await #expect(throws: RPCError("method", "Unsupported method: catalog")) {
            try await handler.handle("catalog", params: .object([:]), operation: operation(root))
        }
        #expect(try await handler.handle("initialize", params: .object([:]), operation: operation(root)) == .object(["apiVersion": .number(2)]))
        #expect(try await handler.handle("settings", params: .object([:]), operation: operation(root)) == .object([:]))
    }
}
