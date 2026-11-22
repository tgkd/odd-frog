import Foundation
import Testing
import OddFrogCore
import OddFrogHostServicesAPI
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
        #expect(NoteText.title(of: try store.read(id: id).text) == "Untitled")
    }

    @Test func newIdentifiersAreLowercaseUUIDs() {
        let store = NoteStore(directory: temp())
        let id = store.newID()
        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
        #expect(id != store.newID())
    }
}
