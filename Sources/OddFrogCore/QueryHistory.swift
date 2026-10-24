import Foundation

public struct QueryHistory: Codable, Sendable, Equatable {
    public static let limit = 50

    public var queries: [String]

    public init(queries: [String] = []) {
        self.queries = queries
    }

    /// Whitespace is kept: a keyword trigger needs its trailing space (`clip `) to reopen as the plugin chip.
    public mutating func record(_ query: String) {
        guard !query.allSatisfy(\.isWhitespace) else { return }
        queries.removeAll { $0 == query }
        queries.insert(query, at: 0)
        if queries.count > Self.limit { queries.removeLast(queries.count - Self.limit) }
    }

    /// The `count` indices to show around `index`, clamped so the window never runs past either end.
    public static func window(around index: Int, count: Int, total: Int) -> Range<Int> {
        let size = max(0, min(count, total))
        let low = max(0, min(index - size / 2, total - size))
        return low..<low + size
    }
}

public actor QueryHistoryStore {
    public let url: URL
    private var history: QueryHistory

    public init(url: URL) {
        self.url = url
        self.history = QueryHistoryStore.read(url) ?? QueryHistory()
    }

    public static var defaultURL: URL {
        StoragePaths.support.appendingPathComponent("query-history.json")
    }

    public func snapshot() -> QueryHistory { history }

    public func record(_ query: String) {
        let before = history
        history.record(query)
        guard history != before else { return }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
        } catch {
            NSLog("odd-frog: query history write failed: \(error)")
        }
    }

    private static func read(_ url: URL) -> QueryHistory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QueryHistory.self, from: data)
    }
}
