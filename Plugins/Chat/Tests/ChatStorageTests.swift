import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

struct ChatStorageTests {
    private let defaultPath = "/tmp/odd-frog-chat-default"

    @Test func missingOrMemoryStorageMeansMemory() throws {
        #expect(try ChatStorage.directory(settings: [:], defaultPath: defaultPath) == nil)
        #expect(try ChatStorage.directory(settings: ["storage": .string("Memory"), "storage_path": .string("/x")],
                                          defaultPath: defaultPath) == nil)
    }

    @Test func fileWithAnEmptyFolderUsesTheDefaultPath() throws {
        let url = try ChatStorage.directory(settings: ["storage": .string("File"), "storage_path": .string("  ")],
                                            defaultPath: defaultPath)
        #expect(url?.path == defaultPath)
        #expect(try ChatStorage.directory(settings: ["storage": .string("File")], defaultPath: defaultPath)?.path == defaultPath)
    }

    @Test func fileExpandsTheTildeAndKeepsAbsolutePaths() throws {
        let home = try ChatStorage.directory(settings: ["storage": .string("File"), "storage_path": .string("~/Chats")],
                                             defaultPath: defaultPath)
        #expect(home?.path == NSString(string: "~/Chats").expandingTildeInPath)
        let absolute = try ChatStorage.directory(settings: ["storage": .string("File"), "storage_path": .string(" /var/chats ")],
                                                 defaultPath: defaultPath)
        #expect(absolute?.path == "/var/chats")
    }

    @Test func aRelativeFolderIsRejected() {
        #expect(throws: RPCError("chat", "The chat folder must start with / or ~: chats")) {
            try ChatStorage.directory(settings: ["storage": .string("File"), "storage_path": .string("chats")],
                                      defaultPath: defaultPath)
        }
    }
}
