import Foundation

public struct FrecencyEntry: Codable, Sendable, Equatable {
    public var weight: Double
    public var lastUsed: Date

    public init(weight: Double, lastUsed: Date) {
        self.weight = weight
        self.lastUsed = lastUsed
    }
}

public struct FrecencyTable: Codable, Sendable, Equatable {
    public static let halfLife: TimeInterval = 7 * 24 * 3600

    public var entries: [String: FrecencyEntry]

    public init(entries: [String: FrecencyEntry] = [:]) {
        self.entries = entries
    }

    public static func decay(_ weight: Double, from lastUsed: Date, to now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(lastUsed))
        return weight * pow(0.5, elapsed / halfLife)
    }

    public func weight(for id: String, at now: Date) -> Double {
        guard let entry = entries[id] else { return 0 }
        return Self.decay(entry.weight, from: entry.lastUsed, to: now)
    }

    public func decayedWeights(at now: Date) -> [String: Double] {
        entries.mapValues { Self.decay($0.weight, from: $0.lastUsed, to: now) }
    }

    public mutating func record(_ id: String, at now: Date) {
        let current = weight(for: id, at: now)
        entries[id] = FrecencyEntry(weight: current + 1, lastUsed: now)
    }

    public mutating func prune(before cutoff: Date, minimumWeight: Double = 0.01, now: Date) {
        entries = entries.filter { _, entry in
            entry.lastUsed >= cutoff || Self.decay(entry.weight, from: entry.lastUsed, to: now) >= minimumWeight
        }
    }
}

public actor FrecencyStore {
    public let url: URL
    private var table: FrecencyTable

    public init(url: URL) {
        self.url = url
        self.table = FrecencyStore.read(url) ?? FrecencyTable()
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("odd-frog", isDirectory: true)
            .appendingPathComponent("frecency.json")
    }

    public func snapshot() -> FrecencyTable { table }

    public func decayedWeights(at now: Date = Date()) -> [String: Double] {
        table.decayedWeights(at: now)
    }

    public func record(_ id: String, at now: Date = Date()) {
        table.record(id, at: now)
        table.prune(before: now.addingTimeInterval(-90 * 24 * 3600), now: now)
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(table).write(to: url, options: .atomic)
        } catch {
            NSLog("odd-frog: frecency write failed: \(error)")
        }
    }

    private static func read(_ url: URL) -> FrecencyTable? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FrecencyTable.self, from: data)
    }
}
