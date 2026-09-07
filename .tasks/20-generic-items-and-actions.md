# Task: Plugin system rework 2/13 — generic items, actions, and the host service layer

Second of thirteen tasks (19–31). Requires task 19 (`19-plugin-api-contract.md`): the
`OddFrogPluginAPI` library with `PluginItem`, `PluginAction`, `IconSpec`, `IconColor`,
`HostService`, `ActivateParams`/`ActivateResult`, and `JSONValue` must exist and compile.

## Goal
The host no longer has feature-specific `LauncherItem` cases. Every row in the launcher is a
`LauncherItem` wrapping an API `PluginItem` plus a plugin id; every Return/⌘Return runs a
`PluginAction` through one `HostServices` dispatcher that never switches on plugin identity. Apps,
config commands, scripts, window actions, and the quick rows (URL, web search, terminal,
calculator) are produced by temporary adapters so the app behaves exactly as before, and
`swift test` passes with the ported tests.

## Files
- Package.swift                                        (modify — OddFrogCore depends on OddFrogPluginAPI)
- Sources/OddFrogCore/Item.swift                       (modify — delete `LauncherItem` enum and `WindowItem`; keep AppItem, CommandItem, CommandAction, ScriptMode, ScriptArgument, ScriptItem)
- Sources/OddFrogCore/LauncherItem.swift               (create — generic item)
- Sources/OddFrogCore/ItemAdapters.swift               (create — `LegacyAdapters`, temporary until task 29)
- Sources/OddFrogCore/ActionSubstitution.swift         (create — `{argument}` substitution)
- Sources/OddFrogCore/WindowAction.swift               (modify — validated init from action fields)
- Sources/OddFrogCore/SearchEngine.swift               (modify — generic items; quick rows through the adapter)
- Sources/OddFrogCore/Settings.swift                   (modify — `apply(to:)` on the generic item; no other change)
- Sources/OddFrog/HostServices.swift                   (create — action dispatcher)
- Sources/OddFrog/ActionExecutor.swift                 (modify — thin wrapper; BackgroundRun/TailBuffer move out)
- Sources/OddFrog/IconCache.swift                      (modify — render `IconSpec`)
- Sources/OddFrog/LauncherViewController.swift         (modify — generic detail line, completion, transient check)
- Sources/OddFrog/AppDelegate.swift                    (modify — build items via adapters)
- Sources/OddFrog/SettingsWindowController.swift       (modify — folder counts, link filter, icon reload filter)
- Tests/OddFrogCoreTests/SearchEngineTests.swift       (modify — helpers build generic items)
- Tests/OddFrogCoreTests/ScriptTests.swift             (modify — global ids; subtitle test moves to adapter test)
- Tests/OddFrogCoreTests/QuickActionTests.swift        (modify — one added assertion on the adapter)
- Tests/OddFrogCoreTests/WindowLayoutTests.swift       (modify — validated init test)
- Tests/OddFrogCoreTests/ItemAdaptersTests.swift       (create)
- Sources/OddFrogPluginAPI/PluginItem.swift            (read — PluginItem, IconSpec, IconColor, ArgumentSpec)
- Sources/OddFrogPluginAPI/PluginAction.swift          (read — PluginAction cases, HostService, requiredService)

## Context
- Task 19 defines (fixed names): `PluginItem {id, title, subtitle, kind, icon, aliases, argument,
  completion, action, secondary, recordable}`, `ArgumentSpec {placeholder, optional}`, `IconSpec`
  (`.file(path:)`, `.emoji`, `.symbol(name:color:size:)`, `.glyph(text:color:size:)`), `IconColor`
  (`rawValue` is a name from `red orange yellow green mint teal cyan blue indigo purple pink brown
  gray` or `#rrggbb`; `name`/`hex` accessors), `PluginAction` (`copy(text:)`, `open(url:)`,
  `launch(path:)`, `reveal(path:)`, `exec(executable:arguments:cwd:output:)`, `shell(command:cwd:)`,
  `terminal(command:cwd:)`, `window(operation:edge:numerator:denominator:)`, `callback(name:payload:)`),
  `ExecOutput {notify, silent}`, `WindowOperation {place, maximize, tidy}`, `HostService` (`open,
  clipboard, launch, exec, terminal, window, notify`, `CaseIterable`), `PluginAction.requiredService`,
  `ActivateParams {itemId, name, payload, argument, secondary}`, `ActivateResult {action, message}`.
- Today (`Sources/OddFrogCore/Item.swift`) `LauncherItem` is an enum `app/command/script/quick/window`
  with computed `id`, `title`, `subtitle`, `aliases`, `acceptsArgument`, `kindLabel`, `withAliases`,
  and static `subtitles(for:)` (folder subtitle for apps whose titles collide) and `abbreviate(_:)`
  (`~` for the home prefix). Ids: app = bundle path, `command:<name>`, `script:<path>`,
  `window:place:<edge>:<n>-<d>` / `window:maximize` / `window:tidy`, `quick:…`.
- `SearchEngine.search(query:items:weights:maxResults:searchTemplate:rates:)` ranks by fuzzy score +
  exact alias + frecency, handles the kind-label prefix (`window left`), splits arguments for items
  with `acceptsArgument`, puts a calculator row first, `>` → terminal row, no match → fallbacks. It
  builds quick rows as `.quick(QuickAction)`. `RankedItem {item, lexical, weight, exactAlias, argument}`.
- `Settings.apply(to:)` drops disabled items and merges override aliases by `item.id`;
  `ItemOverride.id` strings are user-facing in `settings.toml`.
- `ActionExecutor` (`Sources/OddFrog/ActionExecutor.swift`, `@MainActor`) contains `TailBuffer`,
  `BackgroundRun`, `run(_:argument:secondary:)`, `runScript`, `runSecondary`, `openApplication`,
  `runInTerminal(id:name:command:cwd:)` (via `TerminalLauncher.launch(command:cwd:name:kind:shell:)`),
  `spawn(id:name:executable:arguments:cwd:reportOutput:)`, `record(_:)` (skips ids with prefix
  `quick:`; awaits `frecency.record` then `onRecorded`), `fail(_:)`. It owns `terminals`, `windows`
  (`WindowManager.perform(_:cascadeStep:) -> Outcome {done, failed(String), needsAccessibility}`),
  `config: Config` (shell, terminal kind), `cascadeStep`, `onFailure`, `onRecorded`. Folder secondary
  runs `exec '<shell>' -l` in the folder; URL secondary copies the display URL (with `{query}`
  resolved when an argument was typed); script secondary forces terminal; scripts with a required
  argument and none typed post the notification "Needs an argument (<placeholder>): type the command,
  a space, then the value." Non-zero exits notify "<name> exited <status>" with the stderr/stdout tail;
  `reportOutput` posts stdout as a notification on success.
- `IconCache.icon(for:size:)` switches on the enum: app → `icon(forFile:)` (async load, `observeLoads`
  fires with the file path, rows reload); shell → tile `NSColor(white: 0.16, alpha: 1)` glyph `$` 13;
  path → `.systemBlue` symbol `folder.fill` 12; url → `.systemTeal` `link` 14; script → emoji image or
  `.systemGray` glyph `>_` 10; window → `.systemPurple` symbols `rectangle.lefthalf.filled` /
  `rectangle.righthalf.filled` / `rectangle.tophalf.filled` / `rectangle.bottomhalf.filled` /
  `rectangle.fill` / `rectangle.stack.fill` 13; openURL → teal `link` 14; webSearch → `.systemIndigo`
  `magnifyingglass` 13; terminal → shell tile; calculator arithmetic → `.systemOrange`
  `plus.forwardslash.minus` 13; units → `.systemGreen` `ruler` 13; currency → `.systemMint`
  `dollarsign` 13. Tiles are cached by `name` + size.
- `LauncherViewController` (`Sources/OddFrog/LauncherViewController.swift`): `refresh(keepSelection:)`
  calls `SearchEngine.search`; `completion(for:)` = first alias or title + " " when `acceptsArgument`;
  `submit` fills the completion for a `.script` with a required argument and no argument;
  `handleKeyEquivalent` blocks ⌘I on `.quick`; `detail(for:)` returns the quick subtitle, or for a
  script with an argument the placeholder line (`DetailLine(detail:value:tooltip:chip:)`, generic
  placeholder `argument` → "Argument", chip `.optional`/`.required`), or "Query:" + value for a
  command with an argument, else the precomputed subtitle. `icons.observeLoads` reloads rows whose
  `.app` path matches.
- `AppDelegate.rebuildItems` builds `allItems = apps + commands + scripts (+ windows when enabled)`
  then `settings.apply(to:)`. `SettingsWindowController.recomputeFolderCounts` counts `.script` items
  per folder; `showLinks` collects `.command` items with `.url` actions into `[CommandItem]` for
  `LinkManagerController`; its `icons.observeLoads` filter matches `.app` paths; the Items table
  shows `item.kindLabel ?? "App"`.
- `URLTemplate`: `placeholder = "{query}"`, `encoded = "%7Bquery%7D"` (what a `URL` built from a
  template contains), `accepts(_:)`, `display(_:)`, `encode(_:)` (percent-encodes for a query value),
  `resolve(_:query:)`. `ShellCommand.quote(_:)`, `ShellCommand.backgroundArguments(command:)` =
  `["-lc", command]`.
- `WindowAction` (`Sources/OddFrogCore/WindowAction.swift`): `.place(WindowEdge, WindowFraction)`,
  `.maximize`, `.tidy`; `WindowFraction.init(numerator:denominator:)` has a `precondition(numerator > 0
  && denominator >= numerator)`; `WindowEdge` raw values `left right top bottom`; `WindowAction.all`
  lists the ten actions in display order; `title` gives "Left ½" etc., `subtitle` only for tidy.
- Decisions fixed for the whole rework (do not re-decide):
  - Global item id = `"<plugin id>:<local id>"`. Legacy plugin ids used by the adapters:
    `applications`, `commands`, `scripts`, `windows`, `web`, `terminal`, `calculator`. Local ids: apps
    = bundle path (`applications:/Applications/Xcode.app`); commands = lowercased name with runs of
    whitespace replaced by `-` (`commands:build-project`); scripts = script path
    (`scripts:/Users/me/x.sh`); windows = `place-<edge>-<n>-<d>`, `maximize`, `tidy`; quick rows =
    `web:url:<url>`, `web:search:<query>`, `terminal:run`, `calculator:result`.
  - Frecency and item overrides are keyed by the global id from now on. No migration: an existing
    `frecency.json` or `[[items]]` override with an old id simply stops matching (task 24 moves both
    files to new paths anyway).
  - Argument placeholder token in actions is the literal `{argument}`; the host substitutes it.
  - Query-produced rows are `transient`: never recorded, never overridable, ⌘I disabled.
  - The temporary identity checks introduced here (`pluginID == "scripts"` for folder counts,
    `pluginID == "commands"` for Manage Links, the legacy ids in `LegacyAdapters`) are removed by
    tasks 27 and 29.

## Plan
1. `Package.swift`: `OddFrogCore` dependencies become `["OddFrogPluginAPI", .product(name: "TOMLKit",
   package: "TOMLKit")]`. Nothing else changes.

2. `Sources/OddFrogCore/LauncherItem.swift`:
   ```swift
   public struct LauncherItem: Sendable, Hashable {
       public let pluginID: String
       public let item: PluginItem
       public let transient: Bool
       public init(pluginID: String, item: PluginItem, transient: Bool = false)
       public var id: String { pluginID + ":" + item.id }
       public var title: String { item.title }
       public var subtitle: String? { item.subtitle }
       public var kindLabel: String? { item.kind }
       public var aliases: [String] { item.aliases }
       public var icon: IconSpec? { item.icon }
       public var argument: ArgumentSpec? { item.argument }
       public var acceptsArgument: Bool { item.argument != nil }
       public var completion: String
       public var action: PluginAction { item.action }
       public var secondaryAction: PluginAction { item.secondary ?? item.action }
       public var recordable: Bool { item.recordable && !transient }
       public func withAliases(_ extra: [String]) -> LauncherItem
       public static func abbreviate(_ path: String) -> String
   }
   ```
   `completion` = `item.completion` if set, else first alias, else title; append `" "` when
   `acceptsArgument` and the text does not already end with a space. `withAliases` merges extra
   aliases after the existing ones, de-duplicated, returning a copy (same `transient`).
   `abbreviate` moves here unchanged from Item.swift.

3. `Item.swift`: delete the `LauncherItem` enum, `WindowItem`, and the moved `abbreviate`. Keep
   everything else byte-identical.

4. `Sources/OddFrogCore/ActionSubstitution.swift`: `public enum ActionSubstitution { public static let
   token = "{argument}"; public static func apply(_ action: PluginAction, argument: String) ->
   PluginAction }` replacing the token in `copy.text` (verbatim), `open.url` (`URLTemplate.encode(argument)`),
   each `exec.arguments` element (verbatim), `terminal.command` (`ShellCommand.quote(argument)`);
   other cases unchanged.

5. `WindowAction.swift`: add `public init?(operation: WindowOperation, edge: String?, numerator: Int?,
   denominator: Int?)` (import OddFrogPluginAPI): `maximize`/`tidy` ignore the rest; `place` requires
   `WindowEdge(rawValue:)` from `edge`, `numerator > 0`, `denominator >= numerator`, both ≤ 12, else nil.
   Also add `public var localItemID: String` (`place-<edge>-<n>-<d>`, `maximize`, `tidy`) and `public
   var symbolName: String` (the six symbol names listed in Context, by case/edge).

6. `Sources/OddFrogCore/ItemAdapters.swift` — `public enum LegacyAdapters` (import OddFrogPluginAPI):
   - `apps(_ apps: [AppItem]) -> [LauncherItem]`: plugin `applications`, local id `url.path`, title
     `name`, kind nil, icon `.file(path: url.path)`, aliases, action `.launch(path:)`, secondary
     `.reveal(path:)`; subtitle = `abbreviate(url.deletingLastPathComponent().path)` only when another
     app in the array has the same case-insensitive name, else nil.
   - `commands(_ commands: [CommandItem]) -> [LauncherItem]`: plugin `commands`, local id per Context.
     `.shell(text)` + `terminal == false` → kind "Shell", icon `.glyph("$", "#292929", 13)`, action
     `.shell(command: text, cwd: cwd?.path)`, secondary `.terminal(command: text, cwd:)`; `.shell` +
     `terminal == true` → kind "Terminal", same icon, action `.terminal`, secondary nil; `.path(url)` →
     kind "Folder", icon `.symbol("folder.fill", "blue", 12)`, subtitle `abbreviate(url.path)`, action
     `.open(url: url.absoluteString)`, secondary `.terminal(command: "", cwd: url.path)` when the path
     is a directory on disk else `.reveal(path:)`; `.url(url)` → kind "URL", icon `.symbol("link",
     "teal", 14)`, subtitle = host + path without trailing slashes with `%7Bquery%7D` shown as `{query}`
     (today's `webAddress`), action `.open(url: URLTemplate.display(url).replacingOccurrences(of:
     "{query}", with: "{argument}"))`, secondary `.copy(text: <same string>)`; when
     `URLTemplate.accepts(url)` the item gets `argument: ArgumentSpec(placeholder: "Query", optional:
     true)`. Aliases copied.
   - `scripts(_ scripts: [ScriptItem]) -> [LauncherItem]`: plugin `scripts`, local id `url.path`,
     kind "Script", icon `.emoji(icon)` when present else `.glyph(">_", "gray", 10)`, subtitle =
     package when it differs case-insensitively from the title, argument from `ScriptArgument`
     (placeholder, optional), action: `mode == .fullOutput` → `.terminal(command: quote(path) + (argument
     != nil ? " {argument}" : ""), cwd: parent)`, otherwise `.exec(executable: path, arguments:
     argument != nil ? ["{argument}"] : [], cwd: parent, output: .notify)`; secondary always the
     `.terminal` form. Note `{argument}` inside a terminal command is replaced by a shell-quoted value,
     so the terminal command must not quote the token itself.
   - `windows() -> [LauncherItem]`: plugin `windows`, one per `WindowAction.all` in order, local id
     `localItemID`, title/subtitle from the action, kind "Window", icon `.symbol(symbolName, "purple",
     13)`, action `.window(operation:edge:numerator:denominator:)` filled from the case.
   - `quick(_ quick: QuickAction) -> LauncherItem` (transient: true, recordable: false): `.openURL(url)`
     → plugin `web`, id `url:<absoluteString>`, title/subtitle from QuickAction, kind "URL", icon teal
     `link` 14, action `.open`; `.webSearch(query, url)` → plugin `web`, id `search:<query>`, kind
     "Search", icon indigo `magnifyingglass` 13, action `.open`; `.terminal(text)` → plugin `terminal`,
     id `run`, kind "Terminal", shell glyph icon, action `.terminal(command: text, cwd: nil)`;
     `.calculation` → plugin `calculator`, id `result`, kind from `kindLabel`, icon orange
     `plus.forwardslash.minus` / green `ruler` / mint `dollarsign` (13), action `.copy(text:
     copyText)`.

7. `SearchEngine.swift`: the algorithm is unchanged; replace `.quick(...)` constructions with
   `LegacyAdapters.quick(...)`, use `item.kindLabel`, `item.aliases`, `item.acceptsArgument` from the
   struct. Signature unchanged.

8. `Settings.swift`: `apply(to:)` compiles unchanged against the struct (it only uses `id` and
   `withAliases`). Verify; no edit expected.

9. `Sources/OddFrog/HostServices.swift` — move `TailBuffer` and `BackgroundRun` here verbatim, then:
   ```swift
   @MainActor final class HostServices {
       var config: Config
       var cascadeStep: CGFloat = 32
       var declaredServices: (String) -> Set<HostService> = { _ in Set(HostService.allCases) }
       var callback: (String, ActivateParams) async throws -> ActivateResult = { id, _ in throw HostServiceError.noProvider(id) }
       var onFailure: ((String) -> Void)?
       let notifier: Notifier
       let terminals = TerminalLauncher()
       let windows = WindowManager()
       init(config: Config, notifier: Notifier)
       func perform(_ action: PluginAction, for item: LauncherItem, argument: String?, secondary: Bool) async -> Bool
   }
   ```
   `perform`: substitute `{argument}` when `item.argument != nil && argument != nil`; check
   `action.requiredService` against `declaredServices(item.pluginID)` and on a miss `fail("plugin
   <id> did not declare service <name>")` and return false; then dispatch: `open` → `URL(string:)`
   then `NSWorkspace.shared.open`; `copy` → pasteboard; `launch` → today's `openApplication` (await a
   continuation around the completion handler); `reveal` → `activateFileViewerSelecting`; `exec` →
   today's `spawn` with `reportOutput = output == .notify`; `shell` → `spawn` of
   `URL(fileURLWithPath: config.general.shell)` with `ShellCommand.backgroundArguments(command:)`;
   `terminal` → `terminals.launch` with `command.isEmpty ? "exec \(ShellCommand.quote(config.general.shell))
   -l" : command`, `cwd` mapped to a file URL, `name: item.title`; `window` → `WindowAction(operation:
   edge:numerator:denominator:)`, nil → `fail("<title>: invalid window action")`, else
   `windows.perform(_, cascadeStep:)` mapping `.needsAccessibility` to today's Accessibility message;
   `callback` → `try await callback(item.pluginID, ActivateParams(itemId: item.item.id, name:, payload:,
   argument:, secondary:))`, then if `result.action` is non-nil perform it recursively (same item, no
   further substitution), if `result.message` is non-nil `notifier.post(title: item.title, body:)`.
   Return true on success. Failure names use `item.title`. `spawn` returns `Bool` (false when
   `process.run()` throws). `HostServiceError` is a small `enum: Error { case noProvider(String) }`.

10. `ActionExecutor.swift` becomes:
    ```swift
    @MainActor final class ActionExecutor {
        let services: HostServices
        let frecency: FrecencyStore
        var config: Config { get { services.config } set { services.config = newValue } }
        var cascadeStep: CGFloat { get set → services }
        var onFailure: ((String) -> Void)? { get set → services }
        var onRecorded: (() -> Void)?
        init(config: Config, frecency: FrecencyStore, notifier: Notifier)
        func run(_ item: LauncherItem, argument: String? = nil, secondary: Bool = false)
    }
    ```
    `run`: if `item.argument` is required and `argument == nil` → `notifier.post(title: item.title,
    body: "Needs an argument (<placeholder>): type the command, a space, then the value.")` and return;
    else `Task { if await services.perform(secondary ? item.secondaryAction : item.action, for: item,
    argument:, secondary:) { record(item) } }`; `record` only when `item.recordable`.

11. `IconCache.swift`: `icon(for item: LauncherItem, size:)` switches on `item.icon`: nil → tile
    `"app"` `.systemGray` symbol `app.fill` 13; `.file(path)` → `icon(forFile:)`; `.emoji` →
    `emojiImage`; `.symbol(name, color, size)` → `tile(name: "symbol:\(name):\(color.rawValue)", color:
    nsColor(color), symbol: name, symbolSize: size ?? 13)`; `.glyph(text, color, size)` → `tile(name:
    "glyph:\(text):\(color.rawValue)", …, glyphSize: size ?? 13)`. Add `private static func nsColor(_:
    IconColor) -> NSColor` mapping the thirteen names to `.systemRed … .systemBrown, .systemGray`
    and hex to `NSColor(srgbRed:green:blue:alpha: 1)`. `prewarm(_ apps: [AppItem])` is unchanged.

12. `LauncherViewController.swift`: `observeLoads` filter → `if case .file(let path) = results[row]
    .item.icon`; drop the `subtitles` dictionary and `LauncherItem.subtitles(for:)` (use
    `item.subtitle`); `completion(for:)` → `item.completion`; `submit` → fill when `item.argument` is
    non-nil, not optional, and `result.argument == nil`; `isQuick` → `item.transient`; `detail(for:)`:
    if `item.argument` is non-nil and `result.argument` is non-nil → placeholder line with value (as
    today); if the argument is required and untyped → placeholder + `.required` chip; if optional and
    untyped → the subtitle when present, else placeholder + `.optional` chip; no argument → subtitle.
    (Deviation accepted: a script with an optional argument and a package subtitle now shows the
    package instead of the chip.)

13. `AppDelegate.swift`: `rebuildItems` → `allItems = LegacyAdapters.apps(apps) +
    LegacyAdapters.commands(config.commands) + LegacyAdapters.scripts(scripts)` plus
    `LegacyAdapters.windows()` when `settings.window.enabled`. The `@run` debug path and everything
    else compiles unchanged through the forwarding properties.

14. `SettingsWindowController.swift`: `recomputeFolderCounts` counts items with `pluginID == "scripts"`
    by `item.item.id` path prefix; `showLinks` builds `[CommandItem]` from items with `pluginID ==
    "commands"` whose action is `.open(url)` with an `http`/`https` scheme, reconstructing
    `CommandItem(name: title, aliases:, action: .url(URL(string: url.replacingOccurrences(of:
    "{argument}", with: "{query}"))!), cwd: nil, terminal: false)` — this keeps `LinkEditor` working
    until task 27; `observeLoads` filter → `.file(path)` icons; kind column unchanged.

15. Tests:
    - `SearchEngineTests`: helpers `app(_:)` → `LegacyAdapters.apps([AppItem(...)])[0]`, `cmd` →
      `LegacyAdapters.commands([...])[0]`; window items via `LegacyAdapters.windows()`; script/link
      items via the adapters; expectations on ids move to global ids (`commands:double-it`,
      `applications:/Applications/Mid.app` in `weights`); the quick-row cases check
      `results[0].item.pluginID == "calculator"` / `"terminal"` / `"web"` and `transient == true`
      instead of pattern-matching `.quick`.
    - `ScriptTests.settingsRoundTripAndApply`: ids `applications:/Applications/Xcode.app`,
      `commands:build`, `commands:noop`; `applied.map(\.id) == ["commands:build"]`.
    - `ScriptTests.subtitlesOnlyForCollisionsAndInformativeMetadata` → replace with the equivalent
      assertions on adapter output in the new `ItemAdaptersTests` (Xcode duplicates get
      `/Applications` and `~/Applications`, Safari nil, SSH nil, IP "Network", Build nil, Docs
      "developer.apple.com/documentation"; `safari.kindLabel == nil`, `ip.kindLabel == "Script"`), and
      delete it from ScriptTests.
    - `QuickActionTests`: add `#expect(LegacyAdapters.quick(QuickAction.calculation(for: "2+2")!).id ==
      "calculator:result")` and `.transient == true` in `arithmeticQueryBecomesACalculatorAction`.
    - `WindowLayoutTests`: `WindowAction(operation: .place, edge: "left", numerator: 1, denominator: 2)
      == .place(.left, WindowFraction(numerator: 1, denominator: 2))`; `edge: "up"`, `numerator: 0`,
      `numerator: 3, denominator: 2` → nil; `.maximize` with junk fields → `.maximize`; `localItemID`
      of all ten actions equals `["place-left-1-2", "place-right-1-2", "place-left-2-3",
      "place-right-2-3", "place-top-1-2", "place-bottom-1-2", "place-top-3-4", "place-bottom-3-4",
      "maximize", "tidy"]`.
    - `ItemAdaptersTests` (new): commands → shell/terminal/folder/url items with the ids, kinds,
      actions, secondaries and the `{argument}` token for a `{query}` URL (both action and secondary);
      scripts → exec vs terminal by mode, `["{argument}"]` when an argument exists, secondary always
      terminal, emoji icon; windows → ten items with purple symbol icons; quick → ids/plugins/transient;
      `ActionSubstitution.apply` on each of the four substituting cases (`open` percent-encodes
      `odd frog` to `odd%20frog`, `terminal` wraps in single quotes); `LauncherItem.completion` with and
      without argument; `withAliases` de-duplicates.

## Constraints
- No code comments of any kind, in any file (the two existing comments in LinkEditor.swift and the one
  in `AppDelegate.applyLink` stay as they are).
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `OddFrogCore` imports Foundation, CoreGraphics (WindowAction only),
  TOMLKit, OddFrogPluginAPI — never AppKit.
- Swift Testing only; tests never touch the network or the user's home directory (temporary
  directories are fine).
- No new third-party dependencies.
- Rendering and execution never switch on `pluginID` except the two temporary Settings checks named
  in Plan step 14.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes; the ported suites keep their test names.
- `swift test --filter ItemAdaptersTests` passes.
- Manual after `make run`: typing `xc` opens Xcode on Return and reveals it on ⌘Return; a folder
  command opens in Finder and ⌘Return opens a terminal there; `gh odd-frog` opens the search URL;
  a script with a required argument shows the placeholder chip and Return fills the field; `2+2`
  copies `4`; `>uptime` runs in the terminal; with window management on, `window left` lists the two
  left placements and Return moves the front window; ⌘I on a calculator row does nothing.

## Out of scope
- Discovery, manifests, processes, coordinator (tasks 21–23).
- Any change to config or settings file formats or paths (task 24).
- Removing `QuickAction`, `AppScanner`, `ScriptScanner`, `ConfigParser` command parsing, or
  `LinkEditor` (tasks 25–29).

## Open questions
none
