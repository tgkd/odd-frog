import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

struct ConversationArchiveTests {
    private func temp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-chat-archive-\(UUID().uuidString)")
    }

    private func conversation(_ title: String, id: String = ConversationArchive.newID(),
                              modified: Date = Date(timeIntervalSince1970: 1_780_000_000)) -> Conversation {
        Conversation(id: id, title: title, created: modified.addingTimeInterval(-60), modified: modified,
                     messages: [PluginMessage(id: "m0", role: .user, text: title)])
    }

    @Test func memoryListsInStoreOrderAndValidatesLikeTheStore() async throws {
        let archive = ConversationArchive()
        let early = Date(timeIntervalSince1970: 1_780_000_000)
        let late = early.addingTimeInterval(60)
        let ids = ["00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000001"]
        try await archive.write(conversation("old", modified: early), in: nil)
        try await archive.write(conversation("b", id: ids[0], modified: late), in: nil)
        try await archive.write(conversation("a", id: ids[1], modified: late), in: nil)
        #expect(try await archive.list(in: nil).map(\.title) == ["a", "b", "old"])
        #expect(try await archive.read(id: ids[0], in: nil).title == "b")
        try await archive.delete(id: ids[0], in: nil)
        try await archive.delete(id: ids[0], in: nil)
        await #expect(throws: RPCError("chat", "This conversation no longer exists.")) {
            try await archive.read(id: ids[0], in: nil)
        }
        for id in ["../x", "not-a-uuid", ""] {
            await #expect(throws: RPCError("params", "Invalid conversation ID.")) { try await archive.read(id: id, in: nil) }
            await #expect(throws: RPCError("params", "Invalid conversation ID.")) { try await archive.delete(id: id, in: nil) }
            await #expect(throws: RPCError("params", "Invalid conversation ID.")) {
                try await archive.write(conversation("nope", id: id), in: nil)
            }
        }
    }

    @Test func theFirstRequestCarriesNothingAndMemoryLeavesFilesAlone() async throws {
        let folder = temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let existing = conversation("on disk")
        try ConversationStore(directory: folder).write(existing)
        let archive = ConversationArchive()
        #expect(try await archive.list(in: nil).isEmpty)
        try await archive.write(conversation("in memory"), in: nil)
        #expect(try ConversationStore(directory: folder).list() == [existing])
    }

    @Test func memoryToFileWritesTheChatsAndEmptiesMemory() async throws {
        let folder = temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let archive = ConversationArchive()
        let chat = conversation("hi")
        try await archive.write(chat, in: nil)
        #expect(try await archive.list(in: folder) == [chat])
        #expect(try ConversationStore(directory: folder).list() == [chat])
        try ConversationStore(directory: folder).delete(id: chat.id)
        #expect(try await archive.list(in: nil).isEmpty)
    }

    @Test func fileToMemoryLoadsTheChatsAndLeavesTheFiles() async throws {
        let folder = temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let chat = conversation("saved")
        try ConversationStore(directory: folder).write(chat)
        let archive = ConversationArchive()
        #expect(try await archive.list(in: folder) == [chat])
        #expect(try await archive.list(in: nil) == [chat])
        try await archive.delete(id: chat.id, in: nil)
        #expect(try ConversationStore(directory: folder).list() == [chat])
    }

    @Test func anotherFolderGetsACopyAndTheOldFolderStays() async throws {
        let first = temp(), second = temp()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let chat = conversation("moved")
        try ConversationStore(directory: first).write(chat)
        let archive = ConversationArchive()
        _ = try await archive.list(in: first)
        #expect(try await archive.list(in: second) == [chat])
        #expect(try ConversationStore(directory: first).list() == [chat])
    }

    @Test func theLaterModifiedConversationWinsOnTheSameID() async throws {
        let folder = temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let id = ConversationArchive.newID()
        let early = Date(timeIntervalSince1970: 1_780_000_000)
        let late = early.addingTimeInterval(60)
        let archive = ConversationArchive()
        try ConversationStore(directory: folder).write(conversation("newer file", id: id, modified: late))
        try await archive.write(conversation("older memory", id: id, modified: early), in: nil)
        #expect(try await archive.list(in: folder).map(\.title) == ["newer file"])
        try ConversationStore(directory: folder).write(conversation("older file", id: id, modified: early))
        let other = ConversationArchive()
        try await other.write(conversation("newer memory", id: id, modified: late), in: nil)
        #expect(try await other.list(in: folder).map(\.title) == ["newer memory"])
        #expect(try await other.list(in: nil).map(\.title) == ["newer memory"])
    }

    @Test func aFailedCarryOverKeepsTheMemoryChats() async throws {
        let blocker = temp(); defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("not a folder".utf8).write(to: blocker)
        let archive = ConversationArchive()
        let chat = conversation("kept")
        try await archive.write(chat, in: nil)
        await #expect(throws: (any Error).self) { try await archive.list(in: blocker) }
        #expect(try await archive.list(in: nil) == [chat])
    }
}
