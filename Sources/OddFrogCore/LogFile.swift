import Foundation

public struct LogFile: Sendable {
    public static let defaultLimit = 512 * 1024

    public let url: URL
    public let limit: Int

    public init(url: URL, limit: Int = LogFile.defaultLimit) {
        self.url = url
        self.limit = limit
    }

    public func append(_ line: String) {
        let data = Data(line.utf8)
        trimIfNeeded(adding: data.count)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private func trimIfNeeded(adding added: Int) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size + added > limit,
              let existing = try? Data(contentsOf: url) else { return }
        let keep = max(0, limit / 2)
        guard existing.count > keep else { return }
        var tail = existing.suffix(keep)
        if existing[existing.count - keep - 1] != UInt8(ascii: "\n") {
            if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
                tail = tail[tail.index(after: newline)...]
            } else {
                tail = Data()
            }
        }
        try? Data(tail).write(to: url)
    }
}
