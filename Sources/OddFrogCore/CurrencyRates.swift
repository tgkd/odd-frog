import Foundation

public enum CurrencyRateError: Error {
    case provider(String)
}

public struct CurrencyRates: Codable, Sendable, Equatable {
    public let base: String
    public let timestamp: Date
    public let fetched: Date
    public let rates: [String: Double]

    public init(base: String, timestamp: Date, rates: [String: Double], fetched: Date = Date()) {
        self.base = base
        self.timestamp = timestamp
        self.rates = rates
        self.fetched = fetched
    }

    enum CodingKeys: String, CodingKey {
        case base
        case timestamp
        case fetched
        case rates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        base = try container.decode(String.self, forKey: .base)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        rates = try container.decode([String: Double].self, forKey: .rates)
        fetched = try container.decodeIfPresent(Date.self, forKey: .fetched) ?? timestamp
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rates[from.uppercased()], let target = rates[to.uppercased()], source != 0 else { return nil }
        let value = amount / source * target
        guard value.isFinite else { return nil }
        return value
    }
}

public protocol CurrencyRateProvider: Sendable {
    func fetchRates() async throws -> CurrencyRates
}

public struct ExchangeRateAPIProvider: CurrencyRateProvider {
    public static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    public init() {}

    public func fetchRates() async throws -> CurrencyRates {
        let (data, _) = try await URLSession.shared.data(from: Self.endpoint)
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> CurrencyRates {
        struct Response: Decodable {
            let result: String
            let base: String?
            let timestamp: Double?
            let rates: [String: Double]?

            enum CodingKeys: String, CodingKey {
                case result
                case base = "base_code"
                case timestamp = "time_last_update_unix"
                case rates
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result == "success" else { throw CurrencyRateError.provider(response.result) }
        guard let base = response.base, let timestamp = response.timestamp, let rates = response.rates, !rates.isEmpty else {
            throw CurrencyRateError.provider("incomplete response")
        }
        return CurrencyRates(base: base, timestamp: Date(timeIntervalSince1970: timestamp), rates: rates)
    }
}
