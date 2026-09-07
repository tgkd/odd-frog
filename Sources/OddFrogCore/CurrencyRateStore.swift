import Foundation

public actor CurrencyRateStore {
    public static let staleAfter: TimeInterval = 6 * 3600

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("odd-frog", isDirectory: true)
            .appendingPathComponent("rates.json")
    }

    public let url: URL
    private let provider: any CurrencyRateProvider
    private var rates: CurrencyRates?
    private var refreshing = false

    public init(url: URL, provider: any CurrencyRateProvider) {
        self.url = url
        self.provider = provider
        self.rates = CurrencyRateStore.read(url)
    }

    public func current() -> CurrencyRates? { rates }

    @discardableResult
    public func refreshIfStale(now: Date = Date()) async -> CurrencyRates? {
        if let rates, now.timeIntervalSince(rates.fetched) < Self.staleAfter { return rates }
        guard !refreshing else { return rates }
        refreshing = true
        defer { refreshing = false }
        do {
            let fetched = try await provider.fetchRates()
            rates = fetched
            persist(fetched)
            return fetched
        } catch {
            NSLog("odd-frog: rates refresh failed: \(error)")
            return rates
        }
    }

    private func persist(_ table: CurrencyRates) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(table).write(to: url, options: .atomic)
        } catch {
            NSLog("odd-frog: rates write failed: \(error)")
        }
    }

    private static func read(_ url: URL) -> CurrencyRates? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CurrencyRates.self, from: data)
    }
}
