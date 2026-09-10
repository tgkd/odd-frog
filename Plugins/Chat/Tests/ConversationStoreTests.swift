import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

struct ConversationStoreTests {
    private func temp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-chat-\(UUID().uuidString)")
    }

    private func existing() throws -> URL {
        let root = temp()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func conversation(_ id: String, title: String, modified: Date, messages: [PluginMessage] = []) -> Conversation {
        Conversation(id: id, title: title, created: modified.addingTimeInterval(-60), modified: modified, messages: messages)
    }

    @Test func listCreatesTheDirectoryAndStartsEmpty() throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root)
        #expect(try store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func writeAndReadRoundTripMessagesAndDates() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root)
        let id = store.newID()
        let modified = Date(timeIntervalSince1970: 1_780_000_000)
        let messages = [PluginMessage(id: "m0", role: .user, text: "hi"),
                        PluginMessage(id: "m1", role: .assistant, text: "Hello")]
        try store.write(conversation(id, title: "hi", modified: modified, messages: messages))
        let read = try store.read(id: id)
        #expect(read.id == id)
        #expect(read.title == "hi")
        #expect(read.messages == messages)
        #expect(read.modified == modified)
        #expect(read.created == modified.addingTimeInterval(-60))
        #expect(try store.exists(id: id))
        #expect(try store.list().map(\.id) == [id])
    }

    @Test func listOrdersByModificationDateDescending() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root)
        var ids: [String: String] = [:]
        for (name, stamp) in [("oldest", "2026-09-01T08:00:00Z"), ("newest", "2026-09-09T08:00:00Z"),
                              ("middle", "2026-09-05T08:00:00Z")] {
            let id = store.newID()
            try store.write(conversation(id, title: name, modified: ISO8601DateFormatter().date(from: stamp)!))
            ids[name] = id
        }
        #expect(try store.list().map(\.title) == ["newest", "middle", "oldest"])
        #expect(try store.list().map(\.id) == ["newest", "middle", "oldest"].map { ids[$0]! })
    }

    @Test func deleteRemovesTheFileAndIsIdempotent() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root)
        let id = store.newID()
        try store.write(conversation(id, title: "Alpha", modified: Date()))
        try store.delete(id: id)
        #expect(try !store.exists(id: id))
        #expect(try store.list().isEmpty)
        try store.delete(id: id)
        #expect(throws: RPCError("chat", "This conversation no longer exists.")) { try store.read(id: id) }
    }

    @Test func undecodableAndForeignFilesAreSkippedButKept() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root)
        let id = store.newID()
        try store.write(conversation(id, title: "Kept", modified: Date()))
        let broken = store.newID()
        try Data("{ not json".utf8).write(to: root.appendingPathComponent(broken + ".json"))
        for name in ["chats.md", "not-a-uuid.json", "\(store.newID()).txt", "README"] {
            try Data("ignored".utf8).write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("\(store.newID()).json"),
                                                withIntermediateDirectories: true)
        #expect(try store.list().map(\.id) == [id])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(broken + ".json").path))
    }

    @Test func invalidIdentifiersNeverReachTheFilesystem() throws {
        let root = try existing(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root)
        for id in ["../x", "a/b", "not-a-uuid", "", "  "] {
            #expect(throws: RPCError("params", "Invalid conversation ID.")) { try store.read(id: id) }
            #expect(throws: RPCError("params", "Invalid conversation ID.")) { try store.exists(id: id) }
            #expect(throws: RPCError("params", "Invalid conversation ID.")) { try store.delete(id: id) }
            #expect(throws: RPCError("params", "Invalid conversation ID.")) {
                try store.write(Conversation(id: id, title: "nope", created: Date(), modified: Date(), messages: []))
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func newIdentifiersAreLowercaseUUIDs() {
        let store = ConversationStore(directory: temp())
        let id = store.newID()
        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
        #expect(id != store.newID())
    }
}
