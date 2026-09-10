import Foundation
import OddFrogPluginAPI

public struct NoteStore: Sendable {
    public let directory: URL
    public init(directory: URL) {
        self.directory = directory
    }
    public func list() throws -> [Note] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        var notes: [Note] = []
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
            notes.append(Note(id: name, text: text, modified: values?.contentModificationDate ?? .distantPast))
        }
        return notes.sorted { lhs, rhs in
            if lhs.modified != rhs.modified {
                return lhs.modified > rhs.modified
            }
            return lhs.id < rhs.id
        }
    }
    public func read(id: String) throws -> Note {
        let url = try file(for: id)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw RPCError("notes", "This note no longer exists.")
        }
        return Note(id: id, text: text, modified: modified(of: url))
    }
    public func write(id: String, text: String) throws -> Note {
        let url = try file(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        return Note(id: id, text: text, modified: modified(of: url))
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
