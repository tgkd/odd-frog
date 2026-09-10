import Foundation
import Testing
import NotesPluginCore
import OddFrogPluginAPI

struct NoteStoreTests {
    private func temp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-notes-\(UUID().uuidString)")
    }

    private func existing() throws -> URL {
        let root = temp()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private var operation: ProviderOperation {
        ProviderOperation(id: "test", service: { _, _ in throw RPCError("test", "No host services.") }, emit: { _ in })
    }

    private func activation(_ actionID: String, payload: JSONValue = .object([:]), text: String? = nil) -> PluginActivation {
        PluginActivation(actionID: actionID, payload: payload,
                         item: PluginItem(id: "new", title: "New note"), argument: nil, text: text)
    }

    private func params(_ input: PluginActivation, storage: URL) throws -> JSONValue {
        .object(["apiVersion": .number(2),
                 "context": try .encode(PluginContext(storagePath: storage.path)),
                 "input": try .encode(input)])
    }

    @Test func listCreatesTheDirectoryAndStartsEmpty() throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(directory: root)
        let notes = try store.list()
        #expect(notes.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func writeAndReadRoundTripText() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(directory: root)
        let id = store.newID()
        let written = try store.write(id: id, text: "Groceries\nmilk")
        #expect(written.id == id)
        #expect(written.text == "Groceries\nmilk")
        let read = try store.read(id: id)
        #expect(read.id == id)
        #expect(read.text == "Groceries\nmilk")
        #expect(try store.list().map(\.id) == [id])
        let updated = try store.write(id: id, text: "Groceries\nmilk and eggs")
        #expect(try store.read(id: id).text == updated.text)
        #expect(try store.list().count == 1)
    }

    @Test func listOrdersByModificationDateDescending() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(directory: root)
        let stamps = ["2026-09-01T08:00:00Z": "oldest", "2026-09-09T08:00:00Z": "newest", "2026-09-05T08:00:00Z": "middle"]
        var ids: [String: String] = [:]
        for (stamp, name) in stamps {
            let id = store.newID()
            _ = try store.write(id: id, text: name)
            let date = ISO8601DateFormatter().date(from: stamp)!
            try FileManager.default.setAttributes([.modificationDate: date],
                                                  ofItemAtPath: root.appendingPathComponent(id + ".txt").path)
            ids[name] = id
        }
        #expect(try store.list().map(\.text) == ["newest", "middle", "oldest"])
        #expect(try store.list().map(\.id) == ["newest", "middle", "oldest"].map { ids[$0]! })
    }

    @Test func foreignFilesAreIgnored() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(directory: root)
        let id = store.newID()
        _ = try store.write(id: id, text: "Kept")
        for name in ["notes.md", "not-a-uuid.txt", "\(store.newID()).md", "README"] {
            try Data("ignored".utf8).write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("\(store.newID()).txt"),
                                                withIntermediateDirectories: true)
        #expect(try store.list().map(\.id) == [id])
    }

    @Test func invalidIdentifiersNeverReachTheFilesystem() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(directory: root)
        for id in ["../x", "a/b", "not-a-uuid", "", "  "] {
            #expect(throws: RPCError("params", "Invalid note ID.")) { try store.read(id: id) }
            #expect(throws: RPCError("params", "Invalid note ID.")) { try store.write(id: id, text: "nope") }
            #expect(throws: RPCError("params", "Invalid note ID.")) { try store.exists(id: id) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func missingNotesAndEmptyTextAreDistinct() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(directory: root)
        let id = store.newID()
        #expect(throws: RPCError("notes", "This note no longer exists.")) { try store.read(id: id) }
        _ = try store.write(id: id, text: "")
        #expect(try store.exists(id: id))
        #expect(try store.read(id: id).text == "")
        #expect(try store.list().count == 1)
        #expect(Note.title(of: try store.read(id: id).text) == "Untitled")
    }

    @Test func newIdentifiersAreLowercaseUUIDs() {
        let store = NoteStore(directory: temp())
        let id = store.newID()
        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
        #expect(id != store.newID())
    }

    @Test func blankDraftsLeaveNoFileButRealEditsAreSaved() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = NotesHandler()
        let created = try await handler.handle("activate", params: params(activation("create"), storage: root),
                                               operation: operation).decode(PluginEffects.self)
        let view = try #require(created.view)
        #expect(view.title == "New note")
        #expect(view.text == "")
        #expect(UUID(uuidString: view.id) != nil)
        let blank = try await handler.handle(
            "activate", params: params(activation("save", payload: .object(["id": .string(view.id)]), text: "  \n "),
                                       storage: root), operation: operation).decode(PluginEffects.self)
        #expect(blank.refreshQuery == false)
        #expect(blank.view?.title == "New note")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let saved = try await handler.handle(
            "activate", params: params(activation("save", payload: .object(["id": .string(view.id)]), text: "Kept\nbody"),
                                       storage: root), operation: operation).decode(PluginEffects.self)
        #expect(saved.refreshQuery)
        #expect(saved.view?.title == "Kept")
        #expect(try NoteStore(directory: root).list().map(\.text) == ["Kept\nbody"])
    }

    @Test func createPrefillsFromThePayloadAndQueriesListTheNote() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = NotesHandler()
        let created = try await handler.handle(
            "activate", params: params(activation("create", payload: .object(["text": .string("milk")])), storage: root),
            operation: operation).decode(PluginEffects.self)
        let view = try #require(created.view)
        #expect(view.text == "milk")
        #expect(view.title == "milk")
        _ = try await handler.handle(
            "activate", params: params(activation("save", payload: .object(["id": .string(view.id)]), text: "milk"),
                                       storage: root), operation: operation)
        let query = PluginQuery(query: "milk", fullQuery: "note milk", timeZoneIdentifier: "UTC", maxResults: 8)
        let items = try await handler.handle(
            "query", params: .object(["apiVersion": .number(2),
                                      "context": try .encode(PluginContext(storagePath: root.path)),
                                      "input": try .encode(query)]),
            operation: operation).decode([PluginItem].self)
        #expect(items.map(\.title) == ["milk", "New note “milk”"])
        let opened = try await handler.handle(
            "activate", params: params(activation("open", payload: .object(["id": .string(view.id)])), storage: root),
            operation: operation).decode(PluginEffects.self)
        #expect(opened.view?.text == "milk")
    }

    @Test func unknownActionsAndMethodsAreRejected() async throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = NotesHandler()
        await #expect(throws: RPCError("notes", "This note no longer exists.")) {
            try await handler.handle("activate",
                                     params: params(activation("open", payload: .object(["id": .string(UUID().uuidString.lowercased())])), storage: root),
                                     operation: operation)
        }
        await #expect(throws: RPCError("params", "A note ID is required.")) {
            try await handler.handle("activate", params: params(activation("open"), storage: root), operation: operation)
        }
        await #expect(throws: RPCError("params", "Invalid note ID.")) {
            try await handler.handle("activate",
                                     params: params(activation("open", payload: .object(["id": .string("../escape")])), storage: root),
                                     operation: operation)
        }
        await #expect(throws: RPCError("action", "Unknown action: delete")) {
            try await handler.handle("activate", params: params(activation("delete"), storage: root), operation: operation)
        }
        await #expect(throws: RPCError("method", "Unsupported method: catalog")) {
            try await handler.handle("catalog", params: .object([:]), operation: operation)
        }
        #expect(try await handler.handle("initialize", params: .object([:]), operation: operation) == .object(["apiVersion": .number(2)]))
        #expect(try await handler.handle("settings", params: .object([:]), operation: operation) == .object([:]))
    }
}
