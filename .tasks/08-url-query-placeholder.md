# Task: `{query}` placeholder in URL commands

Task 08 of the "user flow" series. Run before 09, which reuses `URLTemplate`.

## Goal
A URL command whose address contains `{query}` accepts the rest of the typed query as an
argument: `gh odd-frog` with `url = "https://github.com/search?q={query}"` opens the GitHub
search for `odd-frog`. Without an argument the placeholder is replaced by nothing. Config
files and the Manage Links sheet keep showing the literal `{query}`.

## Files
- Sources/OddFrogCore/URLTemplate.swift             (create)
- Sources/OddFrogCore/Item.swift                    (modify — `acceptsArgument`, `subtitle`)
- Sources/OddFrogCore/LinkEditor.swift              (modify — serialise `{query}` literally)
- Sources/OddFrog/ActionExecutor.swift              (modify — resolve the template)
- Sources/OddFrog/LauncherViewController.swift      (modify — show the typed query on the row)
- Sources/OddFrog/LinkManagerController.swift       (modify — display + helper text)
- Tests/OddFrogCoreTests/URLTemplateTests.swift     (create)
- Tests/OddFrogCoreTests/SearchEngineTests.swift    (modify — add one test)
- Tests/OddFrogCoreTests/LinkEditorTests.swift      (modify — add one test)
- Sources/OddFrogCore/Config.swift                  (read — `ConfigParser.build` parses `url` with `URL(string:)`)
- Sources/OddFrogCore/SearchEngine.swift            (read — `splits` and `acceptsArgument` drive argument parsing)
- Resources/config.example.toml, README.md          (modify — document the placeholder)

## Context
- Swift 6 strict concurrency; Core target has no AppKit. Tests use Swift Testing (`@Test`,
  `#expect`), one `struct XTests` per file, `@testable import OddFrogCore`.
- Verified on this toolchain: `URL(string: "https://duckduckgo.com/?q={query}")` succeeds and
  yields `absoluteString == "https://duckduckgo.com/?q=%7Bquery%7D"`, `host == "duckduckgo.com"`.
  So `ConfigParser` already accepts such URLs unchanged; the placeholder survives as the
  percent-encoded `%7Bquery%7D`. `LinkDraft.command()` uses the same `URL(string:)` path.
- `CommandAction.url(URL)` is used in: `LauncherItem.subtitle` (via `webAddress`, host + path
  with trailing slashes trimmed), `kindLabel`, `ActionExecutor.run` (`NSWorkspace.shared.open`),
  `LinkEditor.serialized` (writes `url.absoluteString` to config.toml), `LinkManagerController`
  (`loadSelection`, table cells), `SettingsWindowController.showLinks`, `AppDelegate.applyLink`.
- `LauncherItem.acceptsArgument` is true only for `.script` with an argument spec.
  `SearchEngine.search` uses it to try `"<head> <tail>"` splits and puts the tail into
  `RankedItem.argument`. `ActionExecutor.run(_:argument:)` receives it.
- `LauncherViewController.detail(for:)` builds the second row line; for scripts with a typed
  argument it shows `"<placeholder>:"` plus the value in `valueLabel`. Commands currently
  only show `subtitles[id]`.
- `LinkEditor.serialized` encodes `Entry(name, aliases, url: url.absoluteString)` through
  `TOMLEncoder`; `LinkEditor.updating` re-parses the result and compares `Config` values, so a
  serialised `{query}` must parse back to the same `URL` (it does: both spellings yield the
  same `absoluteString`).
- `LinkManagerController` helper text: "Web links open in your default browser. App links open
  in the app registered for that URL."
- `swift test` currently runs 56 tests and passes.

## Plan
1. Create `Sources/OddFrogCore/URLTemplate.swift`:
   `public enum URLTemplate` with `public static let placeholder = "{query}"`,
   `static let encoded = "%7Bquery%7D"`,
   `public static func accepts(_ url: URL) -> Bool` (absoluteString contains `encoded`),
   `public static func display(_ url: URL) -> String` (absoluteString with `encoded` → `{query}`),
   `public static func encode(_ query: String) -> String` (percent-encode with allowed set =
   alphanumerics plus `-._~`, so spaces become `%20` and `&`, `+`, `/` are escaped),
   `public static func resolve(_ url: URL, query: String) -> URL` (replace every `encoded` in
   `absoluteString` with `encode(query)`; fall back to `url` if `URL(string:)` fails),
   `public static func resolve(template: String, query: String) -> URL?` (replace every literal
   `{query}` in the string with `encode(query)`, then `URL(string:)`; nil when the result has no
   scheme). Task 09 uses the last one for the web-search setting.
2. `Item.swift` — `acceptsArgument` returns true also for `.command` whose action is `.url(url)`
   with `URLTemplate.accepts(url)`. In `webAddress`, replace `URLTemplate.encoded` with
   `URLTemplate.placeholder` in the returned text so a placeholder in the path reads
   `example.com/{query}`.
3. `ActionExecutor.run` — for `.url(let url)`: open `URLTemplate.accepts(url) ?
   URLTemplate.resolve(url, query: argument ?? "") : url`. `.path` keeps opening as is.
4. `LauncherViewController.detail(for:)` — for a `.command` result with `result.argument`
   non-nil, return `DetailLine(detail: "Query:", value: argument)`; otherwise keep the subtitle.
5. `LinkEditor.serialized` — write `URLTemplate.display(url)` instead of `absoluteString`.
6. `LinkManagerController` — use `URLTemplate.display` for `urlField.stringValue` in
   `loadSelection` and for the "url" column text. Append to the helper text: " Put {query} in
   a URL to insert what you type after the alias, for example gh odd-frog."
7. Tests:
   - `URLTemplateTests.swift`: `accepts`/`display` round trip for
     `https://github.com/search?q={query}`; `encode("odd frog & co/+") == "odd%20frog%20%26%20co%2F%2B"`;
     `resolve(url, query: "a b").absoluteString == "https://github.com/search?q=a%20b"`;
     `resolve(template: "https://duckduckgo.com/?q={query}", query: "x") ` has host
     `duckduckgo.com` and query `q=x`; `resolve(template: "no scheme {query}", query: "x") == nil`.
   - `SearchEngineTests.swift`: a `.command` item "GitHub" alias `gh` with the search URL;
     query `gh odd-frog` returns it first with `argument == "odd-frog"`; query `gh` returns
     `argument == nil`; a plain `https://github.com` command never receives an argument.
   - `LinkEditorTests.swift`: adding a link whose URL contains `{query}` writes the literal
     `{query}` into the text (not `%7B`), and `ConfigParser.parse` of the result yields an
     `acceptsArgument` command.
8. `Resources/config.example.toml` — add a fourth command "GitHub Search", aliases `["ghs"]`,
   `url = "https://github.com/search?q={query}"`. `README.md` Config section: one sentence on
   `{query}` and the `gh odd-frog` example, in the Links subsection as well.

## Constraints
- No code comments of any kind. Do not touch the two existing comments in `LinkEditor.swift`.
- Swift 6 strict concurrency; Core types stay `Sendable`. No AppKit in Core. No new dependencies.
- Tests: Swift Testing only (`@Test`/`#expect`), no XCTest.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes with the new tests added (56 + at least 3).
- `swift build -c release` succeeds.
- Manual after `make run` with the updated example command in `~/.config/odd-frog/config.toml`:
  type `ghs odd-frog` → the row shows "Query: odd-frog"; ↩ opens
  `https://github.com/search?q=odd-frog`. `ghs` alone opens `https://github.com/search?q=`.
  Settings → Manage Links shows the URL with a literal `{query}`; saving it unchanged keeps
  the literal in `config.toml`.

## Out of scope
- Multiple named placeholders; placeholders in `path` or `command` entries.
- The fallback web search itself (task 09).

## Open questions
none
