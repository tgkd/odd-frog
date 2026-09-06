# Task: Fallback rows when nothing matches, `>` runs in the terminal, configurable web search, no alphabetical fill on an empty query

Task 09 of the "user flow" series. Requires task 08 (`URLTemplate.resolve(template:query:)`).

## Goal
A query that matches no item still offers something to run: an "Open <url>" row when the text
looks like a URL, and a "Search for “<text>”" row that opens the web search configured in
Settings (default DuckDuckGo). A query starting with `>` shows a single "Run in Terminal" row
for the rest of the text. With an empty query the panel lists only items that have been used;
on a fresh install it shows just the search field.

## Files
- Sources/OddFrogCore/QuickAction.swift             (create)
- Sources/OddFrogCore/Item.swift                    (modify — new `LauncherItem.quick` case)
- Sources/OddFrogCore/SearchEngine.swift            (modify — fallbacks, `>` prefix, no fill)
- Sources/OddFrogCore/Settings.swift                (modify — `[search] url`)
- Sources/OddFrog/LauncherViewController.swift      (modify — `searchTemplate`, pass through)
- Sources/OddFrog/AppDelegate.swift                 (modify — thread the setting)
- Sources/OddFrog/SettingsWindowController.swift    (modify — "Web search" block in General)
- Sources/OddFrog/IconCache.swift                   (modify — icons for quick rows)
- Sources/OddFrog/ActionExecutor.swift              (modify — run quick rows, never record them)
- Tests/OddFrogCoreTests/QuickActionTests.swift     (create)
- Tests/OddFrogCoreTests/SearchEngineTests.swift    (modify — `emptyQueryShowsRecentThenAlphabetical`, new tests)
- Tests/OddFrogCoreTests/ScriptTests.swift          (modify — `settingsRoundTripAndApply`, `emptySettingsParse` must still pass)
- Sources/OddFrogCore/URLTemplate.swift             (read — from task 08)
- README.md                                         (modify)

## Context
- Swift 6 strict concurrency; Core has no AppKit; all `LauncherItem` payloads are
  `Sendable, Hashable`. Tests are Swift Testing.
- `LauncherItem` is an enum with `.app`, `.command`, `.script`. Every switch over it must be
  exhaustive: `id`, `title`, `subtitle`, `aliases`, `acceptsArgument`, `kindLabel`,
  `withAliases` in `Item.swift`; `IconCache.icon(for:)`; `ActionExecutor.run`;
  `LauncherViewController.detail(for:)` and `submit()` use `if case`. `SettingsWindowController`
  receives `allItems` from `AppDelegate.rebuildItems`, which never includes fallback rows.
- `SearchEngine.search(query:items:weights:maxResults:)`: empty trimmed query → `recent`,
  which lists used items by weight and then fills the remainder alphabetically (this fill is
  what must go). Non-empty → fuzzy ranking; returns `[]` when nothing matches.
  `RankedItem(item:lexical:weight:exactAlias:argument:)`; `order` sorts by exactAlias, score,
  weight, title. Existing test `emptyQueryShowsRecentThenAlphabetical` expects
  `["Mid", "Alpha"]` for `maxResults: 2` and must change to expect `["Mid"]`.
- `LauncherViewController.refresh()` shows the "No results for “q”" label when `results` is
  empty and the query is non-empty; `preferredHeight` collapses to the field alone when both
  are empty. With fallbacks present the label will rarely show, which is intended.
- `Settings` (settings.toml, hot-reloaded, written by the Settings window) has `scripts` and
  `items`; each nested struct hand-writes `init(from:)` with defaults so missing keys parse.
  `Settings.empty` must equal `try Settings.parse("")` (test `emptySettingsParse`).
  `serialized()` uses `TOMLEncoder`. `AppDelegate.applySettings(_:persist:)` receives changes
  from the window (`settingsWindow.onChange`) and from the file watcher; `rebuildItems` runs
  after either.
- Settings window General group (`makeGeneralGroup`, line ~208): two `settingBlock(title:
  control:helper:)` boxes ("Shortcut", "Launch at login") in a horizontal `NSStackView` with
  `fillEqually`, heights tied equal; controls are 24 pt high. Helpers are styled by
  `style(helper:)`. `present(settings:items:hotkey:)` seeds the controls; `commit()` calls
  `onChange?(settings)`. The window is 680 wide, min 560.
- `IconCache.tile(name:color:symbol:symbolSize:size:)` draws an SF Symbol on a rounded tile;
  `.url` commands use `("url", .systemTeal, "link", 14)`, `.shell` uses the `$` glyph tile.
- `ActionExecutor.record(_:)` writes frecency for an id; `runInTerminal(id:name:command:cwd:)`
  records on success. Quick rows must never be recorded, otherwise "quick:search:foo" ids pile
  up in `frecency.json` and show under the empty query.
- Decisions already made: default engine DuckDuckGo; the setting lives in settings.toml (not
  config.toml) and is edited in the Settings window; fallbacks appear only when no item
  matches; `>` bypasses item search entirely.

## Plan
1. Create `QuickAction.swift`:
   ```
   public enum QuickAction: Sendable, Hashable {
       case openURL(URL)
       case webSearch(query: String, url: URL)
       case terminal(String)
   }
   ```
   with `id` (`"quick:url:<absoluteString>"`, `"quick:search:<query>"`, `"quick:terminal:<text>"`),
   `title` ("Open <URLTemplate.display-style host+path>", "Search for “<query>”",
   "Run in Terminal"), `subtitle` (nil, the search URL's host, the command text), `kindLabel`
   ("URL", "Search", "Terminal"), and:
   - `public static func detectURL(_ text: String) -> URL?`: trimmed text with no whitespace;
     if it contains `://`, accept when `URL(string:)` has a scheme and either a host or a
     non-`http(s)` scheme; otherwise require a dot that is neither first nor last, a last label
     of two or more letters, only `[A-Za-z0-9.-]` before the first `/`, `?` or `:`, and return
     `URL(string: "https://" + text)`. `localhost:3000` and `3.14` yield nil.
   - `public static func fallbacks(for query: String, searchTemplate: String?) -> [QuickAction]`:
     trimmed query; if it starts with `>` return `[.terminal(rest)]` when `rest` is non-empty,
     else `[]`; otherwise `detectURL` → `.openURL`, then, when `searchTemplate` resolves via
     `URLTemplate.resolve(template:query:)`, `.webSearch`.
2. `Item.swift` — add `case quick(QuickAction)`; extend every switch: `id`/`title`/`subtitle`/
   `kindLabel` delegate to `QuickAction`; `aliases` is `[]`; `acceptsArgument` false;
   `withAliases` returns `self`.
3. `SearchEngine.search` — add `searchTemplate: String? = nil`. Empty query → `recent` without
   the alphabetical fill (delete the fill; keep sorting and `prefix(maxResults)`). Query with
   `>` prefix → return only the fallbacks. Otherwise rank as today and, if `ranked` is empty,
   return `fallbacks(for:)` mapped to `RankedItem(item: .quick($0), lexical: 0, weight: 0,
   exactAlias: false)`.
4. `Settings.swift` — add `public struct Search: Codable, Sendable, Equatable { public var url: String }`
   with `public static let defaultURL = "https://duckduckgo.com/?q={query}"`, default init and
   `init(from:)` that falls back to the default when the key is missing or empty; add
   `public var search: Search` to `Settings` (decoded with `decodeIfPresent ?? Search()`),
   coding key `search`. `Settings.empty` keeps equalling `parse("")`.
5. `LauncherViewController` — `var searchTemplate: String? { didSet { refresh(keepSelection: true) } }`
   (use `refresh()` if task 05 is absent) and pass it to `SearchEngine.search`. In
   `detail(for:)`, handle `.quick` before the `subtitles` lookup: fallback rows are not in
   `items`, so `subtitles[id]` is nil for them; return `item.subtitle.map { DetailLine(detail: $0) }`.
6. `AppDelegate` — in `wirePanel` and at the end of `applySettings`, set
   `controller.searchTemplate = settings.search.url`.
7. `SettingsWindowController` — add a third block "Web search" to the General row: an
   `NSTextField` (bezel `.roundedBezel`, single line, 24 pt) with placeholder
   `Settings.Search.defaultURL`, helper "Used when nothing matches. {query} is replaced with
   what you typed." On `controlTextDidEndEditing` for this field: trim; if the value resolves
   through `URLTemplate.resolve(template:query: "test")` and contains `{query}`, store it in
   `settings.search.url`, `commit()`, helper back to secondary colour; otherwise set the helper
   to "Enter a full URL containing {query}." in `.systemRed` and restore the field to the
   stored value. `present(...)` seeds the field. Tie the new block's height to the other two.
   `controlTextDidChange` currently checks `obj.object === filterField`; keep that guard so the
   filter path is untouched.
8. `IconCache.icon(for:)` — `.quick(.openURL)` → the existing `url` tile; `.webSearch` →
   `tile(name: "search", color: .systemIndigo, symbol: "magnifyingglass", symbolSize: 13)`;
   `.terminal` → the existing `shell` tile.
9. `ActionExecutor` — `.quick(.openURL(url))`, `.quick(.webSearch(_, url))` →
   `NSWorkspace.shared.open(url)`, `fail` on false; `.quick(.terminal(text))` →
   `runInTerminal(id: item.id, name: "Run in Terminal", command: text, cwd: nil)`. In
   `record(_:)`, return early when the id has the `quick:` prefix.
10. Tests:
    - `QuickActionTests.swift`: `detectURL` accepts `github.com`, `docs.swift.org/path`,
      `obsidian://open`, `https://x.y`; rejects `hello world`, `3.14`, `localhost:3000`,
      `.hidden`, `word.`. `fallbacks(for: "> ls -la", searchTemplate: t)` is exactly
      `[.terminal("ls -la")]`; `fallbacks(for: "odd frog", searchTemplate: t)` is one
      `.webSearch` whose url has query `q=odd%20frog`; with `searchTemplate: nil` and a
      non-URL query the result is empty.
    - `SearchEngineTests.swift`: rename the empty-query test to `emptyQueryShowsOnlyUsedItems`
      expecting `["Mid"]`; add `noMatchYieldsFallbacks` (query `zzzz` over `[app("Zed")]` with a
      template returns one `.quick(.webSearch)`), and `terminalPrefixBypassesItems` (query
      `>uptime` returns exactly one `.quick(.terminal("uptime"))` even though an item titled
      "uptime" exists).
    - `ScriptTests.settingsRoundTripAndApply`: extend to set `search.url` and assert it round
      trips through `serialized()` / `parse`.
11. `README.md` — Usage: fallbacks, `>` prefix, and that an empty query shows used items only.
    Settings section: "Web search" with the default and the `[search] url` key in the
    settings.toml example.

## Constraints
- No code comments of any kind.
- Swift 6 strict concurrency; Core stays AppKit-free; new Core types are `Sendable, Hashable`.
- Swift Testing only. No new dependencies.
- Settings window layout uses explicit constraints and `settingBlock`; no `NSStackView`
  changes beyond adding the third view to the existing horizontal stack.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes with the new and updated tests.
- `swift build -c release` succeeds.
- Manual after `make run`:
  1. Move `~/Library/Application Support/odd-frog/frecency.json` aside and relaunch: ⌥Space
     shows only the field. Launch one app; reopen: that app is the only row.
  2. Type `qwzx`: one row "Search for “qwzx”" with subtitle `duckduckgo.com`; ↩ opens
     `https://duckduckgo.com/?q=qwzx`.
  3. Type `github.com`: rows "Open github.com" and "Search for …"; ↩ on the first opens
     `https://github.com`.
  4. Type `>uptime` : a single "Run in Terminal" row; ↩ opens the terminal running `uptime`.
  5. Settings → Web search: enter `https://www.google.com/search?q={query}`, press Tab; the
     next fallback search uses Google; `settings.toml` contains `[search]` with that url.
     Enter `nope` → red helper, field reverts.
  6. `frecency.json` contains no `quick:` ids after steps 2–4.

## Out of scope
- Calculator, clipboard history, file search. Showing fallbacks below real matches.
- Per-engine names in the title (the host in the subtitle is enough).

## Open questions
none
