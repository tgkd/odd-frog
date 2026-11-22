import Foundation
import OddFrogHostServicesAPI
import OddFrogPluginAPI

public struct NoteStore: Sendable {
    public let directory: URL
    public init(directory: URL) {
        self.directory = directory
    }
    public func list() throws -> [NoteRecord] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var notes: [NoteRecord] = []
        for url in contents {
            guard url.pathExtension == "txt" else {
                continue
            }
            let name = url.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: name) != nil else {
                continue
            }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else {
                continue
            }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                continue
            }
            notes.append(NoteRecord(id: name, text: text, modified: values?.contentModificationDate ?? .distantPast))
        }
        return notes.sorted { lhs, rhs in
            if lhs.modified != rhs.modified {
                return lhs.modified > rhs.modified
            }
            return lhs.id < rhs.id
        }
    }
    public func read(id: String) throws -> NoteRecord {
        let url = try file(for: id)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw RPCError("notes", "This note no longer exists.")
        }
        return NoteRecord(id: id, text: text, modified: modified(of: url))
    }
    public func write(id: String, text: String) throws -> NoteRecord {
        let url = try file(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        return NoteRecord(id: id, text: text, modified: modified(of: url))
    }
    public func exists(id: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try file(for: id).path)
    }
    public func newID() -> String {
        UUID().uuidString.lowercased()
    }
    private func file(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else {
            throw RPCError("params", "Invalid note ID.")
        }
        return directory.appendingPathComponent(id + ".txt", isDirectory: false)
    }
    private func modified(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }
}

public struct NotesService: Sendable {
    public let store: NoteStore
    public init(directory: URL) {
        store = NoteStore(directory: directory)
    }
    @MainActor public func register(in registry: HostServiceRegistry) {
        let store = store
        registry.register("notes.read@1") { params, _ in
            let query = try params.decode(NotesQuery.self)
            guard query.isValid() else { throw RPCError("params", "Invalid notes query.") }
            let filter = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = try store.list().filter { filter.isEmpty || $0.text.localizedStandardContains(filter) }
            return try .encode(NotesSnapshot(notes: Array(matches.prefix(query.limit)), truncated: matches.count > query.limit))
        }
        registry.register("notes.get@1") { params, _ in
            guard let id = params["id"].string else { throw RPCError("params", "A note ID is required.") }
            return try .encode(store.read(id: id))
        }
        registry.register("notes.write@1", activationRequired: true) { params, _ in
            let write = try params.decode(NoteWrite.self)
            guard write.text.count <= NoteText.maximumLength else {
                throw RPCError("params", "A note can have up to \(NoteText.maximumLength) characters.")
            }
            return try .encode(store.write(id: write.id, text: write.text))
        }
        registry.register("notes.create@1", activationRequired: true) { params, _ in
            guard let text = params["text"].string, NoteText.isValid(text) else {
                throw RPCError("params", "A note needs text, up to \(NoteText.maximumLength) characters.")
            }
            let note = try store.write(id: store.newID(), text: text)
            return try .encode(PluginEffects(notification: "Note added: \(NoteText.title(of: note.text))", refreshQuery: true))
        }
        registry.register("notes.append@1", activationRequired: true) { params, _ in
            let append = try params.decode(NoteAppend.self)
            let existing = try store.read(id: append.id)
            let separator = existing.text.hasSuffix("\n") || existing.text.isEmpty ? "" : "\n"
            let combined = existing.text + separator + append.text
            guard NoteText.isValid(append.text), combined.count <= NoteText.maximumLength else {
                throw RPCError("params", "The note would exceed \(NoteText.maximumLength) characters.")
            }
            let note = try store.write(id: append.id, text: combined)
            return try .encode(PluginEffects(notification: "Note updated: \(NoteText.title(of: note.text))", refreshQuery: true))
        }
    }
}
