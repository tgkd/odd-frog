# Task: Plugin system rework 10/13 — extract the Calculator into its own library and plugin

Tenth of thirteen tasks (19–31). Requires tasks 19–27 to be complete: the plugin contract
(`OddFrogPluginAPI`), generic `LauncherItem`, discovery/registry/runtime, the search coordinator,
config v2 with `PluginSettingsStore`, and the windows/web/terminal/applications/scripts/commands
packages already extracted. After this task the host has no arithmetic, unit, or currency code
left; the calculator is a bundled persistent provider that can be replaced without rebuilding
the host.

## Goal
Typing `2+2`, `100 km in mi`, or `100 usd in eur` still shows the same Calculator / Units /
Currency row first, Return still copies the result, and currency rates are still fetched at most
every six hours in the background. All of that now runs inside the `OddFrogCalculatorPlugin`
process, built on a new `OddFrogCalculator` library. `OddFrogCore` and `OddFrog` contain no
`Arithmetic`, `UnitConversion`, `Currency*`, `QuickAction.calculation`, or `CalculationKind`
symbols, and `swift test` passes with the moved suites running under `OddFrogCalculatorTests`.

## Files
- Package.swift                                                    (modify — two new targets, one new test target, resource move)
- Sources/OddFrogCalculator/Arithmetic.swift                       (create via `git mv` from Sources/OddFrogCore/Arithmetic.swift)
- Sources/OddFrogCalculator/UnitConversion.swift                   (create via `git mv` from Sources/OddFrogCore/UnitConversion.swift)
- Sources/OddFrogCalculator/UnitRegistry.swift                     (create via `git mv` from Sources/OddFrogCore/UnitRegistry.swift)
- Sources/OddFrogCalculator/CurrencyRates.swift                    (create via `git mv` from Sources/OddFrogCore/CurrencyRates.swift)
- Sources/OddFrogCalculator/CurrencyRateStore.swift                (create via `git mv` from Sources/OddFrogCore/CurrencyRateStore.swift; modify)
- Sources/OddFrogCalculator/CurrencyConversion.swift               (create via `git mv` from Sources/OddFrogCore/CurrencyConversion.swift)
- Sources/OddFrogCalculator/CalculatorQuery.swift                  (create — query → `PluginItem`)
- Sources/OddFrogCalculatorPlugin/main.swift                       (create)
- Sources/OddFrogCalculatorPlugin/CalculatorHandler.swift          (create)
- Plugins/calculator/plugin.toml                                   (create)
- Tests/OddFrogCalculatorTests/ArithmeticTests.swift               (create via `git mv` from Tests/OddFrogCoreTests/ArithmeticTests.swift; modify import)
- Tests/OddFrogCalculatorTests/UnitConversionTests.swift           (create via `git mv` from Tests/OddFrogCoreTests/UnitConversionTests.swift; modify import)
- Tests/OddFrogCalculatorTests/CurrencyTests.swift                 (create via `git mv` from Tests/OddFrogCoreTests/CurrencyTests.swift; modify)
- Tests/OddFrogCalculatorTests/CalculatorQueryTests.swift          (create)
- Tests/OddFrogCalculatorTests/Fixtures/rates.json                 (create via `git mv` from Tests/OddFrogCoreTests/Fixtures/rates.json)
- Tests/OddFrogCoreTests/QuickActionTests.swift                    (modify — drop calculation tests)
- Tests/OddFrogCoreTests/SearchEngineTests.swift                   (modify — drop calculator cases if any remain)
- Tests/OddFrogCoreTests/SearchCoordinatorTests.swift              (modify — drop the calculator-specific case if task 23 added one)
- Sources/OddFrogCore/QuickAction.swift                            (modify — remove `calculation(for:rates:)` and `CalculationKind`)
- Sources/OddFrogCore/SearchEngine.swift                           (modify — remove `rates` parameter)
- Sources/OddFrogCore/ItemAdapters.swift                           (modify — remove the calculator entries from `LegacyProviders` and `LegacyAdapters.quick`, and `LegacySettings` currency accessor)
- Sources/OddFrog/LauncherViewController.swift                     (modify — remove `rates`)
- Sources/OddFrog/AppDelegate.swift                                (modify — remove `rates` store and `refreshRates`)
- Sources/OddFrog/IconCache.swift                                  (modify — remove any calculator-specific tile branch left over)
- Sources/OddFrog/SettingsWindowController.swift                   (modify — remove the currency switch)
- Makefile                                                         (modify — bundle the provider)
- README.md                                                        (modify — rates cache path)
- Sources/OddFrogWebPlugin/WebHandler.swift                        (read — provider structure to mirror, created by task 25)
- Sources/OddFrogPluginAPI/PluginServer.swift                      (read — `PluginHandler` protocol, created by task 19)
- Plugins/web/plugin.toml                                          (read — manifest shape to mirror, created by task 25)

## Context
- Today's calculator lives in `OddFrogCore`: `Arithmetic.evaluate(_:) -> Double?`,
  `UnitConversion.evaluate(_:) -> UnitConversion?` (`input`, `value`, `result`),
  `CurrencyConversion.evaluate(_:rates:) -> CurrencyConversion?` (`input`, `value`, `result`,
  `updated`), `CurrencyRates` (`base`, `timestamp`, `fetched`, `rates`, `convert(_:from:to:)`),
  `CurrencyRateProvider` protocol, `ExchangeRateAPIProvider` (endpoint
  `https://open.er-api.com/v6/latest/USD`, `parse(_:)`), and `actor CurrencyRateStore` with
  `staleAfter = 6 * 3600`, `static var defaultURL` (Application Support `odd-frog/rates.json`),
  `init(url:provider:)`, `current()`, `refreshIfStale(now:)`. All six files import only Foundation.
- Presentation rules currently in `QuickAction` (Sources/OddFrogCore/QuickAction.swift) that the
  plugin must reproduce byte-for-byte:
  - arithmetic: title `value.formatted(.number.precision(.fractionLength(0...6)))`, subtitle = the
    trimmed input, kind `Calculator`, copy text
    `value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))`;
  - units: title `conversion.result`, subtitle `conversion.input`, kind `Units`, copy text as
    arithmetic;
  - currency: title `exchange.result`, subtitle `"\(input) · rate updated
    \(updated.formatted(.relative(presentation: .numeric)))"`, kind `Currency`, copy text
    `value.formatted(.number.grouping(.never).precision(.fractionLength(2)))`;
  - order of evaluation: arithmetic, then units, then currency (only when rates exist); empty or
    whitespace-only input → nil.
- Icons today (Sources/OddFrog/IconCache.swift): arithmetic `plus.forwardslash.minus` on
  `.systemOrange` size 13, units `ruler` on `.systemGreen` size 13, currency `dollarsign` on
  `.systemMint` size 13. With `IconSpec.symbol(name:color:size:)` these become
  `{symbol, color: "orange"|"green"|"mint", size: 13}`; `IconCache` (task 20) renders any
  `IconSpec` generically, so no host change is needed for the pictures themselves.
- Host-side calculator plumbing to remove: `AppDelegate.rates`
  (`CurrencyRateStore(url:provider:)`), `AppDelegate.refreshRates()` and its calls from
  `applicationDidFinishLaunching`, `applySettings`, and `showPanel`; `LauncherViewController.rates`;
  the `rates:` parameter of `SearchEngine.search`; `LegacySettings` currency accessor
  (`plugins["calculator"].values["currency"]`, task 24); the "calculator" in-process provider inside
  `LegacyProviders` and the `.calculation` branch of `LegacyAdapters.quick` (tasks 20/23); the
  `currencySwitch`/`currencyHelper`/`toggleCurrency`/`refreshWindowManagement` currency line in
  `SettingsWindowController`.
- Bundled provider pattern (task 25): an executable target whose `main.swift` does
  `await PluginServer.serve(Handler())`; the handler is a `final class` conforming to
  `PluginHandler` (Sources/OddFrogPluginAPI/PluginServer.swift) with `initialize`, `query`,
  `configure`, `cancel`, `shutdown`. Settings arrive as `[String: JSONValue]` in
  `InitializeParams.settings` and `ConfigureParams.settings`. Events are sent with
  `PluginServer.emit(Event(event: EventName.refresh, params: nil))`; the server instance is passed to
  the handler after construction (mirror how `WebHandler` receives it).
- The runtime (task 22) passes `data_dir` = `~/Library/Application Support/odd-frog/v2/plugins/<id>/`
  in `InitializeParams.dataDir` and calls `configure` whenever the effective settings change
  (task 24). `onRefreshRequested` re-runs the current query through the coordinator (task 23).
- Query items from a live provider are transient: `recordable = false` and never overridable.
- Manifest shape reference (task 25's `Plugins/web/plugin.toml`): `[plugin]`, `[provider]`,
  `[query]`, `[services]`, `[[settings]]` per `Sources/OddFrogPluginAPI/ManifestParser.swift`.
- Decision recorded here: `OddFrogCalculator` depends on `OddFrogPluginAPI` so that the query →
  `PluginItem` mapping is testable in a library target (SwiftPM cannot unit-test an executable
  target). The API library is host-independent, so this keeps the "feature code is not a host
  dependency" rule intact. Alternative rejected: keeping the mapping inside the executable and
  testing only the numeric layers, which would leave title/subtitle/copy-text formatting untested.
- `Tests/OddFrogCoreTests/Fixtures/rates.json` is currently declared through
  `resources: [.copy("Fixtures")]` on `OddFrogCoreTests`; after this task that directory still
  holds `providers/*.sh` (task 22), so the declaration stays and the calculator test target gets
  its own `resources: [.copy("Fixtures")]`.
- Makefile after task 27 loops over bundled plugin ids copying `Plugins/<id>/` into
  `Contents/PlugIns/<id>/`, then copies `.build/release/<Executable>` next to each manifest and
  signs it before signing the app. Add `calculator` → `OddFrogCalculatorPlugin` to that list in the
  same style the Makefile already uses for `web` → `OddFrogWebPlugin`.
- Fixture rates (`rates.json`): `USD 1`, `EUR 0.861072`, `RSD 100.993275`, `GBP 0.74`, `JPY 147.2`,
  `time_last_update_unix 1788739351`; `100 usd in eur` → `86.11 EUR`.

## Plan
1. `Package.swift`:
   - Add `.target(name: "OddFrogCalculator", dependencies: ["OddFrogPluginAPI"])`.
   - Add `.executableTarget(name: "OddFrogCalculatorPlugin", dependencies: ["OddFrogPluginAPI",
     "OddFrogCalculator"])`.
   - Add `.testTarget(name: "OddFrogCalculatorTests", dependencies: ["OddFrogCalculator"],
     resources: [.copy("Fixtures")])`.
   - Leave `OddFrogCoreTests`'s `resources: [.copy("Fixtures")]` in place (the providers fixtures
     from task 22 live there).
2. Move the six source files with `git mv` into `Sources/OddFrogCalculator/`. Edit
   `CurrencyRateStore.swift`: delete `static var defaultURL`; everything else unchanged. No other
   edits to the moved files (they stay `public`).
3. Create `Sources/OddFrogCalculator/CalculatorQuery.swift`:
   ```swift
   import Foundation
   import OddFrogPluginAPI

   public enum CalculatorQuery {
       public static let itemID = "result"
       public static func item(for text: String, rates: CurrencyRates?) -> PluginItem?
   }
   ```
   `item(for:rates:)` trims the text, returns nil when empty, then tries `Arithmetic.evaluate`,
   `UnitConversion.evaluate`, and (when `rates` is non-nil) `CurrencyConversion.evaluate` in that
   order, and builds a `PluginItem` with `id: itemID`, `title`, `subtitle`, `kind` (`"Calculator"`,
   `"Units"`, `"Currency"`), `icon: .symbol(name:color:size: 13)` with names/colors from Context,
   `aliases: []`, `action: .copy(text: copyText)`, `secondary: nil`, `recordable: false`. Keep the
   three formatting rules from Context in private helpers on this enum.
4. Create `Plugins/calculator/plugin.toml`:
   ```toml
   [plugin]
   id = "calculator"
   name = "Calculator"
   version = "1.0.0"
   api = 1
   description = "Arithmetic, unit conversion and currency conversion as you type."

   [provider]
   mode = "persistent"
   executable = "OddFrogCalculatorPlugin"

   [query]
   role = "live"
   activation = "all"
   priority = 10

   [services]
   uses = ["clipboard"]

   [[settings]]
   key = "currency"
   type = "bool"
   title = "Currency conversion"
   description = "Rates from exchangerate-api.com, refreshed at most every six hours."
   default = true
   ```
5. Create `Sources/OddFrogCalculatorPlugin/CalculatorHandler.swift`: `final class CalculatorHandler:
   PluginHandler` (mark `@unchecked Sendable` only if an `NSLock`-guarded state box is used; prefer
   an internal `actor State` holding `rates: CurrencyRates?`, `currencyEnabled: Bool`, `store:
   CurrencyRateStore?`, `refreshLoop: Task<Void, Never>?`).
   - `initialize(_ params)`: create `CurrencyRateStore(url: URL(fileURLWithPath: params.dataDir)
     .appendingPathComponent("rates.json"), provider: ExchangeRateAPIProvider())`, read
     `currency` from `params.settings` (`.bool`, default true), seed `rates = await store.current()`
     when enabled, start the refresh loop when enabled, return `InitializeResult(api:
     PluginAPI.version, name: "Calculator", version: "1.0.0")`.
   - Refresh loop: `Task` that calls `store.refreshIfStale()`; when it returns a table different
     from the cached one, stores it and calls `server.emit(Event(event: EventName.refresh, params:
     nil))`; then sleeps `CurrencyRateStore.staleAfter` seconds and repeats until cancelled. The
     first iteration runs immediately after `initialize` returns (do not block `initialize` on the
     network).
   - `query(_ params)`: `CalculatorQuery.item(for: params.input, rates: currencyEnabled ? rates :
     nil)` → `QueryResult(items: item.map { [$0] } ?? [])`.
   - `configure(_ params)`: update `currencyEnabled`; turning it off cancels the loop and sets
     `rates = nil`; turning it on re-seeds from the store and restarts the loop.
   - `cancel`: no-op (queries are synchronous). `shutdown`: cancel the loop.
   - Diagnostics (refresh failures, rate counts) go to `FileHandle.standardError` as single lines.
6. Create `Sources/OddFrogCalculatorPlugin/main.swift` mirroring `Sources/OddFrogWebPlugin/main.swift`
   (construct the handler, hand it the server, `await server.run()`).
7. Host removals (each must compile after the step):
   - `Sources/OddFrogCore/QuickAction.swift`: delete `CalculationKind`, the `.calculation` case
     and every switch arm for it, `calculation(for:rates:)`, and the private `title/subtitle/copyText`
     helpers. (`detectURL`/`fallbacks`/`terminal` remain until task 29.)
   - `Sources/OddFrogCore/SearchEngine.swift`: remove the `rates:` parameter and any remaining
     calculation branch.
   - `Sources/OddFrogCore/ItemAdapters.swift`: remove the calculator provider from
     `LegacyProviders`, the `.calculation` branch from `LegacyAdapters.quick`, and the currency
     accessor from `LegacySettings`.
   - `Sources/OddFrog/LauncherViewController.swift`: remove the `rates` property and its use.
   - `Sources/OddFrog/AppDelegate.swift`: remove `rates`, `refreshRates()`, and the three call
     sites.
   - `Sources/OddFrog/SettingsWindowController.swift`: remove `currencySwitch`, `currencyHelper`,
     `toggleCurrency`, the currency row from the Extras `groupedBox`, and the currency line in
     `refreshWindowManagement`. The Extras box keeps the window-management row and access line
     until task 30 removes them.
   - `Sources/OddFrog/IconCache.swift`: delete any leftover calculator-specific branch; generic
     `IconSpec` rendering stays.
8. Tests:
   - `git mv` `ArithmeticTests.swift`, `UnitConversionTests.swift`, `CurrencyTests.swift`, and
     `Fixtures/rates.json` into `Tests/OddFrogCalculatorTests/`; change `@testable import
     OddFrogCore` to `@testable import OddFrogCalculator`.
   - In the moved `CurrencyTests.swift`, replace `currencyQueryBecomesACurrencyAction` with an
     equivalent that calls `CalculatorQuery.item(for: "100 usd in eur", rates: table)` and checks
     `title == "86.11 EUR"`, `kind == "Currency"`, `subtitle` has prefix `"100 USD → EUR · rate
     updated "`, `action == .copy(text: "86.11")`, and `item(for: "100 usd in eur", rates: nil) ==
     nil`.
   - Create `CalculatorQueryTests.swift`: `2+2` → title `4`, subtitle `2+2`, kind `Calculator`,
     id `result`, action `.copy(text: "4")`, `recordable == false`, icon
     `.symbol(name: "plus.forwardslash.minus", color: IconColor(rawValue: "orange")!, size: 13)`;
     `0.1+0.2` → title `0.3`; `100 km in mi` → title `62.1371 mi`, subtitle `100 km → mi`, kind
     `Units`, copy `62.137119`, icon `ruler`/green; `safari`, `42`, `""` → nil.
   - `Tests/OddFrogCoreTests/QuickActionTests.swift`: delete `arithmeticQueryBecomesACalculatorAction`,
     `calculatorTitleRoundsToSixPlaces`, `unitQueryBecomesAUnitsAction`,
     `plainTextAndBareNumbersAreNotCalculations`.
   - `SearchEngineTests.swift` / `SearchCoordinatorTests.swift`: delete any test that depends on the
     removed calculator provider (`calculatorRowComesFirst`, `calculatorRowReplacesFallbacks`,
     `bareNumberStillSearches` if they still exist after task 23; the coordinator's generic
     live-role tests already cover "live rows come first").
9. `Makefile`: add `calculator`/`OddFrogCalculatorPlugin` to the bundled plugin list so `make bundle`
   copies `Plugins/calculator/plugin.toml` and the signed executable into
   `Contents/PlugIns/calculator/`.
10. `README.md`: in the currency paragraph replace `~/Library/Application Support/odd-frog/rates.json`
    with `~/Library/Application Support/odd-frog/v2/plugins/calculator/rates.json`, and change the
    Settings sentence about "Currency" to say the switch lives on the Calculator plugin's page in
    Settings › Plugins (task 30 builds that page; the wording is correct once 30 lands and the
    setting is already editable in `settings.toml` as `[plugins.calculator] currency = false`).

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `OddFrogCalculator` imports only Foundation and `OddFrogPluginAPI`;
  the plugin executable imports Foundation, `OddFrogPluginAPI`, `OddFrogCalculator`.
- `OddFrogCore` stays AppKit-free and, after this task, free of any calculator symbol
  (`grep -rn 'Arithmetic\|UnitConversion\|UnitRegistry\|CurrencyRates\|CurrencyRateStore\|CurrencyConversion\|CalculationKind' Sources/OddFrogCore Sources/OddFrog` prints nothing).
- Swift Testing only; tests never touch the network (`ExchangeRateAPIProvider` is exercised only
  through `parse`).
- Use `git mv` for every moved file so history follows.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes; `swift test --filter OddFrogCalculatorTests` runs the four moved/new suites.
- `swift build -c release` succeeds and produces `.build/release/OddFrogCalculatorPlugin`.
- `make bundle` succeeds and `build/OddFrog.app/Contents/PlugIns/calculator/` contains `plugin.toml`
  and `OddFrogCalculatorPlugin`.
- Manual after `make run`: `2+2` shows a `4` row first with the orange calculator tile and kind
  "Calculator"; `100 km in mi` shows `62.1371 mi` with the green ruler tile; within a few seconds of
  launch `~/Library/Application Support/odd-frog/v2/plugins/calculator/rates.json` exists and
  `100 usd in eur` shows `8x.xx EUR` with the mint tile and a subtitle ending "ago"; Return then
  ⌘V pastes `86.11`-style text. Add `[plugins.calculator]\ncurrency = false` to
  `~/.config/odd-frog/v2/settings.toml`: without restarting, `100 usd in eur` shows only search
  results while `2+2` still works; `pgrep -f OddFrogCalculatorPlugin` shows one process the whole
  time. Turn Wi-Fi off and relaunch: the currency row still appears from the cache.

## Out of scope
- The Settings UI for the `currency` switch (task 30 renders manifest settings).
- Deleting the rest of `QuickAction`, `LegacyAdapters`, `LegacyProviders`, `LegacySettings`
  (task 29).
- Independent packaging of the calculator (`make plugin-calculator`, task 31).
- Any change to the calculator grammar, providers, or formatting.

## Open questions
none
