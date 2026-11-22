import Foundation

public struct Review: Sendable, Equatable {
    public var runID: String
    public var step: Int
    public var title: String
    public var text: String
    public var editable: Bool
    public init(runID: String, step: Int, title: String, text: String, editable: Bool) {
        self.runID = runID; self.step = step; self.title = title; self.text = text; self.editable = editable
    }
    public var viewID: String { "\(runID)-\(step)" }
}

struct ReviewedText: Equatable {
    var title: String
    var body: String

    init?(_ text: String) {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let head = lines.firstIndex(where: { !Self.isBlank($0) }) else { return nil }
        var rest = lines[(head + 1)...]
        while let first = rest.first, Self.isBlank(first) { rest = rest.dropFirst() }
        while let last = rest.last, Self.isBlank(last) { rest = rest.dropLast() }
        title = lines[head].trimmingCharacters(in: .whitespaces)
        body = rest.joined(separator: "\n")
    }

    private static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }
}

struct ReviewFiles: Sendable {
    let folder: URL

    init(history: URL?) {
        folder = history.map { $0.deletingLastPathComponent().appendingPathComponent("review", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-review-\(UUID().uuidString)",
                                                                             isDirectory: true)
    }

    func write(_ body: String, run: String, step: Int) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let file = folder.appendingPathComponent("\(run)-\(step).txt")
        try? manager.removeItem(at: file)
        guard manager.createFile(atPath: file.path, contents: Data(body.utf8),
                                 attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return file
    }

    func remove(_ files: [URL]) {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
