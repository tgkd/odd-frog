# Task: Inline calculator — currency conversion with cached exchange rates

Task 16, last of the calculator series. Requires tasks 14 and 15
(`14-inline-calculator-arithmetic.md`, `15-unit-conversion.md`).

## Goal
Typing `100 usd in eur`, `200 eur to rsd`, `$100 in eur` or `100 usd eur` shows a "Currency"
row first, titled with the converted amount and code (for example `86.11 EUR`) and subtitled
with the input plus how old the rate is (`100 USD → EUR · rate updated 4 hours ago`). Rates
come from one HTTPS request to a free, keyless provider, cached on disk and refreshed at most
every six hours in the background. Offline, the cached rate is used; with no cache at all the
query falls through to normal search. The launcher never waits on the network while typing.

## Files
- Sources/OddFrogCore/CurrencyRates.swift           (create — rate table, provider protocol, HTTP provider)
- Sources/OddFrogCore/CurrencyRateStore.swift       (create — actor: disk cache + staleness)
- Sources/OddFrogCore/CurrencyConversion.swift      (create — grammar + evaluation)
- Sources/OddFrogCore/QuickAction.swift             (modify — `.currency` kind, `rates:` parameter)
- Sources/OddFrogCore/SearchEngine.swift            (modify — `rates:` parameter threaded through)
- Sources/OddFrog/LauncherViewController.swift      (modify — `rates` property)
- Sources/OddFrog/AppDelegate.swift                 (modify — own the store, refresh on launch and show)
- Sources/OddFrog/IconCache.swift                   (modify — tile for the Currency kind)
- Tests/OddFrogCoreTests/CurrencyTests.swift        (create)
- Tests/OddFrogCoreTests/Fixtures/rates.json        (create — trimmed provider response)
- Package.swift                                     (modify — `resources: [.copy("Fixtures")]` on the test target)
- Tests/OddFrogCoreTests/QuickActionTests.swift     (modify — one row test)
- README.md                                         (modify — Usage paragraph + privacy note)
- Sources/OddFrogCore/Frecency.swift                (read — `FrecencyStore` is the actor/disk pattern to mirror)

## Context
- Task 14 and 15 Context holds. `QuickAction.calculation(for:)` tries arithmetic then units.
  `SearchEngine.search(query:items:weights:maxResults:searchTemplate:)` calls it with the
  trimmed query. `LauncherViewController` owns `items`, `weights`, `maxResults`,
  `searchTemplate` as `didSet { refresh(keepSelection: true) }` properties and passes them to
  `SearchEngine.search` inside `refresh`. `AppDelegate.wirePanel` seeds those properties;
  `showPanel` calls `refreshWeightsIfStale()` (10-minute throttle) — the model for a cheap
  per-show check. `applicationDidFinishLaunching` starts several `Task { await … }` jobs.
- `FrecencyStore` (Sources/OddFrogCore/Frecency.swift) is the persistence pattern:
  `public actor`, `init(url:)` reads the file synchronously, `defaultURL` under
  `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  /odd-frog/`, JSON via `JSONEncoder` with `.iso8601` dates and `.sortedKeys`, atomic writes,
  `NSLog("odd-frog: …")` on write failure (Core has no `Log`).
- Provider, decided: `https://open.er-api.com/v6/latest/USD` (ExchangeRate-API open
  endpoint, no key, daily update, 166 currencies including RSD). Verified response shape on
  2026-09-07:
  ```
  {"result":"success","provider":"https://www.exchangerate-api.com",
   "time_last_update_unix":1788739351,"time_next_update_unix":1788826621,
   "base_code":"USD","rates":{"USD":1,"AED":3.6725,"EUR":0.861072,"RSD":100.993275,…}}
  ```
  Alternative considered and rejected: `api.frankfurter.app` (ECB, ~30 currencies, no RSD,
  which the user's own example needs).
- Cross rates with a USD base: `amount / rates[from] * rates[to]`. With the values above,
  `200 EUR → RSD` is `200 / 0.861072 * 100.993275 ≈ 23457.57`.
- `Date.formatted(.relative(presentation: .numeric))` yields `"4 hours ago"`.
- The app is an `LSUIElement` agent with no App Transport Security overrides; plain HTTPS via
  `URLSession.shared` needs nothing in Info.plist.
- ISO codes vs unit tokens: task 15 runs first, so `cup`/`cups` (also ISO `CUP`, Cuban peso)
  resolve as volume whenever the other token is a volume unit; `2 cup in usd` reaches the
  currency evaluator and converts Cuban pesos. Accepted edge case; document nothing.
- Decisions, already made: no Settings UI and no settings keys; rates are `Double`, not
  `Decimal`; base is always USD; refresh interval 6 hours; the cache file is
  `~/Library/Application Support/odd-frog/rates.json`; a refresh failure keeps the old cache
  and logs once; one row per query.

## Plan
1. Create `Sources/OddFrogCore/CurrencyRates.swift`:
   - `public struct CurrencyRates: Codable, Sendable, Equatable { public let base: String;
     public let timestamp: Date; public let rates: [String: Double] }` with a public
     memberwise init and `public func convert(_ amount: Double, from: String, to: String)
     -> Double?` (uppercases both codes; nil when either is missing or the source rate is 0).
   - `public protocol CurrencyRateProvider: Sendable { func fetchRates() async throws ->
     CurrencyRates }`.
   - `public struct ExchangeRateAPIProvider: CurrencyRateProvider` with
     `public static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!`,
     `public init()`, `fetchRates()` doing `URLSession.shared.data(from:)` then
     `Self.parse(_:)`, and `public static func parse(_ data: Data) throws -> CurrencyRates`
     decoding `result`, `base_code`, `time_last_update_unix`, `rates`; throw
     `CurrencyRateError.provider(String)` (a small `public enum … : Error`) when `result` is
     not `"success"`.
2. Create `Sources/OddFrogCore/CurrencyRateStore.swift`:
   `public actor CurrencyRateStore` with `public static let staleAfter: TimeInterval = 6 * 3600`,
   `public static var defaultURL: URL` (Application Support `/odd-frog/rates.json`, same
   construction as `FrecencyStore.defaultURL`), `public init(url: URL, provider: any
   CurrencyRateProvider)` that reads the cache file synchronously (missing or undecodable →
   nil), `public func current() -> CurrencyRates?`, and `public func refreshIfStale(now: Date
   = Date()) async -> CurrencyRates?` which returns the cached table untouched when
   `now - timestamp < staleAfter`, otherwise awaits `provider.fetchRates()`, stores it in
   memory, writes it to disk (create the directory, JSON with `.iso8601` dates, `.sortedKeys`,
   atomic), and returns it; on a thrown error it `NSLog`s `"odd-frog: rates refresh failed:
   \(error)"` and returns the stale cache. Guard against concurrent refreshes with a
   `private var refreshing = false` flag so two callers do not both hit the network.
3. Create `Sources/OddFrogCore/CurrencyConversion.swift`:
   `public struct CurrencyConversion: Sendable, Hashable { public let input: String; public let
   value: Double; public let result: String; public let updated: Date }` and
   `public static func evaluate(_ text: String, rates: CurrencyRates) -> CurrencyConversion?`.
   Grammar over the trimmed text: `<amount> <ws?> <code> <ws> (in|to|as|->|=|→)? <ws> <code>`
   where `<amount>` is task 14's number token; a currency symbol may replace the source code
   either before the amount (`$100 in eur`) or after it (`100€ in usd`); symbols: `$` USD,
   `€` EUR, `£` GBP, `¥` JPY, `₽` RUB, `₴` UAH, `₺` TRY, `₹` INR, `₩` KRW. Codes are three
   letters (case-insensitive) and both must be keys of `rates.rates`; the keyword-less form
   needs both to resolve. Anything else → nil. `value` = `rates.convert(...)`; `result` =
   `value.formatted(.number.precision(.fractionLength(2)))` + `" "` + target code;
   `input` = `"<amount as typed> <FROM> → <TO>"`; `updated` = `rates.timestamp`.
4. `QuickAction.swift`:
   - `CalculationKind` gains `case currency(result: String, updated: Date)`; `title` returns
     `result`; `kindLabel` `"Currency"`; `subtitle` for this kind is
     `input + " · rate updated " + updated.formatted(.relative(presentation: .numeric))`;
     `copyText` is the `value` formatted with `.number.grouping(.never).precision(
     .fractionLength(2))`.
   - `calculation(for:)` becomes `calculation(for query: String, rates: CurrencyRates? =
     nil)`; after arithmetic and units return nil and `rates` is non-nil, try
     `CurrencyConversion.evaluate(trimmed, rates:)`.
5. `SearchEngine.search` gains `rates: CurrencyRates? = nil` (last parameter) and passes it to
   `QuickAction.calculation(for:rates:)`.
6. `LauncherViewController`: add `var rates: CurrencyRates? { didSet { refresh(keepSelection:
   true) } }` next to `searchTemplate` and pass it in `refresh`.
7. `AppDelegate`:
   - `private let rates = CurrencyRateStore(url: CurrencyRateStore.defaultURL, provider:
     ExchangeRateAPIProvider())`.
   - In `applicationDidFinishLaunching`, alongside the other tasks:
     `Task { await refreshRates() }` where `private func refreshRates() async` does
     `controller.rates = await rates.refreshIfStale()` and logs
     `"rates: \(count) currencies, updated \(timestamp)"` via `Log.write` when non-nil.
     Seed `controller.rates = await rates.current()` first so the cached table is available
     before the network round trip finishes.
   - In `showPanel`, after `refreshWeightsIfStale()`, `Task { await refreshRates() }`
     (the store's own staleness check makes this free when fresh).
8. `IconCache.icon(for:)`: `.currency` kind → `tile(name: "currency", color: .systemMint,
   symbol: "dollarsign", symbolSize: 13, size: size)`.
9. `Package.swift`: the test target gets `resources: [.copy("Fixtures")]`. Create
   `Tests/OddFrogCoreTests/Fixtures/rates.json` containing a real response trimmed to
   `result`, `base_code`, `time_last_update_unix: 1788739351`, and `rates` for `USD: 1`,
   `EUR: 0.861072`, `RSD: 100.993275`, `GBP: 0.74`, `JPY: 147.2`.
10. Tests (`CurrencyTests.swift`, loading the fixture through `Bundle.module`):
    - `parseProviderResponse`: `ExchangeRateAPIProvider.parse` yields base `USD`, five rates,
      timestamp `Date(timeIntervalSince1970: 1788739351)`; a body with `"result":"error"`
      throws.
    - `crossRateConversion`: `convert(200, from: "eur", to: "rsd")` ≈ `23458.14`
      (tolerance `0.01`); `convert(1, from: "USD", to: "XXX")` is nil.
    - `grammar`: with the fixture rates, `100 usd in eur` → `≈ 86.11`, result `"86.11 EUR"`,
      input `"100 USD → EUR"`; `$100 in eur` and `100 usd eur` give the same value;
      `100€ to usd` ≈ `116.13`; `100 usd in xyz`, `usd in eur`, `100 usd`, `100 km in mi`
      → nil.
    - `storeUsesCacheUntilStale`: a counting stub provider (`final class` with an `NSLock`
      counter, conforming to `CurrencyRateProvider`) returning the fixture; a store on a
      temporary file: `refreshIfStale()` fetches once and writes the file; a second store on
      the same file reports `current()` non-nil and, with `now: timestamp + 1 hour`, does not
      fetch; with `now: timestamp + 7 hours` it fetches again. A throwing provider leaves
      `current()` equal to the previous table.
    - `QuickActionTests.swift`: `calculation(for: "100 usd in eur", rates: fixture)` has
      title `"86.11 EUR"`, kind label `"Currency"`, subtitle starting with
      `"100 USD → EUR · rate updated "`, `copyText == "86.11"`; with `rates: nil` it is nil.
11. `README.md`: extend the calculator paragraph with currency examples and add a short
    "Exchange rates" note under Usage: rates are fetched from open.er-api.com at most every
    six hours, cached in `~/Library/Application Support/odd-frog/rates.json`, and the row shows
    the rate's age; without a cache the currency form does nothing.

## Constraints
- No code comments of any kind, in any file.
- Swift 6 strict concurrency; `OddFrogCore` stays AppKit-free; tests never touch the network
  (the HTTP provider is exercised only through `parse`). No new dependencies.
- Braces on every `if`/`guard` body in new code.
- Swift Testing only; use `Bundle.module` for the fixture.
- Never block the main actor on the store; all store calls are `await`ed from `Task`s in
  `AppDelegate`.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes (from the repo root).
- `swift build -c release` succeeds.
- Manual after `make run`: `~/Library/Application Support/odd-frog/rates.json` appears within
  a few seconds of launch and `~/Library/Logs/odd-frog.log` has a `rates:` line. `100 usd in eur`
  → "86.xx EUR" first, mint `$` tile, kind "Currency", subtitle ending "rate updated … ago";
  ↩ then ⌘V pastes the two-decimal number. `200 eur to rsd` → about 23,4xx RSD. Turn Wi-Fi
  off, relaunch: the same rows still appear from the cache. Delete `rates.json`, stay offline,
  relaunch: `100 usd in eur` shows only search results; the log has one `rates refresh failed`
  line.

## Out of scope
- Choosing a provider or base currency in Settings; API keys; historical rates; crypto.
- Currency symbols in the output (ISO codes only); locale-specific currency formatting.
- Retrying failed refreshes on a timer; the next panel show retries.

## Open questions
none
