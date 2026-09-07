# Task: Plugin system rework 7/13 — first real packages: Windows, Web, Terminal

Seventh of thirteen tasks (19–31). Requires tasks 19–24. After this task three launcher features are
delivered by packages discovered from `Contents/PlugIns` instead of host code: the declarative
Windows package, and two persistent providers for web fallbacks and the exclusive `>` terminal
handler. Applications, commands, scripts and the calculator still run through the temporary host
adapters.

## Goal
`make run` builds and bundles `Plugins/windows`, `Plugins/web` and `Plugins/terminal` into
`build/OddFrog.app/Contents/PlugIns/<id>/`, the host discovers them, and the launcher behaves as
before: `>` shows "Run in Terminal", a URL-looking query shows "Open …", anything unmatched shows
"Search for …", and the ten Window items appear only while the Windows plugin is enabled. The host
no longer contains window item definitions, URL detection for fallbacks, or the `>` handler
(`QuickAction.detectURL` stays until task 29 for its tests only).

## Files
- Package.swift                                              (modify — two executable targets)
- Makefile                                                   (modify — bundle plugins, sign executables first)
- Plugins/windows/plugin.toml                                (create)
- Plugins/web/plugin.toml                                    (create)
- Plugins/terminal/plugin.toml                               (create)
- Sources/OddFrogWebPlugin/main.swift                        (create)
- Sources/OddFrogWebPlugin/WebHandler.swift                  (create)
- Sources/OddFrogWebPlugin/URLDetection.swift                (create — copies of `detectURL`, `URLTemplate.encode/resolve(template:)`)
- Sources/OddFrogTerminalPlugin/main.swift                   (create)
- Sources/OddFrogTerminalPlugin/TerminalHandler.swift        (create)
- Sources/OddFrogCore/ItemAdapters.swift                     (modify — drop windows adapter, web/terminal providers and quick cases)
- Sources/OddFrogCore/QuickAction.swift                      (modify — keep `detectURL` and `.calculation` only)
- Sources/OddFrogCore/WindowAction.swift                     (read — stays as task 20 left it; task 29 deletes the `WindowAction` enum)
- Sources/OddFrog/HostServices.swift                         (modify — cascade step from the requesting plugin's settings)
- Sources/OddFrog/AppDelegate.swift                          (modify — wiring; no window/web/terminal host code)
- Sources/OddFrog/IconCache.swift                            (read — icon rendering from `IconSpec` created by task 20)
- Sources/OddFrog/WindowManager.swift                        (read — unchanged here; task 29 reshapes `perform`)
- Tests/OddFrogCoreTests/BundledManifestsTests.swift         (create)
- Tests/OddFrogCoreTests/WindowLayoutTests.swift             (read — unchanged; the manifest test duplicates `actionIdsAndTitles` for the manifest, task 29 deletes the original)
- Tests/OddFrogCoreTests/QuickActionTests.swift              (modify — drop terminal/fallback tests; keep `detectURL*`)
- Tests/OddFrogCoreTests/ItemAdaptersTests.swift             (modify — drop windows/quick-fallback cases)
- README.md                                                  (modify — mention the Plugins folder and the three packages)

## Context
- Design fixed by earlier tasks: manifest schema, `PluginItem`, `PluginAction`, `IconSpec`,
  `PluginServer`/`PluginHandler` (`Sources/OddFrogPluginAPI/`, task 19); discovery from
  `Bundle.main.builtInPlugInsURL` and `~/.config/odd-frog/plugins` (`PluginDiscovery`, task 21);
  `PluginRuntime.sync(enabled:)` / `query(_:queryID:text:input:keyword:)` / `cancel(_:queryID:)` (tasks 22, 24); `SearchCoordinator`
  with `providers: [QueryProvider]` built from manifests' `QuerySpec` (task 23), where the temporary
  `LegacyProviders` (in `ItemAdapters.swift`) still supplies in-process providers for `terminal`,
  `calculator` and `web`; `PluginSettingsStore.effective(for:)` (task 24) with `LegacySettings`
  reading `plugins["windows"].enabled` / `cascade_step` and `plugins["web"].values["search_url"]`.
- Today's window items (Sources/OddFrogCore/WindowAction.swift `WindowAction.all`): Left ½, Right ½,
  Left ⅔, Right ⅔, Top ½, Bottom ½, Top ¾, Bottom ¾, Maximize, Tidy Windows (subtitle "Cascade every
  window on this screen"), kind label "Window". Icons (Sources/OddFrog/IconCache.swift): purple tiles
  with `rectangle.lefthalf.filled`, `rectangle.righthalf.filled`, `rectangle.tophalf.filled`,
  `rectangle.bottomhalf.filled`, `rectangle.fill` (maximize), `rectangle.stack.fill` (tidy), symbol
  size 13. `WindowManager.perform(_ action: WindowAction, cascadeStep:)` returns `.done/.failed/
  .needsAccessibility`; `WindowLayout.frame(for:in:)` and `cascade(count:in:step:)` are pure and tested.
- Today's fallbacks (Sources/OddFrogCore/QuickAction.swift): `detectURL` (scheme with host, or a
  bare host with a dotted label and 2+ letter TLD → `https://`), `.openURL` titled "Open <host/path>"
  (teal `link` tile, size 14, kind "URL"), `.webSearch` titled `Search for “<text>”` with subtitle
  `url.host` (indigo `magnifyingglass`, size 13, kind "Search") built from the search template via
  `URLTemplate.resolve(template:query:)` (percent-encodes with `URLTemplate.encode`). `>` + rest →
  `.terminal(rest)` titled "Run in Terminal", subtitle = rest, dark `$` glyph tile (`NSColor(white:
  0.16)` ≈ `#292929`, size 13), kind "Terminal"; empty rest → no row. All three are never recorded.
- Task 20's `HostServices.perform` handles `.window(operation:edge:numerator:denominator:)` by calling
  `WindowManager` and reads `cascadeStep` from a property; `.open(url:)` via `NSWorkspace.shared.open`;
  `.terminal(command:cwd:)` via `TerminalLauncher` with the host's `general.terminal`/`general.shell`.
- Makefile today: `bundle` copies the host binary and three resources, then `codesign --force --sign
  "$(SIGN)" --deep $(BUNDLE)`. `make bundle` works as written (verified). `swift build -c release`
  builds every product in the package, so plugin executables land in `.build/release/<Name>`.
- Test resources: `Tests/OddFrogCoreTests` copies `Fixtures`; the repo `Plugins/` directory is reached
  from a test through `#filePath` (three `deletingLastPathComponent()` from
  `Tests/OddFrogCoreTests/BundledManifestsTests.swift` gives the repo root).
- Trade-off decided: URL detection and template resolution are duplicated into the Web plugin
  (`URLDetection.swift`) instead of a shared library, because a 40-line copy is cheaper than another
  target; the host copy in `QuickAction.detectURL` and its `QuickActionTests.detectURL*` tests remain
  until task 29 deletes them, so the logic stays covered meanwhile.
- Decided: the Web and Terminal providers are persistent (not one-shot) so the host does not spawn a
  process per keystroke. Both ignore `catalog`. The Terminal provider needs no settings; the Web
  provider takes `search_url` at `initialize` and `configure`.

## Plan
1. `Package.swift`: add `.executableTarget(name: "OddFrogWebPlugin", dependencies: ["OddFrogPluginAPI"])`
   and `.executableTarget(name: "OddFrogTerminalPlugin", dependencies: ["OddFrogPluginAPI"])`.
2. `Plugins/windows/plugin.toml`:
   ```toml
   [plugin]
   id = "windows"
   name = "Window Management"
   version = "1.0.0"
   api = 1
   description = "Move and resize the front window from the launcher."
   default_enabled = false

   [services]
   uses = ["window"]

   [[settings]]
   key = "cascade_step"
   type = "number"
   title = "Cascade step"
   description = "Diagonal offset in points for Tidy Windows."
   default = 32
   min = 16
   max = 120
   ```
   followed by ten `[[items]]` tables: ids `place-left-1-2`, `place-right-1-2`, `place-left-2-3`,
   `place-right-2-3`, `place-top-1-2`, `place-bottom-1-2`, `place-top-3-4`, `place-bottom-3-4`,
   `maximize`, `tidy`; titles and subtitle as in Context; `kind = "Window"`; `icon = { symbol =
   "<name>", color = "purple", size = 13 }`; `action = { type = "window", operation = "place", edge =
   "left", numerator = 1, denominator = 2 }` (and `{ type = "window", operation = "maximize" }`,
   `{ type = "window", operation = "tidy" }`).
3. `Plugins/web/plugin.toml`: `[plugin] id = "web"`, `name = "Web"`, `version = "1.0.0"`, `api = 1`,
   description "Open URLs and search the web when nothing matches."; `[provider] mode =
   "persistent"`, `executable = "OddFrogWebPlugin"`; `[query] role = "fallback"`, `activation = "all"`,
   `priority = 100`; `[services] uses = ["open"]`; one `[[settings]]`: `key = "search_url"`, `type =
   "string"`, `title = "Web search"`, `description = "Used when nothing matches. {query} is replaced
   with your search."`, `default = "https://duckduckgo.com/?q={query}"`, `must_contain = "{query}"`.
4. `Plugins/terminal/plugin.toml`: id `terminal`, name "Terminal", description "Run what you type in
   the configured terminal."; `[provider] mode = "persistent"`, `executable = "OddFrogTerminalPlugin"`;
   `[query] role = "exclusive"`, `prefix = ">"`, `activation = "all"`, `priority = 10`; `[services] uses
   = ["terminal"]`.
5. `Sources/OddFrogWebPlugin/URLDetection.swift`: `enum URLDetection { static func detect(_ text:
   String) -> URL? }` (body of today's `QuickAction.detectURL`), `static func encode(_ query: String)
   -> String` and `static func resolve(template: String, query: String) -> URL?` (bodies of
   `URLTemplate.encode` / `resolve(template:query:)`), `static func hostPath(_ url: URL) -> String`
   (body of `QuickAction.displayHostPath`).
6. `Sources/OddFrogWebPlugin/WebHandler.swift`: `final class WebHandler: PluginHandler` storing
   `searchURL` behind an `NSLock` (or make it an `actor` if `PluginHandler` allows; it is
   `AnyObject & Sendable`, so a `final class` with a lock is the expected shape). `initialize` reads
   `settings["search_url"]` (`.string`, falling back to the default) and returns `InitializeResult(api:
   PluginAPI.version, name: "Web", version: "1.0.0")`; `configure` updates it; `query` returns up to
   two items: `PluginItem(id: "open", title: "Open \(hostPath)", kind: "URL", icon: .symbol(name:
   "link", color: IconColor(rawValue: "teal")!, size: 14), action: .open(url: detected.absoluteString),
   recordable: false)` when `detect(text)` succeeds, then `PluginItem(id: "search", title: "Search for
   “\(text)”", subtitle: resolved.host, kind: "Search", icon: .symbol(name: "magnifyingglass", color:
   IconColor(rawValue: "indigo")!, size: 13), action: .open(url: resolved.absoluteString), recordable: false)` when the
   template resolves. Empty `text` → no items. `main.swift`: `await PluginServer.serve(WebHandler())`
   inside `@main`-less top-level code (`Task`-free: use `let handler = WebHandler(); await
   PluginServer.serve(handler)` at top level, which Swift 6 allows in `main.swift`).
7. `Sources/OddFrogTerminalPlugin/TerminalHandler.swift`: `final class TerminalHandler: PluginHandler`;
   `initialize` returns name "Terminal"; `query`: `let rest = params.input.trimmingCharacters(in:
   .whitespaces)`; empty → `[]`; else one `PluginItem(id: "run", title: "Run in Terminal", subtitle:
   rest, kind: "Terminal", icon: .glyph(text: "$", color: IconColor(rawValue: "#292929")!, size: 13),
   action: .terminal(command: rest, cwd: nil), recordable: false)`. `main.swift` as in step 6.
8. `Makefile`:
   ```make
   PLUGINS  := windows web terminal
   PROVIDER_windows :=
   PROVIDER_web := OddFrogWebPlugin
   PROVIDER_terminal := OddFrogTerminalPlugin
   ```
   and in `bundle`, after the resource copies and before `codesign` of the app:
   ```make
   	for p in $(PLUGINS); do \
   		mkdir -p $(CONTENTS)/PlugIns/$$p; \
   		cp -R Plugins/$$p/. $(CONTENTS)/PlugIns/$$p/; \
   	done
   	cp .build/release/OddFrogWebPlugin $(CONTENTS)/PlugIns/web/
   	cp .build/release/OddFrogTerminalPlugin $(CONTENTS)/PlugIns/terminal/
   	for exe in $(CONTENTS)/PlugIns/web/OddFrogWebPlugin $(CONTENTS)/PlugIns/terminal/OddFrogTerminalPlugin; do \
   		codesign --force --sign "$(SIGN)" $$exe; \
   	done
   ```
   (keep the per-provider `cp` lines explicit rather than a generic loop; tasks 26–28 append theirs).
   The final app `codesign … --deep` line stays last.
9. Host removals and rewiring:
   - `WindowAction.swift`, `WindowManager.swift`, and the `.window` branch of `HostServices` stay
     exactly as task 20 left them: `HostServices` still builds a `WindowAction` through the validated
     `init?(operation:edge:numerator:denominator:)` and calls `WindowManager.perform(_:cascadeStep:)`.
     Only the item side goes away here (`LegacyAdapters.windows()`); task 29 deletes the enum itself
     and reshapes `WindowLayout.frame`/`WindowManager.perform`.
   - `HostServices`: the `window` branch converts `PluginAction.window` fields (edge string →
     `WindowEdge(rawValue:)`, ints → `WindowFraction` without hitting its `precondition` — check first)
     and gets the step from a new closure `cascadeStep: (String) -> Double` (parameter: requesting
     plugin id) that `AppDelegate` sets to `{ (pluginSettings.effective(for: $0)["cascade_step"]).number
     ?? 32 }`; remove the old `cascadeStep` property.
   - `ItemAdapters.swift`: delete `LegacyAdapters.windows()`, the `.openURL/.webSearch/.terminal`
     branches of `LegacyAdapters.quick`, and the `terminal`/`web` entries of `LegacyProviders` (only
     `calculator` remains). `QuickAction.swift`: delete the `.openURL/.webSearch/.terminal` cases,
     `fallbacks(for:)`, `displayHostPath`; keep `detectURL` and `.calculation` with its helpers.
   - `AppDelegate`: `rebuildItems` no longer appends window items (they arrive via
     `registry.declarativeItems()`, task 21) and no longer checks `LegacySettings.windowEnabled`;
     the coordinator's `providers` list comes from enabled packages' `QuerySpec`s plus
     `LegacyProviders.calculator`. `LegacySettings.windowEnabled/setWindowEnabled/cascadeStep/
     searchURL/setSearchURL` stay in use by `SettingsWindowController` (same stored keys); the
     `controller.searchTemplate` assignment and the `searchTemplate` property on
     `LauncherViewController` are deleted (the Web plugin owns the template).
10. Tests:
    - `BundledManifestsTests.swift`: `repoPlugins` computed from `#filePath`; `allBundledManifestsParse`
      iterates every `Plugins/*/plugin.toml`, parses with `ManifestParser.load`, asserts `id ==
      directory name`; `windowsDeclaresTenItems` asserts the ten ids in order, `kind == "Window"`,
      `defaultEnabled == false`, `uses == [.window]`, and the `cascade_step` definition (min 16, max
      120, default `.number(32)`); `webIsFallbackAll` (role fallback, activation all, priority 100,
      `search_url` must_contain); `terminalIsExclusive` (prefix `>`, priority 10, uses `[.terminal]`).
    - `QuickActionTests`: delete `terminalPrefixYieldsSingleTerminalAction`,
      `nonURLQueryYieldsWebSearchFallback`, `noSearchTemplateAndNoURLYieldsNoFallbacks`; keep
      `detectURL*` and the calculator cases. `ItemAdaptersTests`: delete the windows and
      fallback/terminal cases. `SearchCoordinatorTests` (task 23) used fake providers and need no
      change; if any test referenced `LegacyProviders.terminal/web`, replace it with an inline fake.
11. `README.md`: in "Build and run" mention that `make bundle` packages the plugins under
    `Plugins/` into `Contents/PlugIns`; in Usage, the Window management paragraph says the feature is
    the Windows plugin, off by default, enabled in Settings (the Plugins pane arrives in task 30 — until
    then the General pane switch remains).

## Constraints
- No code comments of any kind, in any file, including `plugin.toml` files.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; plugin executables import only `Foundation` and `OddFrogPluginAPI`;
  `OddFrogCore` stays AppKit-free; Swift Testing only; tests never spawn the plugin executables and
  never touch the network; no new dependencies.
- Rendering and dispatch in the host must not switch on plugin ids: the only remaining id checks are
  the temporary `LegacyProviders.calculator` and `LegacySettings` accessors.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root) and produces `.build/debug/OddFrogWebPlugin` and
  `.build/debug/OddFrogTerminalPlugin`.
- `swift test` passes, including `BundledManifestsTests`.
- `make bundle` succeeds and `build/OddFrog.app/Contents/PlugIns/` contains `windows/plugin.toml`,
  `web/plugin.toml` + `OddFrogWebPlugin`, `terminal/plugin.toml` + `OddFrogTerminalPlugin`;
  `codesign -dv build/OddFrog.app/Contents/PlugIns/web/OddFrogWebPlugin` reports a signature.
- Manual after `make run`: `> uptime` shows a single "Run in Terminal" row and ↩ opens the terminal;
  `github.com` shows "Open github.com" first; `zzqx` shows only `Search for “zzqx”` and ↩ opens
  DuckDuckGo; with Window management off no `Window` items exist; after enabling it in Settings ›
  General, `window` lists ten items and `Left ½` moves the front window; `~/Library/Logs/odd-frog.log`
  shows `plugin web` and `plugin terminal` started lines and no failures.

## Out of scope
- Applications, scripts, commands, calculator extraction (tasks 26–28).
- The Plugins settings pane (task 30); deleting `QuickAction.detectURL`, `URLTemplate` uses in the
  host, or the calculator legacy provider (tasks 28–29).
- One-shot providers, user-installed packages (tasks 22 and 31 cover them).

## Open questions
none
