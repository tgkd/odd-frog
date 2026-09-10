import Foundation
import OddFrogPluginAPI

public struct ConversationStore: Sendable {
    public let directory: URL
    public init(directory: URL) {
        self.directory = directory
    }
    public func list() throws -> [Conversation] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var conversations: [Conversation] = []
        for url in contents {
            guard url.pathExtension == "json" else {
                continue
            }
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else {
                continue
            }
            guard (try? url.resourceValues(forKeys: keys))?.isRegularFile == true else {
                continue
            }
            guard let conversation = decode(url) else {
                continue
            }
            conversations.append(conversation)
        }
        return conversations.sorted { lhs, rhs in
            if lhs.modified != rhs.modified {
                return lhs.modified > rhs.modified
            }
            return lhs.id < rhs.id
        }
    }
    public func read(id: String) throws -> Conversation {
        guard let conversation = decode(try file(for: id)) else {
            throw RPCError("chat", "This conversation no longer exists.")
        }
        return conversation
    }
    public func write(_ conversation: Conversation) throws {
        let url = try file(for: conversation.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PluginProtocol.encoder().encode(conversation).write(to: url, options: .atomic)
    }
    public func delete(id: String) throws {
        let url = try file(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
    public func exists(id: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try file(for: id).path)
    }
    public func newID() -> String {
        UUID().uuidString.lowercased()
    }
    private func file(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else {
            throw RPCError("params", "Invalid conversation ID.")
        }
        return directory.appendingPathComponent(id + ".json", isDirectory: false)
    }
    private func decode(_ url: URL) -> Conversation? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PluginProtocol.decoder().decode(Conversation.self, from: data)
    }
}
