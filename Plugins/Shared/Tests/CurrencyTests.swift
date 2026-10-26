import Foundation
import Testing
@testable import OddFrogCore
@testable import BundledFeatures

private final class StubProvider: CurrencyRateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let table: CurrencyRates?

    init(table: CurrencyRates?) {
        self.table = table
    }

    var calls: Int {
        lock.withLock { count }
    }

    func fetchRates() async throws -> CurrencyRates {
        lock.withLock { count += 1 }
        guard let table else { throw CurrencyRateError.provider("stub") }
        return table
    }
}

struct CurrencyTests {
    private let locale = Locale(identifier: "en_US")
    private func fixture() throws -> CurrencyRates {
        let url = try #require(Bundle.module.url(forResource: "rates", withExtension: "json", subdirectory: "Fixtures"))
        return try ExchangeRateAPIProvider.parse(try Data(contentsOf: url))
    }

    private func fixture(fetched: Date) throws -> CurrencyRates {
        let table = try fixture()
        return CurrencyRates(base: table.base, timestamp: table.timestamp, rates: table.rates, fetched: fetched)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("odd-frog-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("rates.json")
    }

    @Test func parsesTheProviderResponse() throws {
        let table = try fixture()
        #expect(table.base == "USD")
        #expect(table.rates.count == 5)
        #expect(table.timestamp == Date(timeIntervalSince1970: 1788739351))
        #expect(table.fetched.timeIntervalSinceNow > -5)
    }

    @Test func rejectsAnUnsuccessfulResponse() {
        let body = Data(#"{"result":"error","error-type":"unsupported-code"}"#.utf8)
        #expect(throws: CurrencyRateError.self) {
            try ExchangeRateAPIProvider.parse(body)
        }
    }

    @Test func convertsThroughTheBaseCurrency() throws {
        let table = try fixture()
        let value = try #require(table.convert(200, from: "eur", to: "rsd"))
        #expect(abs(value - 23457.57) < 0.01)
        #expect(table.convert(1, from: "USD", to: "XXX") == nil)
        #expect(table.convert(1, from: "XXX", to: "USD") == nil)
    }

    @Test func parsesEveryAcceptedForm() throws {
        let table = try fixture()
        for text in ["100 usd in eur", "100 USD to EUR", "$100 in eur", "100 usd eur", "100 usd -> eur"] {
            let conversion = try #require(CurrencyConversion.evaluate(text, rates: table, locale: locale), "\(text) did not convert")
            #expect(abs(conversion.value - 86.1072) < 0.001, "\(text) = \(conversion.value)")
            #expect(conversion.result == "86.11 EUR")
            #expect(conversion.input == "100 USD → EUR")
            #expect(conversion.updated == table.timestamp)
        }
        let back = try #require(CurrencyConversion.evaluate("100€ to usd", rates: table, locale: locale))
        #expect(abs(back.value - 116.1341) < 0.001)
        #expect(back.input == "100 EUR → USD")
    }

    @Test func rejectsMalformedCurrencyQueries() throws {
        let table = try fixture()
        for text in ["100 usd in xyz", "usd in eur", "100 usd", "100 km in mi", "safari", "100 usd in eur extra"] {
            #expect(CurrencyConversion.evaluate(text, rates: table, locale: locale) == nil, "\(text) should not convert")
        }
    }

    @Test func convertsToTheDefaultCurrencyWhenTargetIsMissing() throws {
        let table = try fixture()
        for text in ["100 usd", "$100"] {
            #expect(CurrencyConversion.evaluate(text, rates: table, locale: locale) == nil)
            let same = try #require(CurrencyConversion.evaluate(text, rates: table, defaultCurrency: "USD", locale: locale), "\(text) did not convert")
            #expect(same.input == "100 USD" && same.result == "100.00 USD")
        }
        for text in ["100 eur", "100€"] {
            let conversion = try #require(CurrencyConversion.evaluate(text, rates: table, defaultCurrency: "USD", locale: locale), "\(text) did not convert")
            #expect(conversion.input == "100 EUR → USD")
            #expect(abs(conversion.value - 116.1341) < 0.001)
        }
        let rsd = try #require(CurrencyConversion.evaluate("100 usd", rates: table, defaultCurrency: "rsd", locale: locale))
        #expect(rsd.input == "100 USD → RSD")
        #expect(CurrencyConversion.evaluate("100 xyz", rates: table, defaultCurrency: "USD", locale: locale) == nil)
        #expect(CurrencyConversion.evaluate("100 eur", rates: table, defaultCurrency: "XYZ", locale: locale) == nil)
        #expect(CurrencyConversion.evaluate("100 km", rates: table, defaultCurrency: "USD", locale: locale) == nil)
    }

    @Test func wordLikeCodesNeedAnExplicitTarget() throws {
        let fixture = try fixture()
        let table = CurrencyRates(base: fixture.base, timestamp: fixture.timestamp, rates: fixture.rates.merging(["TRY": 41.2, "CUP": 24, "ALL": 83.5]) { $1 })
        for text in ["1 try", "3 cup", "2 all"] {
            #expect(CurrencyConversion.evaluate(text, rates: table, defaultCurrency: "USD", locale: locale) == nil, "\(text) should not convert")
        }
        let explicit = try #require(CurrencyConversion.evaluate("1 try in usd", rates: table, defaultCurrency: "USD", locale: locale))
        #expect(explicit.input == "1 TRY → USD")
    }

    @Test func sharedSymbolsMeanTheDefaultCurrency() throws {
        let fixture = try fixture()
        let table = CurrencyRates(base: fixture.base, timestamp: fixture.timestamp, rates: fixture.rates.merging(["CNY": 7.1, "MXN": 18.4]) { $1 })
        #expect(try #require(CurrencyConversion.evaluate("¥100", rates: table, defaultCurrency: "CNY", locale: locale)).input == "100 CNY")
        #expect(try #require(CurrencyConversion.evaluate("¥100 in usd", rates: table, defaultCurrency: "CNY", locale: locale)).input == "100 CNY → USD")
        #expect(try #require(CurrencyConversion.evaluate("¥100", rates: table, defaultCurrency: "USD", locale: locale)).input == "100 JPY → USD")
        #expect(try #require(CurrencyConversion.evaluate("$100 in eur", rates: table, defaultCurrency: "MXN", locale: locale)).input == "100 MXN → EUR")
        #expect(try #require(CurrencyConversion.evaluate("$100", rates: table, defaultCurrency: "EUR", locale: locale)).input == "100 USD → EUR")
        #expect(try #require(CurrencyConversion.evaluate("€100", rates: table, defaultCurrency: "MXN", locale: locale)).input == "100 EUR → MXN")
    }

    @Test func storeUsesTheCacheUntilItGoesStale() async throws {
        let moment = Date(timeIntervalSince1970: 1788800000)
        let table = try fixture(fetched: moment)
        let provider = StubProvider(table: table)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = CurrencyRateStore(url: url, provider: provider)
        #expect(await store.current() == nil)
        let loaded = await store.refreshIfStale(now: moment)
        #expect(loaded == table)
        #expect(provider.calls == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reopened = CurrencyRateStore(url: url, provider: provider)
        #expect(await reopened.current() == table)
        _ = await reopened.refreshIfStale(now: moment.addingTimeInterval(3600))
        #expect(provider.calls == 1)
        _ = await reopened.refreshIfStale(now: moment.addingTimeInterval(7 * 3600))
        #expect(provider.calls == 2)
    }

    @Test func oldProviderDataDoesNotForceRepeatedRequests() async throws {
        let moment = Date(timeIntervalSince1970: 1788800000)
        let table = try fixture(fetched: moment)
        #expect(moment.timeIntervalSince(table.timestamp) > CurrencyRateStore.staleAfter)

        let provider = StubProvider(table: table)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CurrencyRateStore(url: url, provider: provider)
        _ = await store.refreshIfStale(now: moment)
        #expect(provider.calls == 1)
        for minute in 1...20 {
            _ = await store.refreshIfStale(now: moment.addingTimeInterval(Double(minute) * 60))
        }
        #expect(provider.calls == 1)
    }

    @Test func cacheWithoutAFetchTimeIsTreatedAsStale() async throws {
        let table = try fixture()
        let legacy = Data("""
        {"base":"USD","timestamp":"2026-09-07T00:02:31Z","rates":{"USD":1,"EUR":0.861072}}
        """.utf8)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacy.write(to: url)

        let store = CurrencyRateStore(url: url, provider: StubProvider(table: table))
        let cached = try #require(await store.current())
        #expect(cached.fetched == cached.timestamp)
    }

    @Test func failedRefreshKeepsTheCachedTable() async throws {
        let moment = Date(timeIntervalSince1970: 1788800000)
        let table = try fixture(fetched: moment)
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = await CurrencyRateStore(url: url, provider: StubProvider(table: table)).refreshIfStale(now: moment)

        let failing = CurrencyRateStore(url: url, provider: StubProvider(table: nil))
        let result = await failing.refreshIfStale(now: moment.addingTimeInterval(7 * 3600))
        #expect(result == table)
        #expect(await failing.current() == table)
    }

    @Test func currencyQueryBecomesACurrencyAction() throws {
        let table = try fixture()
        let action = try #require(QuickAction.calculation(for: "100 usd in eur", rates: table, locale: locale))
        #expect(action.title == "86.11 EUR")
        #expect(action.kindLabel == "Currency")
        #expect(action.subtitle?.hasPrefix("100 USD → EUR · rate updated ") == true)
        #expect(action.copyText == "86.11")
        #expect(QuickAction.calculation(for: "100 usd in eur") == nil)
    }

    @Test func bareAmountBecomesACurrencyActionInTheDefaultCurrency() throws {
        let table = try fixture()
        let action = try #require(QuickAction.calculation(for: "100 eur", rates: table, defaultCurrency: "USD", locale: locale))
        #expect(action.title == "116.13 USD")
        #expect(action.kindLabel == "Currency")
        #expect(action.subtitle?.hasPrefix("100 EUR → USD · rate updated ") == true)
        #expect(QuickAction.calculation(for: "100 eur", rates: table, locale: locale) == nil)
    }
}
