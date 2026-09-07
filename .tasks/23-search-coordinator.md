# Task: Plugin system rework 5/13 — the search coordinator

Fifth of thirteen tasks (19–31). Requires tasks 19–22: `QuerySpec`/`QueryRole`/`QueryActivation`
in `OddFrogPluginAPI`, the generic `LauncherItem` and `LegacyAdapters`, `PluginRegistry`, and
`PluginRuntime.query/cancel` plus its `onRefreshRequested` event.

## Goal
Every keystroke goes through one `SearchCoordinator` that shows catalog matches immediately and
merges asynchronous provider results by role: an exclusive prefix handler suppresses everything
else, live answers precede catalog matches, fallbacks appear only when both are empty. Requests are
debounced 75 ms, one query is in flight per provider, superseded queries are cancelled, stale
responses are discarded, and a user-moved selection survives asynchronous updates. The three quick
features still implemented in the host (terminal `>`, calculator, web fallbacks) run as in-process
providers through the same path, so `SearchEngine` no longer knows about them.

## Files
- Sources/OddFrogCore/SearchCoordinator.swift          (create)
- Sources/OddFrogCore/SearchEngine.swift               (modify — catalog ranking only)
- Sources/OddFrogCore/ItemAdapters.swift               (modify — add `LegacyProviders`)
- Sources/OddFrogPluginAPI/PluginManifest.swift        (read — `QuerySpec` has a public memberwise init since task 19)
- Sources/OddFrog/LauncherViewController.swift         (modify — coordinator-driven results)
- Sources/OddFrog/AppDelegate.swift                    (modify — own coordinator + legacy providers, wire runtime providers)
- Tests/OddFrogCoreTests/SearchCoordinatorTests.swift  (create)
- Tests/OddFrogCoreTests/SearchEngineTests.swift       (modify — move the quick-row cases to the coordinator suite)
- Tests/OddFrogCoreTests/QuickActionTests.swift        (read — unchanged; `QuickAction` stays until task 29)

## Context
- `QuerySpec {role: QueryRole (.exclusive|.live|.fallback), prefix: String?, activation:
  QueryActivation (.all|.keyword), keywords: [String], priority: Int}` (task 19). If task 19 left its
  memberwise init internal, add `public init(role:prefix:activation:keywords:priority:)` with
  defaults `prefix nil`, `activation .keyword`, `keywords []`, `priority 100`.
- `SearchEngine.search(query:items:weights:maxResults:searchTemplate:rates:)` (task 20) still
  contains the `>` branch, the `QuickAction.calculation` row, and `fallbackResults`; `RankedItem
  {item, lexical, weight, exactAlias, argument}`; `SearchEngine.recent(items:weights:maxResults:)`
  serves the empty query; `order(_:_:)` sorts ranked results.
- `LegacyAdapters.quick(_ quick: QuickAction) -> LauncherItem` (task 20) builds transient items for
  `.openURL`, `.webSearch`, `.terminal`, `.calculation` with plugin ids `web`, `web`, `terminal`,
  `calculator`. `QuickAction.calculation(for:rates:)`, `QuickAction.fallbacks(for:searchTemplate:)`
  (returns the terminal action for `>` text or URL + web-search actions), `QuickAction.detectURL`.
- `LauncherViewController` (task 20 state): properties `items`, `weights`, `maxResults`,
  `searchTemplate`, `rates` each call `refresh(keepSelection: true)`; `refresh` calls
  `SearchEngine.search`, reloads the table, computes `scrollHeight`, shows the empty label "No
  results for “…”" when there are no rows and the query is non-blank, re-selects the previous id or
  row 0, and calls `onHeightChange`; `prepareForShow` clears the field and refreshes; `controlTextDidChange`
  refreshes; `control(_:textView:doCommandBy:)` handles moveUp/moveDown/insertNewline/
  cancelOperation/insertTab; `results` is `private(set)` and read by `AppDelegate.snapshotPanel`
  right after `controller.refresh()` for the `@run` debug path.
- `AppDelegate` (task 22 state): `wirePanel` sets `controller.maxResults`, `controller.searchTemplate
  = settings.search.url`; `applySettings` updates `controller.searchTemplate`; `refreshRates` sets
  `controller.rates`; `hidePanel()` calls `panel.dismiss()`; `runtime.onRefreshRequested` currently
  calls `rebuildItems()`; `registry.enabledPackages()` gives packages whose `manifest.query` may be
  set; `runtime.query(_:queryID:text:input:keyword:)` and `runtime.cancel(_:queryID:)` exist.
- Rules fixed for the whole rework:
  - Roles: `exclusive` — when the trimmed text starts with the provider's `prefix`, only that
    provider is queried with `input` = text after the prefix, trimmed; no catalog search. If several
    exclusive prefixes match, the lowest `priority` (then lowest id) wins. `live` — results shown
    above catalog matches. `fallback` — shown only when live and catalog results are both empty.
  - Activation: `all` — every non-empty query; `keyword` — the first whitespace-separated token,
    lowercased, equals one of `keywords`; `input` = remainder trimmed (may be empty); `keyword` param
    = the matched keyword. For `all`, `input == text` and `keyword == nil`.
  - Provider order among the same role: `priority` ascending, then plugin id ascending; order within
    a provider's result array is preserved. Providers cannot supply ranking scores.
  - Live/fallback requests are debounced 75 ms after the last keystroke; catalog results are shown
    immediately. One query in flight per provider; a newer query for that provider cancels the older
    (`cancel` is sent) and only the newest pending query survives. A response is applied only if its
    `queryID` is the provider's current one and the coordinator generation is unchanged.
  - Fallback providers are only asked when the catalog match list is empty; their results are only
    displayed while the live set is also empty.
  - Query results are transient. Closing the panel cancels in-flight queries and clears transient
    results. `maxResults` caps the merged list.
  - The empty query shows recent items only and queries no provider.

## Plan
1. `Sources/OddFrogCore/SearchCoordinator.swift`:
   ```swift
   public struct QueryProvider: Sendable, Hashable {
       public let pluginID: String
       public let spec: QuerySpec
       public init(pluginID: String, spec: QuerySpec)
   }
   public struct SearchResults: Sendable, Equatable {
       public let items: [RankedItem]
       public let pending: Bool
   }
   @MainActor public final class SearchCoordinator {
       public var catalog: [LauncherItem] = [] { didSet { rerunCatalog() } }
       public var weights: [String: Double] = [:] { didSet { rerunCatalog() } }
       public var maxResults = 8 { didSet { emit() } }
       public var providers: [QueryProvider] = []
       public var query: @MainActor (String, Int, String, String, String?) async throws -> [LauncherItem] = { _, _, _, _, _ in [] }
       public var cancel: @MainActor (String, Int) async -> Void = { _, _ in }
       public var onResults: ((SearchResults) -> Void)?
       public private(set) var current: SearchResults
       public init(debounce: TimeInterval = 0.075)
       public func update(query: String)
       public func refresh()
       public func close()
   }
   ```
   State: `text` (trimmed current query), `generation: Int`, `catalogResults: [RankedItem]`,
   `live: [String: [LauncherItem]]`, `fallback: [String: [LauncherItem]]`, `inflight: [String: (queryID:
   Int, task: Task<Void, Never>)]`, `nextQueryID`, `debounceTask: Task<Void, Never>?`, `exclusiveID:
   String?`. `update(query:)`: bump generation, cancel the debounce task, cancel all in-flight
   (`cancel` closure + task cancel), clear live/fallback. Empty text → `catalogResults =
   SearchEngine.recent(...)`, emit `pending: false`, return. Exclusive match → `exclusiveID` set,
   `catalogResults = []`, emit `pending: true`, schedule the dispatch. Otherwise `catalogResults =
   SearchEngine.search(query:items:weights:maxResults:)`, emit `pending: activated providers exist`,
   schedule the dispatch. Dispatch (after `debounce` seconds via `Task.sleep`, or immediately when
   `debounce == 0` or from `refresh()`): for each activated provider (exclusive: the one; else every
   live provider whose activation matches, plus fallback providers when `catalogResults.isEmpty`)
   assign a query id, cancel the provider's previous in-flight query, and run
   `query(pluginID, queryID, text, input, keyword)` in a `Task`; on return, if `generation` and the
   provider's current query id still match, store the items under `live`/`fallback` and emit;
   thrown errors store `[]`. `pending` is true while any dispatch is outstanding. `emit()` builds
   `SearchResults`: live items in provider order (RankedItem with lexical 0, weight 0, exactAlias
   false), then `catalogResults`, then fallback items only when both are empty, prefixed to
   `maxResults`; calls `onResults` and stores `current`. `refresh()`: re-dispatches the current
   text immediately without touching catalog results. `close()`: bump generation, cancel everything,
   clear live/fallback/exclusive, `text = ""`, no emit. `rerunCatalog()` recomputes `catalogResults`
   for the current text (recent for empty) and emits without re-querying providers.

2. `SearchEngine.swift`: `search(query:items:weights:maxResults:)` — remove `searchTemplate` and
   `rates` parameters, the `>` branch, the `calculation` row, and `fallbackResults`; an empty query
   still returns `recent`. Make `recent` `public`.

3. `ItemAdapters.swift`: add
   ```swift
   @MainActor public final class LegacyProviders {
       public static let pluginIDs: Set<String> = ["terminal", "calculator", "web"]
       public var searchTemplate: String?
       public var rates: CurrencyRates?
       public var providers: [QueryProvider]
       public init()
       public func query(pluginID: String, text: String, input: String) -> [LauncherItem]
   }
   ```
   `providers` = terminal (`.exclusive`, prefix `>`, activation `.all`, priority 10), calculator
   (`.live`, `.all`, priority 10), web (`.fallback`, `.all`, priority 100). `query`: terminal →
   `input.isEmpty ? [] : [LegacyAdapters.quick(.terminal(input))]`; calculator →
   `QuickAction.calculation(for: text, rates:)` mapped to one item or `[]`; web →
   `QuickAction.fallbacks(for: text, searchTemplate:)` mapped (the `>` case cannot occur here because
   the exclusive provider owns it).

4. `LauncherViewController.swift`: `init(icons:coordinator:)`; `items`/`weights`/`maxResults` become
   pass-throughs to `coordinator.catalog`/`weights`/`maxResults` (drop their `didSet` refresh); delete
   `searchTemplate` and `rates`. `coordinator.onResults = { [weak self] in self?.apply($0) }`.
   `refresh(keepSelection:)` becomes `coordinator.update(query: searchField.stringValue)` (the catalog
   pass calls `apply` synchronously, so `results` is populated on return as before). `apply(_:)`:
   `results = $0.items`, reload, `scrollHeight`, empty state only when `rows == 0 && !pending &&
   query non-blank`, `hairline` as before, selection: if `userMovedSelection` and the previously
   selected id is present → keep it, else row 0; `onHeightChange`. `userMovedSelection` is set by
   moveUp/moveDown/moveToBeginning/moveToEnd and by `select(row:)` from clicks, and cleared in
   `controlTextDidChange`, `prepareForShow`, and `fill`. Add `func panelDidHide()` →
   `coordinator.close()`.

5. `AppDelegate.swift`: `private let legacyProviders = LegacyProviders()`, `private let coordinator
   = SearchCoordinator()`, `controller = LauncherViewController(icons: icons, coordinator: coordinator)`.
   `wirePanel`: `coordinator.query = { [weak self] id, qid, text, input, keyword in guard let self
   else { return [] }; if LegacyProviders.pluginIDs.contains(id) { return legacyProviders.query(pluginID:
   id, text: text, input: input) }; return try await runtime.query(id, queryID: qid, text: text,
   input: input, keyword: keyword) }`; `coordinator.cancel = { [weak self] id, qid in guard let self,
   !LegacyProviders.pluginIDs.contains(id) else { return }; await runtime.cancel(id, queryID: qid) }`;
   `legacyProviders.searchTemplate = settings.search.url`. Add `refreshProviders()` = `coordinator.providers
   = legacyProviders.providers + registry.enabledPackages().compactMap { package in package.manifest?.query
   .map { QueryProvider(pluginID: package.id, spec: $0) } }`, called from `rebuildItems()`.
   `applySettings`: `legacyProviders.searchTemplate = …` then `coordinator.refresh()`. `refreshRates`:
   set `legacyProviders.rates` then `coordinator.refresh()`. `runtime.onRefreshRequested = { [weak
   self] _ in self?.coordinator.refresh() }`. `hidePanel()`: `controller.panelDidHide()` before
   `panel.dismiss()`. `snapshotPanel`'s `@run` path: after `controller.refresh()` wait 0.2 s
   (`DispatchQueue.main.asyncAfter`) before reading `controller.results.first`, so debounced rows are
   included.

6. Tests:
   - `SearchCoordinatorTests` (`@MainActor`, coordinator with `debounce: 0` unless stated). A
     `Recorder` (`final class`, `NSLock`-guarded) stores queries `(pluginID, queryID, text, input,
     keyword)` and cancels; a helper installs `query`/`cancel` closures that look up a per-plugin
     `[LauncherItem]` answer and an optional delay (`Task.sleep`) or an error. A `collect()` helper
     awaits until `current.pending == false` (poll with `Task.sleep(10 ms)`, 2 s limit). Items come
     from `LegacyAdapters.apps` / a small `PluginItem` factory. Cases:
     - catalog matches are emitted synchronously from `update` and `pending` is true while a live
       provider is outstanding;
     - live results precede catalog matches and two live providers order by priority then id;
     - exclusive prefix `>`: catalog not searched (`Recorder` shows only the exclusive query, input
       stripped), other live providers not queried, `>` alone yields no items;
     - keyword activation: `kp 3000` → query with keyword `kp`, input `3000`; `kpx` → not queried;
       `all` activation gets `input == text`;
     - fallback queried only when catalog is empty; fallback items hidden when a live provider
       returned items; shown when live is empty;
     - stale discard: provider answering after 100 ms while `update` was called again → the first
       answer never appears and `cancel` was recorded with the first query id;
     - `refresh()` re-queries with a new query id and keeps catalog results;
     - `close()` cancels in-flight and `current` no longer changes when the delayed answer arrives;
     - a throwing provider contributes nothing and `pending` returns to false;
     - `maxResults` caps live + catalog;
     - debounce 0.075: three `update` calls within 20 ms produce exactly one provider query.
   - Port from `SearchEngineTests` to the coordinator suite using `LegacyProviders` (template
     `https://duckduckgo.com/?q={query}`): `noMatchYieldsFallbacks` (web search item, plugin `web`),
     `terminalPrefixBypassesItems` (`>uptime` → one `terminal:run` item titled "Run in Terminal" with
     subtitle `uptime`, even though an app named uptime exists), `calculatorRowComesFirst` (`2+2` →
     calculator item first, `commands:double-it` second), `calculatorRowReplacesFallbacks` (`2*3` →
     exactly one item titled `6`), `bareNumberStillSearches`. Remove those five from
     `SearchEngineTests` and drop the `searchTemplate`/`rates` arguments elsewhere in that file.

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `SearchCoordinator` and `LegacyProviders` are `@MainActor`; `OddFrogCore`
  never imports AppKit.
- Swift Testing only; coordinator tests use in-memory fake providers, no processes, no network.
- No new third-party dependencies.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes.
- `swift test --filter SearchCoordinatorTests` passes in under 10 s.
- Manual after `make run`: typing `saf` shows Safari at once; `2+2` shows the Calculator row above
  matches; `>uptime` shows only "Run in Terminal"; `zzzz` shows the web-search fallback; pressing ↓
  twice on `s` then waiting keeps the third row selected when results settle; hiding the panel and
  reopening shows recent items with no stale rows.

## Out of scope
- Bundled provider packages (tasks 25–28); removing `QuickAction`/`LegacyProviders` (task 29);
  provider-supplied ranking scores (never).

## Open questions
none
