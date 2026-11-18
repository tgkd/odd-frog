import Foundation
import OddFrogPluginAPI

public actor ConversationArchive {
    private enum Location: Equatable {
        case memory
        case folder(String)

        init(_ directory: URL?) {
            self = directory.map { .folder($0.standardizedFileURL.path) } ?? .memory
        }
    }

    private var served: Location?
    private var memory: [String: Conversation] = [:]

    public init() {}

    public func list(in directory: URL?) throws -> [Conversation] {
        switch try select(directory) {
        case .memory:
            return Self.sorted(Array(memory.values))
        case .folder(let path):
            return try Self.store(path).list()
        }
    }

    public func read(id: String, in directory: URL?) throws -> Conversation {
        switch try select(directory) {
        case .memory:
            try Self.validate(id)
            guard let conversation = memory[id] else {
                throw RPCError("chat", "This conversation no longer exists.")
            }
            return conversation
        case .folder(let path):
            return try Self.store(path).read(id: id)
        }
    }

    public func write(_ conversation: Conversation, in directory: URL?) throws {
        switch try select(directory) {
        case .memory:
            try Self.validate(conversation.id)
            memory[conversation.id] = conversation
        case .folder(let path):
            try Self.store(path).write(conversation)
        }
    }

    public func delete(id: String, in directory: URL?) throws {
        switch try select(directory) {
        case .memory:
            try Self.validate(id)
            memory[id] = nil
        case .folder(let path):
            try Self.store(path).delete(id: id)
        }
    }

    public nonisolated static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    private func select(_ directory: URL?) throws -> Location {
        let target = Location(directory)
        guard let served, served != target else {
            self.served = target
            return target
        }
        try carry(from: served, to: target)
        self.served = target
        return target
    }

    private func carry(from source: Location, to target: Location) throws {
        switch (source, target) {
        case (.memory, .folder(let path)):
            try merge(Array(memory.values), into: Self.store(path))
            memory = [:]
        case (.folder(let path), .memory):
            for conversation in try Self.store(path).list() {
                if let kept = memory[conversation.id], kept.modified >= conversation.modified {
                    continue
                }
                memory[conversation.id] = conversation
            }
        case (.folder(let from), .folder(let to)):
            try merge(Self.store(from).list(), into: Self.store(to))
        case (.memory, .memory):
            return
        }
    }

    private func merge(_ conversations: [Conversation], into store: ConversationStore) throws {
        let present = try Dictionary(store.list().map { ($0.id, $0.modified) }, uniquingKeysWith: max)
        for conversation in conversations {
            if let modified = present[conversation.id], modified >= conversation.modified {
                continue
            }
            try store.write(conversation)
        }
    }

    private static func store(_ path: String) -> ConversationStore {
        ConversationStore(directory: URL(fileURLWithPath: path, isDirectory: true))
    }

    private static func validate(_ id: String) throws {
        guard UUID(uuidString: id) != nil else {
            throw RPCError("params", "Invalid conversation ID.")
        }
    }

    private static func sorted(_ conversations: [Conversation]) -> [Conversation] {
        conversations.sorted { lhs, rhs in
            if lhs.modified != rhs.modified {
                return lhs.modified > rhs.modified
            }
            return lhs.id < rhs.id
        }
    }
}
