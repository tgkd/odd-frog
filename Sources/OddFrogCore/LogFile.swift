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
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
