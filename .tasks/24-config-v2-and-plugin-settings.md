# Task: Plugin system rework 6/13 — fresh `v2` configuration and host-owned plugin settings

Sixth of thirteen tasks (19–31). Requires tasks 19–23 (`19-plugin-api-contract.md` through
`23-search-coordinator.md`): the generic `LauncherItem`, the temporary `LegacyAdapters`, the
`PluginRegistry`, the `PluginRuntime`, and the `SearchCoordinator` all exist and the host still runs
apps, commands, scripts, windows, calculator and web/terminal fallbacks through host code. This task
moves every configuration file to the fresh `v2` layout and adds the settings store that later tasks
(25–28) use when each feature becomes a real plugin. No feature is extracted here.

## Goal
The host reads and writes only the `v2` files: `~/.config/odd-frog/v2/config.toml` (`[general]`
only), `~/.config/odd-frog/v2/settings.toml` (`[[items]]` overrides plus one `[plugins.<id>]` table per
plugin holding `enabled` and that plugin's setting values), `~/.config/odd-frog/v2/plugins/commands/
commands.toml` (the `[[commands]]` list, seeded from an example on first launch), and
`~/Library/Application Support/odd-frog/v2/` for history and plugin data. Legacy files under
`~/.config/odd-frog/` and `~/Library/Application Support/odd-frog/` (other than `tmp/`) are never
read, written, or deleted. A `PluginSettingsStore` turns manifests plus stored values into validated
effective settings, hands them to running providers, and drives enable/disable. Existing features keep
working through temporary accessors that read their old settings from the new plugin tables.

## Files
- Sources/OddFrogCore/Config.swift                       (modify — v2 directories, `rootDirectory`)
- Sources/OddFrogCore/Settings.swift                     (modify — `plugins: [String: PluginState]`, drop feature tables)
- Sources/OddFrogCore/PluginPaths.swift                  (create — config/data directories per plugin, history path)
- Sources/OddFrogCore/PluginSettingsStore.swift          (create)
- Sources/OddFrogCore/PluginDiscovery.swift              (modify — `userDirectory` uses `ConfigLoader.rootDirectory`)
- Sources/OddFrogCore/PluginRuntime.swift                (modify — `configRoot`/`dataRoot` come from `PluginPaths`)
- Sources/OddFrogCore/ItemAdapters.swift                 (modify — add temporary `LegacySettings`)
- Sources/OddFrogCore/Frecency.swift                     (modify — `defaultURL` → v2)
- Sources/OddFrogCore/CurrencyRateStore.swift            (modify — `defaultURL` → calculator data dir)
- Sources/OddFrogCore/LinkEditor.swift                   (read — `save(to:)` is reused unchanged on the commands file)
- Sources/OddFrogPluginAPI/PluginAPI.swift               (modify only if step 2 needs the `Int` decode attempt)
- Sources/OddFrog/AppDelegate.swift                      (modify — commands file, settings store, runtime wiring)
- Sources/OddFrog/SettingsWindowController.swift         (modify — read/write through `LegacySettings`)
- Sources/OddFrog/StatusMenu.swift                       (read — "Open Config" stays; target path changes in AppDelegate)
- Resources/config.example.toml                          (modify — `[general]` only)
- Resources/commands.example.toml                        (create — the four example commands)
- Makefile                                               (modify — copy `commands.example.toml` into Resources)
- README.md                                              (modify — Config and Settings sections)
- Tests/OddFrogCoreTests/SettingsTests.swift             (create — moved and rewritten settings tests)
- Tests/OddFrogCoreTests/PluginSettingsStoreTests.swift  (create)
- Tests/OddFrogCoreTests/ScriptTests.swift               (modify — remove `settingsRoundTripAndApply`, `emptySettingsParse`)
- Tests/OddFrogCoreTests/ConfigTests.swift               (modify — example without commands still parses; commands file parse)
- Tests/OddFrogCoreTests/LinkEditorTests.swift           (read — must keep passing unchanged)

## Context
- `ConfigLoader.defaultDirectory` (Sources/OddFrogCore/Config.swift) is `$XDG_CONFIG_HOME/odd-frog`
  or `~/.config/odd-frog`; `defaultPath` is `config.toml` inside it; `SettingsLoader.defaultPath` is
  `settings.toml` inside it. `ConfigLoader.ensureExists(at:template:)` copies a template file or writes
  a minimal `[general]` block. `ConfigLoader.replacingHotkey(in:with:)` edits the `[general]` table
  textually and is used by `AppDelegate.setHotkey`.
- `ConfigParser.parse` decodes `[general]` and `[[commands]]` (RawConfig/RawGeneral/RawCommand) and
  validates commands (unique names, unique aliases, exactly one of command/path/url, `terminal` only
  with `command`). It must keep parsing `[[commands]]`: the same parser reads the commands file in this
  task and the Commands plugin (task 27) reuses the rules. A `[general]` table inside the commands file
  is parsed and ignored.
- `Settings` today: `scripts {folders, watch}`, `items: [ItemOverride]`, `search {url}`, `currency
  {enabled}`, `window {enabled, cascadeStep}`; `Settings.parse` lowercases override aliases;
  `serialized()` uses `TOMLEncoder`; `apply(to:)` filters and aliases `LauncherItem`s by global id
  (task 20). `SettingsLoader.save` writes atomically.
- Host consumers of the old feature tables (all must switch to `LegacySettings` in this task):
  `AppDelegate` lines using `settings.search.url` (search template), `settings.window.cascadeStep`
  and `settings.window.enabled`, `settings.scripts.folders/watch` and `settings.scriptFolders`,
  `settings.currency.enabled`; `SettingsWindowController` uses `settings.scripts.folders` (folder
  table, add/remove), `settings.scripts.watch` (switch), `settings.search.url` (field),
  `settings.currency.enabled` (switch), `settings.window.enabled` (switch) and `update(windowSettings:
  Settings.Window)`.
- `FrecencyStore.defaultURL` is `~/Library/Application Support/odd-frog/frecency.json`;
  `CurrencyRateStore.defaultURL` is `…/odd-frog/rates.json`; `TerminalLauncher.scratchDirectory`
  is `…/odd-frog/tmp/` and stays where it is.
- Task 19 types used here: `JSONValue`, `SettingValue`, `SettingDefinition.validate`,
  `PluginManifest.effectiveSettings(stored:)`, `PluginManifest.settingsJSON(_:)`, `PluginManifest
  .defaultEnabled`. Task 21 types: `PluginPackage {id, manifest, directory, source, error}` (public
  memberwise init), `PluginSource`, `PluginRegistry.enabled`,
  `PluginRegistry.defaultEnabled(for:)` (rule: bundled → `manifest.defaultEnabled`, user → false).
  Task 22: `PluginRuntime` has `configRoot: URL`, `dataRoot: URL`, `settingsProvider: (PluginPackage)
  -> [String: JSONValue]`, `sync(enabled: [PluginPackage]) async` (starts newly enabled catalog
  providers, stops disabled/removed ones), `stop(_ id:) async`, `reload(_ package:) async`,
  `configure(_ id:, settings:) async`, `status(for:) -> PluginStatus?`.
- TOML decoding detail: task 19's `JSONValue.init(from:)` tries `Bool`, `Double`, `String`, array,
  object. TOMLKit may refuse to decode a TOML integer (`cascade_step = 32`) as `Double`. If the round-
  trip test in step 9 fails on integers, add an `Int` attempt before `Double` in `JSONValue.init(from:)`
  (mapping to `.number(Double(int))`); that is the only permitted edit to `Sources/OddFrogPluginAPI`.
  `JSONValue.null` cannot be represented in TOML; `PluginState` encoding skips null values.
- Decisions made for this task: no migration or import of legacy files; the commands file lives in
  the Commands plugin's config dir from the start so task 27 only relocates code; `enabled` is the
  reserved host key inside `[plugins.<id>]`; a plugin table may hold keys that no manifest declares
  (kept verbatim, ignored by `effective(for:)`); the temporary `LegacySettings` accessors use the plugin
  ids `scripts`, `web`, `calculator`, `windows` and the setting keys that the future manifests declare
  (`folders`, `watch`, `search_url`, `currency`, `cascade_step`), so no data changes when the plugins
  arrive.

## Plan
1. `Config.swift`: add `public static var rootDirectory: URL` (the current `defaultDirectory` body:
   `$XDG_CONFIG_HOME/odd-frog` or `~/.config/odd-frog`) and make `defaultDirectory` return
   `rootDirectory.appendingPathComponent("v2", isDirectory: true)`. `defaultPath`/`SettingsLoader
   .defaultPath` follow automatically. Add `public static var commandsExamplePath: URL?` returning
   `Bundle.main.resourceURL?.appendingPathComponent("commands.example.toml")`. No change to
   `ConfigParser`.
2. `Settings.swift`: delete the nested `Scripts`, `Search`, `Currency`, `Window` structs and their
   properties. Add
   `public struct PluginState: Codable, Sendable, Equatable { public var enabled: Bool?; public var
   values: [String: JSONValue] }` with a public init (`enabled: Bool? = nil, values: [String: JSONValue]
   = [:]`) and custom `Codable`: decode through a keyed container with a dynamic `CodingKey` struct,
   take `enabled` as `Bool` when present, every other key as `JSONValue`; encode `enabled` when non-nil
   and each value except `.null`. `Settings` becomes `items: [ItemOverride]` + `plugins: [String:
   PluginState]` (default `[:]`), `CodingKeys` `items`, `plugins`; `init(from:)` uses
   `decodeIfPresent` for both. Keep `empty`, `override(for:)`, `setOverride`, `apply(to:)`, `parse`,
   `serialized()`. Add `public func pluginState(_ id: String) -> PluginState` (stored or empty) and
   `public mutating func setPluginState(_ state: PluginState, for id: String)` (removes the table when
   `enabled == nil && values.isEmpty`). Remove `scriptFolders`.
3. `PluginPaths.swift` (Core):
   `public enum PluginPaths` with `public struct Directories: Sendable, Hashable { public let config:
   URL; public let data: URL }`, `public static var configRoot: URL` (`ConfigLoader.defaultDirectory/
   plugins`), `public static var dataRoot: URL` (`FileManager.default.urls(for:
   .applicationSupportDirectory, in: .userDomainMask)[0]/odd-frog/v2`), `public static func
   directories(for id: String) -> Directories` (`configRoot/<id>`, `dataRoot/plugins/<id>`),
   `public static var historyURL: URL` (`dataRoot/frecency.json`), `public static func
   ensure(_ directories: Directories) throws` (creates both with intermediates), and `public static var
   commandsFile: URL` (`directories(for: "commands").config/commands.toml`).
4. `PluginDiscovery.swift`: `userDirectory` must be `ConfigLoader.rootDirectory.appendingPathComponent
   ("plugins", isDirectory: true)` so user packages stay at `~/.config/odd-frog/plugins` and do not
   collide with `PluginPaths.configRoot` (`~/.config/odd-frog/v2/plugins`). Update the task 21 test that
   asserts the path if there is one.
5. `Frecency.swift`: `defaultURL` returns `PluginPaths.historyURL`. `CurrencyRateStore.swift`:
   `defaultURL` returns `PluginPaths.directories(for: "calculator").data.appendingPathComponent
   ("rates.json")`.
6. `PluginSettingsStore.swift` (Core):
   ```swift
   @MainActor public final class PluginSettingsStore {
       public var packages: [PluginPackage] { didSet }      // host assigns from the registry
       public var settings: Settings { didSet }             // host assigns on load and on every change
       public var onChange: ((Settings) -> Void)?           // fired by set/setEnabled with the updated settings
       public init(packages: [PluginPackage] = [], settings: Settings = .empty)
       public static func defaultEnabled(for package: PluginPackage) -> Bool   // bundled → manifest?.defaultEnabled ?? false; user → false
       public func isEnabled(_ id: String) -> Bool          // settings.plugins[id]?.enabled ?? defaultEnabled(for: package); false when unknown id
       public func enabledIDs() -> Set<String>              // ids of packages with a manifest that are enabled
       public func effective(for id: String) -> [String: SettingValue]   // manifest.effectiveSettings(stored: values); [:] without manifest
       public func json(for id: String) -> [String: JSONValue]           // manifest.settingsJSON(effective(for:))
       public func setEnabled(_ id: String, _ enabled: Bool)             // writes pluginState.enabled, then onChange
       public func set(_ id: String, key: String, value: SettingValue)   // validates against the definition; invalid → NSLog and no change; writes value.json; onChange
   }
   ```
   Invalid stored values encountered by `effective(for:)` are reported once per key via
   `NSLog("odd-frog: plugin <id> setting <key> ignored: invalid value")` (keep a `Set<String>` of
   reported `id/key` pairs to avoid repeating).
7. `PluginRuntime.swift`: replace the hard-coded defaults of `configRoot`/`dataRoot` with
   `PluginPaths.configRoot`/`PluginPaths.dataRoot` (add those two static URLs to `PluginPaths`, the
   parents of `configDir(for:)`/`dataDir(for:)`), and call `PluginPaths.ensure(.directories(for: id))`
   (create both directories) inside the private `start` before spawning. `config_dir`/`data_dir` in
   `InitializeParams` stay `configRoot/<id>` and `dataRoot/<id>`. The task 22 tests that set
   `configRoot`/`dataRoot` to temporary directories keep working unchanged.
8. `ItemAdapters.swift`: add a temporary `public enum LegacySettings` (deleted in task 29) with
   getters and setters over `Settings`:
   - `scriptFolders(_ s: Settings) -> [String]` (`plugins["scripts"].values["folders"]` as
     `.array` of `.string`; default `[]`), `scriptFolderURLs(_:) -> [URL]` (tilde-expanded, the old
     `scriptFolders` computed property), `scriptWatch(_:) -> Bool` (default true),
     `searchURL(_:) -> String` (`plugins["web"].values["search_url"]`; default
     `https://duckduckgo.com/?q={query}`, also when empty), `currencyEnabled(_:) -> Bool`
     (`plugins["calculator"].values["currency"]`, default true), `windowEnabled(_:) -> Bool`
     (`plugins["windows"].enabled`, default false), `cascadeStep(_:) -> Double`
     (`plugins["windows"].values["cascade_step"]`, default 32, values outside 16…120 → 32).
   - Matching mutating setters `setScriptFolders(_:in:)`, `setScriptWatch`, `setSearchURL`,
     `setCurrencyEnabled`, `setWindowEnabled`, `setCascadeStep` that update `settings.plugins` through
     `setPluginState`.
9. `AppDelegate.swift`:
   - Add `private let pluginSettings = PluginSettingsStore()`, `private var commands: [CommandItem] =
     []`, `private let commandsWatcher = ConfigWatcher(path: PluginPaths.commandsFile)`.
   - `loadInitialConfig`: unchanged apart from the template (still `config.example.toml`). Add
     `loadInitialCommands()`: `ConfigLoader.ensureExists(at: PluginPaths.commandsFile, template:
     ConfigLoader.commandsExamplePath)` (creating the directory is done by `ensureExists`), then
     `commands = try ConfigLoader.load(from: PluginPaths.commandsFile).config.commands`; on error
     `report("Commands error: …")` and keep `[]`. Start `commandsWatcher` like `configWatcher`, calling a
     new `reloadCommands(from:source:)` that parses with `ConfigParser.parse` and only replaces
     `commands` (log `"commands applied (<source>): N commands"`).
   - `reloadConfig` no longer touches commands; `rebuildItems` uses `commands` instead of
     `config.commands`; `applyLink` calls `LinkEditor.save(to: PluginPaths.commandsFile, …)` then
     `commandsWatcher.markApplied` + `reloadCommands`.
   - Replace every `settings.search/window/scripts/currency` read with the `LegacySettings` getter;
     `settingsWindow.update(windowSettings:)` becomes `update(windowEnabled: Bool)`.
   - Wire the store: after `loadInitialSettings` set `pluginSettings.settings = settings`; whenever the
     registry rescans, set `pluginSettings.packages = registry.packages` and `registry.enabled =
     pluginSettings.enabledIDs()`; `pluginSettings.onChange = { [weak self] in self?.applySettings($0,
     persist: true) }`. In `applySettings`: assign `pluginSettings.settings = updated`; compute
     `json(for:)` for every running id before and after; set `runtime.settingsProvider = { [weak
     self] package in self?.pluginSettings.json(for: package.id) ?? [:] }` once in `wirePanel`; after a
     settings change call `Task { await runtime.sync(enabled: registry.enabledPackages()) }` (this
     starts newly enabled and stops newly disabled providers) and, for ids still running whose
     `json(for:)` changed, `await runtime.configure(id, settings: pluginSettings.json(for: id))`.
     Keep the existing `foldersChanged` rescan logic but based on `LegacySettings.scriptFolders/
     scriptWatch`.
   - `status.onOpenConfig` keeps opening `ConfigLoader.defaultPath` (now v2).
10. `SettingsWindowController.swift`: replace each `settings.scripts…`, `settings.search.url`,
    `settings.currency.enabled`, `settings.window.enabled` read/write with the `LegacySettings`
    getter/setter; `update(windowSettings:)` → `update(windowEnabled: Bool)` storing into settings via
    `LegacySettings.setWindowEnabled`; `refreshWindowManagement` reads through the getters.
11. `Resources/config.example.toml`: keep only the `[general]` block. Create
    `Resources/commands.example.toml` with exactly the four `[[commands]]` entries removed from it
    (Open Projects, GitHub, GitHub Search, Uptime). `Makefile` `bundle`: add
    `cp Resources/commands.example.toml $(CONTENTS)/Resources/` after the config example line.
12. Tests:
    - `SettingsTests.swift`: `pluginTablesRoundTrip` (settings with `[plugins.calculator] enabled =
      false, currency = false`, `[plugins.windows] cascade_step = 40`, `[plugins.scripts] folders =
      ["~/x"]`, two item overrides → `serialized()` → `parse` equals the original; integer and float
      numbers both decode as `.number`); `unknownKeysAreKept`; `emptySettingsParse` (`Settings.empty`,
      `plugins` empty); `legacyAccessorsDefaults` (every getter default on `.empty`; `cascadeStep` of
      15, 121, -1 → 32; 16, 40.5, 120 kept); `applyUsesGlobalIDs` (moved from ScriptTests:
      `applications:/Applications/Xcode.app` disabled, `commands:build` alias `bb`).
    - `PluginSettingsStoreTests.swift`: build two `PluginPackage`s from inline manifests via
      `ManifestParser.parse` (a bundled one with `default_enabled = false` and a bool + number
      setting; a user one with `default_enabled = true`): `isEnabled` defaults (bundled false, user
      false despite the manifest), `setEnabled` flips and fires `onChange`, `effective` returns
      defaults, overlays a valid stored value, ignores an out-of-range number and a wrong-typed bool,
      `set` rejects an invalid value (settings unchanged, no `onChange`), `json(for:)` shape.
    - `ConfigTests`: `parsesExample` unchanged (it is an inline string); add `commandsFileGeneralIsIgnored`
      (a text with `[general] hotkey = "cmd+k"` and one command parses; caller ignores `.general`).
    - `ScriptTests`: delete the two moved tests. `LinkEditorTests` need no change.
13. `README.md`: Config section paths → `~/.config/odd-frog/v2/config.toml` (`[general]` only) and
    `~/.config/odd-frog/v2/plugins/commands/commands.toml` for `[[commands]]`; Settings section →
    `~/.config/odd-frog/v2/settings.toml` with a `[plugins.<id>]` example (`[plugins.windows]
    enabled = true` / `cascade_step = 32`, `[plugins.scripts] folders = […]` / `watch = true`,
    `[plugins.web] search_url = …`, `[plugins.calculator] currency = true`); state that the previous
    files are left untouched and are not imported; history path `…/odd-frog/v2/frecency.json`; rates
    cache `…/odd-frog/v2/plugins/calculator/rates.json`.

## Constraints
- No code comments of any kind, in any file (the two existing comments in `LinkEditor.swift` stay).
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `OddFrogCore` stays AppKit-free; Swift Testing only; tests use
  temporary directories, never the real home directory or the network; no new dependencies.
- Never read, write, or delete `~/.config/odd-frog/config.toml`, `~/.config/odd-frog/settings.toml`,
  `~/Library/Application Support/odd-frog/frecency.json` or `rates.json`.
- Do not change the wire protocol, manifests, or any type in `OddFrogPluginAPI` beyond the optional
  `Int` decode attempt in `JSONValue`.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes, including the new `SettingsTests` and `PluginSettingsStoreTests` suites and
  the existing `LinkEditorTests`.
- Manual after `make run` with no `~/.config/odd-frog/v2` directory: `~/.config/odd-frog/v2/
  config.toml`, `settings.toml` is absent until a setting changes, `plugins/commands/commands.toml`
  (with the four example commands) exist; the launcher shows GitHub, Open Projects, Uptime; editing
  `commands.toml` by hand updates the launcher without a restart; toggling Window management in
  Settings writes `[plugins.windows] enabled = true` into `settings.toml`; adding a script folder
  writes `[plugins.scripts] folders = [...]`; the old `~/.config/odd-frog/config.toml` is byte-for-byte
  unchanged; `~/Library/Application Support/odd-frog/v2/frecency.json` appears after running an item.

## Out of scope
- Any plugin extraction, `plugin.toml` files, or the Plugins settings pane.
- Migration tooling for legacy files (documented as manual in task 31).
- Removing `LegacyAdapters`/`LegacySettings` (task 29).

## Open questions
none
