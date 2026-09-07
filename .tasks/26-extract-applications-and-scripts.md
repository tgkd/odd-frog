# Task: Plugin system rework 8/13 — Applications and Scripts providers

Eighth of thirteen tasks (19–31). Requires tasks 19–25. After this task the app index and the script
folders are published by two persistent catalog providers; the host no longer scans applications or
script folders, and no longer owns `AppScanner`, `AppIndexer`, `ScriptScanner`, or `DirectoryWatcher`.
Commands and the calculator still run through the temporary host adapters.

## Goal
`make run` bundles `Plugins/applications` (provider `OddFrogAppsPlugin`) and `Plugins/scripts`
(provider `OddFrogScriptsPlugin`, settings `folders` and `watch`). Apps and scripts appear in the
launcher exactly as today (titles, duplicate-title folder subtitles, package subtitles, emoji icons,
argument placeholders, ⌘↩ terminal runs, notifications), new apps or scripts show up within a few
seconds through `catalog_changed`, and disabling either plugin removes its items and stops its
process. Scanner logic lives in two small library targets with their tests moved from Core.

## Files
- Package.swift                                              (modify — `OddFrogAppsKit`, `OddFrogScriptsKit`, two executables, two test targets)
- Makefile                                                   (modify — bundle both providers)
- Plugins/applications/plugin.toml                           (create)
- Plugins/scripts/plugin.toml                                (create)
- Sources/OddFrogPluginAPI/DirectoryWatcher.swift            (create — moved from Core, made public)
- Sources/OddFrogAppsKit/AppScanner.swift                    (create — moved from Sources/OddFrogCore/AppIndexer.swift)
- Sources/OddFrogAppsKit/AppCatalog.swift                    (create — `[AppItem]` → `[PluginItem]`)
- Sources/OddFrogAppsPlugin/main.swift                       (create)
- Sources/OddFrogAppsPlugin/AppsHandler.swift                (create)
- Sources/OddFrogScriptsKit/ScriptScanner.swift              (create — moved from Sources/OddFrogCore/Scripts.swift + script types from Item.swift)
- Sources/OddFrogScriptsKit/ScriptCatalog.swift              (create — `[ScriptItem]` → `[PluginItem]`, shell quoting)
- Sources/OddFrogScriptsPlugin/main.swift                    (create)
- Sources/OddFrogScriptsPlugin/ScriptsHandler.swift          (create)
- Sources/OddFrogCore/AppIndexer.swift                       (delete)
- Sources/OddFrogCore/Scripts.swift                          (delete)
- Sources/OddFrogCore/DirectoryWatcher.swift                 (delete)
- Sources/OddFrogCore/Item.swift                             (modify — delete `AppItem`, `ScriptMode`, `ScriptArgument`, `ScriptItem`; keep `CommandItem`/`CommandAction`)
- Sources/OddFrogCore/ItemAdapters.swift                     (modify — delete `apps(_:)`, `scripts(_:)`)
- Sources/OddFrogCore/PluginRegistry.swift                   (modify — `import OddFrogPluginAPI` for `DirectoryWatcher`)
- Sources/OddFrog/AppDelegate.swift                          (modify — remove indexer, scanners, watchers, Rescan)
- Sources/OddFrog/StatusMenu.swift                           (modify — remove "Rescan Apps")
- Sources/OddFrog/IconCache.swift                            (modify — `prewarm(_ items: [LauncherItem])`)
- Sources/OddFrog/SettingsWindowController.swift             (modify — folder counts by plugin id + local id)
- Sources/OddFrog/HostServices.swift                         (modify only if the empty-argument rule in Context is missing)
- Tests/OddFrogAppsKitTests/AppScannerTests.swift            (create — moved from AppIndexerTests + the symlink case)
- Tests/OddFrogAppsKitTests/AppCatalogTests.swift            (create)
- Tests/OddFrogScriptsKitTests/ScriptScannerTests.swift      (create — moved scanner cases from ScriptTests)
- Tests/OddFrogScriptsKitTests/ScriptCatalogTests.swift      (create)
- Tests/OddFrogCoreTests/AppIndexerTests.swift               (delete)
- Tests/OddFrogCoreTests/ScriptTests.swift                   (delete — remaining cases move or are covered elsewhere)
- Tests/OddFrogCoreTests/ItemAdaptersTests.swift             (modify — drop apps/scripts cases)
- Tests/OddFrogCoreTests/BundledManifestsTests.swift         (modify — two more manifests)
- README.md                                                  (modify — Rescan Apps removed; scripts settings live under the Scripts plugin)

## Context
- `Sources/OddFrogCore/AppIndexer.swift` holds `AppScanner` (`defaultRoots`, `AppScanCache`,
  `scan(roots:maxDepth:cache:)`, `watchedDirectories(roots:)`, `makeItem`) and the `AppIndexer` actor
  (`refresh()` with an in-flight task and a cache). It uses `Bundle(url:)` for names/bundle ids and is
  Foundation-only. `AppItem {url, name, bundleID, aliases}` is in `Item.swift`.
- `Sources/OddFrogCore/Scripts.swift` holds `ScriptScanner` (`scan(folders:)`, `parse(url:executable:)`,
  `parse(header:url:executable:)`, `parseArgument`), reading 4096 header bytes, requiring `#!` and the
  executable bit, honouring `@raycast.title/mode/icon/packageName/argument1`; `ScriptItem {url, title,
  mode, icon, package, argument, aliases}`, `ScriptMode {silent, fullOutput, inline}`, `ScriptArgument
  {placeholder, optional}` are in `Item.swift`. Scanning never executes scripts.
- `Sources/OddFrogCore/DirectoryWatcher.swift`: `final class DirectoryWatcher: @unchecked Sendable`,
  `watch(_ directories: [URL], onChange:)`, `stop()`, 0.3 s debounce, drops sources for deleted
  directories. Used by `AppDelegate` (`scriptWatcher`, `appWatcher`) and task 21's `PluginRegistry`.
- Task 20's `LegacyAdapters.apps(_:)`/`scripts(_:)` define the item shapes this task must reproduce in
  the plugins: apps → local id = bundle path, `icon: .file(path)`, `action: .launch(path)`, `secondary:
  .reveal(path)`, subtitle = parent folder abbreviated with `~` only when another app shares the title
  (case-insensitive); scripts → local id = script path, title, subtitle = `package` when it differs
  from the title (case-insensitive), `kind: "Script"`, icon `.emoji` when the header icon is an emoji
  else `.glyph(text: ">_", color: gray, size: 10)`, `argument` from `@raycast.argument1`, primary
  action `exec(executable: path, arguments: ["{argument}"] when an argument exists else [], cwd:
  parent, output: .notify)` for silent/inline and `terminal(command: "<quoted path> {argument}" (or
  without the token), cwd: parent)` for fullOutput, `secondary` always the terminal form.
- Host substitution rule (task 20, `HostServices`): `{argument}` is replaced by the typed argument
  (shell-quoted inside `terminal.command`, verbatim inside `exec.arguments`); when the item's argument
  is optional and none was typed, `exec.arguments` elements equal to `{argument}` are dropped and the
  token in `terminal.command` is replaced by an empty string. If task 20's implementation lacks the
  empty-argument half of that rule, add it in `HostServices.swift` in this task.
- `AppDelegate` today: `indexer.refresh()` on launch, `rearmAppWatcher()` over
  `AppScanner.watchedDirectories`, `refreshScripts(force:)` with a 60 s throttle and on panel show
  when `watch` is off, `rewatchScripts()` on folder changes, `icons.prewarm(apps)`, and the status
  menu "Rescan Apps" item (`status.onRescan`).
- `SettingsWindowController.recomputeFolderCounts` counts scripts per folder by prefix of the script
  path; after task 20 it filters `pluginID == "scripts"` and uses `item.item.id` as the path.
- Task 24's `LegacySettings.scriptFolders/scriptWatch` read `plugins["scripts"].values["folders"/"watch"]`;
  those keys become the Scripts plugin's declared settings here, so stored data is unchanged and
  `PluginSettingsStore.json(for: "scripts")` delivers them to the provider.
- Test resources: `Tests/OddFrogCoreTests` has `Fixtures/`; the new kit test targets need none
  (they create temporary directories).
- Decisions: scanners move into library targets (`OddFrogAppsKit`, `OddFrogScriptsKit`) rather than
  into the executables so they stay unit-testable; `DirectoryWatcher` moves to `OddFrogPluginAPI`
  (Foundation-only) instead of being copied three times; the two kits extend the design's target
  table and the executables depend on them. Apps plugin roots stay `AppScanner.defaultRoots`
  (`/Applications`, `~/Applications`, `/System/Applications`,
  `/System/Library/CoreServices/Applications`, depth 2). Bundle-id metadata is dropped from items
  (nothing consumed it).

## Plan
1. `Package.swift`: add `.target(name: "OddFrogAppsKit", dependencies: ["OddFrogPluginAPI"])`,
   `.target(name: "OddFrogScriptsKit", dependencies: ["OddFrogPluginAPI"])`,
   `.executableTarget(name: "OddFrogAppsPlugin", dependencies: ["OddFrogPluginAPI", "OddFrogAppsKit"])`,
   `.executableTarget(name: "OddFrogScriptsPlugin", dependencies: ["OddFrogPluginAPI", "OddFrogScriptsKit"])`,
   `.testTarget(name: "OddFrogAppsKitTests", dependencies: ["OddFrogAppsKit"])`,
   `.testTarget(name: "OddFrogScriptsKitTests", dependencies: ["OddFrogScriptsKit"])`.
2. Move `DirectoryWatcher` to `Sources/OddFrogPluginAPI/DirectoryWatcher.swift` unchanged except
   `public` on the class, `init`, `watch`, `stop`. Delete the Core file; add `import OddFrogPluginAPI`
   to `PluginRegistry.swift` and `AppDelegate.swift`.
3. `OddFrogAppsKit`:
   - `AppScanner.swift`: the `AppScanner` enum and `AppItem` struct moved verbatim (`public`), without
     `AppIndexer` (the handler owns its cache).
   - `AppCatalog.swift`: `public enum AppCatalog { public static func items(for apps: [AppItem]) ->
     [PluginItem] }` producing the shape in Context (subtitle only on duplicate titles; `abbreviate`
     replaces the home prefix with `~`).
4. `OddFrogScriptsKit`:
   - `ScriptScanner.swift`: `ScriptScanner`, `ScriptItem`, `ScriptMode`, `ScriptArgument` moved
     verbatim (`public`).
   - `ScriptCatalog.swift`: `public enum ScriptCatalog { public static func items(for scripts:
     [ScriptItem]) -> [PluginItem]; static func quote(_:) -> String }` (quote = today's
     `ShellCommand.quote`: single quotes with `'\''` escaping) producing the shape in Context.
5. `Plugins/applications/plugin.toml`: `[plugin] id = "applications"`, `name = "Applications"`,
   `version = "1.0.0"`, `api = 1`, description "Installed applications."; `[provider] mode =
   "persistent"`, `executable = "OddFrogAppsPlugin"`, `catalog = true`; `[services] uses = ["launch"]`.
6. `Plugins/scripts/plugin.toml`: id `scripts`, name "Scripts", description "Executable scripts from
   your folders, with Raycast script-command headers."; `[provider] mode = "persistent"`, `executable
   = "OddFrogScriptsPlugin"`, `catalog = true`; `[services] uses = ["exec", "terminal"]`; settings:
   `key = "folders"`, `type = "folders"`, `title = "Script folders"`, description "Every executable
   script in these folders becomes a launcher item.", `default = []`; `key = "watch"`, `type =
   "bool"`, `title = "Watch for changes"`, description "Rescan when a script is added, removed or
   edited.", `default = true`.
7. `Sources/OddFrogAppsPlugin/AppsHandler.swift`: `final class AppsHandler: PluginHandler` with a
   lock-guarded `cache: AppScanner.AppScanCache`, `apps: [AppItem]`, `watcher = DirectoryWatcher()`,
   and `server: PluginServer?` (set by `main.swift` so the handler can `emit`). `initialize`: scan
   synchronously (30 s budget is ample), start the watcher on `AppScanner.watchedDirectories(roots:
   AppScanner.defaultRoots)`; on change rescan with the cache, re-arm the watcher, and if the app list
   changed `server.emit(Event(event: EventName.catalogChanged, params: nil))`. `catalog` returns
   `AppCatalog.items(for: apps)`. `shutdown` stops the watcher. `main.swift`: create the handler, the
   `PluginServer(handler:)`, assign `handler.server = server`, `await server.run()`.
8. `Sources/OddFrogScriptsPlugin/ScriptsHandler.swift`: same structure; settings `folders` (array of
   strings, tilde-expanded with `NSString.expandingTildeInPath`) and `watch` read at `initialize` and
   `configure`; scan with `ScriptScanner.scan(folders:)`; watch the folders only when `watch` is true
   (otherwise `watcher.watch([])`); on change or on `configure` rescan and emit `catalog_changed` when
   the list changed. `catalog` returns `ScriptCatalog.items(for: scripts)`.
9. `Makefile`: `PLUGINS := windows web terminal applications scripts`; add `cp .build/release/
   OddFrogAppsPlugin $(CONTENTS)/PlugIns/applications/` and `cp .build/release/OddFrogScriptsPlugin
   $(CONTENTS)/PlugIns/scripts/`; add both paths to the per-executable `codesign` loop.
10. Host removals: delete `AppIndexer.swift`, `Scripts.swift`, the four script/app types from
    `Item.swift`, `LegacyAdapters.apps/scripts`; in `AppDelegate` delete `indexer`, `apps`, `scripts`,
    `scriptWatcher`, `appWatcher`, `lastScriptScan`, `refreshApps`, `refreshScripts`, `rewatchScripts`,
    `rearmAppWatcher`, the `foldersChanged` branch in `applySettings` (the store's `configure` call
    from task 24 now carries folder changes to the provider), the script refresh in `showPanel`, and
    `status.onRescan`; `StatusMenu` drops "Rescan Apps" (task 21's "Reload Plugins" stays).
    `rebuildItems` composes `registry.declarativeItems() + runtime.catalogItems() + LegacyAdapters
    .commands(commands) + …` and calls `icons.prewarm(items)` where `IconCache.prewarm` now takes
    `[LauncherItem]` and prewarms every `.file` icon path. `runtime.onCatalogChanged` triggers
    `rebuildItems` (task 22 wiring; verify it exists).
11. `SettingsWindowController.recomputeFolderCounts`: read folders through `LegacySettings
    .scriptFolderURLs`, count items with `pluginID == "scripts"` whose `item.id` has the folder prefix
    (temporary; task 30 replaces the pane).
12. Tests:
    - `AppScannerTests.swift` (AppsKit): the three `AppIndexerTests` cases plus
      `appScanSkipsBrokenSymlinksAndDedupesAliases` from ScriptTests, unchanged apart from imports.
    - `AppCatalogTests.swift`: two apps titled "Xcode" in `/Applications` and `~/Applications` get
      subtitles "/Applications" and "~/Applications", a unique "Safari" gets none; ids are bundle
      paths; action `.launch`, secondary `.reveal`, icon `.file`.
    - `ScriptScannerTests.swift` (ScriptsKit): `parsesRaycastHeader`, `optionalArgumentAndFullOutput`,
      `executableWithoutHeaderUsesFilename`, `nonExecutableOrNoShebangIsSkipped`,
      `scanSkipsBinariesAndSources` moved from `ScriptTests` (same fixtures and assertions).
    - `ScriptCatalogTests.swift`: a silent script with an argument → `exec` with `arguments ==
      ["{argument}"]`, `output == .notify`, cwd = parent, secondary `.terminal` whose command is the
      quoted path + ` {argument}`; a fullOutput script without argument → primary `.terminal` with the
      quoted path only; package subtitle rule; emoji vs glyph icon; `kind == "Script"`.
    - `ItemAdaptersTests`: drop the apps/scripts cases. `BundledManifestsTests`: add
      `applicationsIsCatalogOnly` (catalog true, no query, uses `[.launch]`) and `scriptsDeclaresFolders`
      (settings `folders` type folders default `.folders([])`, `watch` bool default true, uses
      `[.exec, .terminal]`).
    - Delete `AppIndexerTests.swift` and `ScriptTests.swift` (every remaining case is moved above or
      was deleted in task 24).
13. `README.md`: remove "Rescan Apps" from the menu list; the "Script folders" bullet says the folders
    are the Scripts plugin's settings (stored under `[plugins.scripts]`); note that Reload Plugins
    restarts the Applications and Scripts providers.

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `OddFrogPluginAPI`, both kits and both executables import only
  `Foundation` (+ `OddFrogPluginAPI`/the kit); `OddFrogCore` stays AppKit-free; Swift Testing only;
  tests use temporary directories and never spawn the plugin executables or touch the network; no
  new third-party dependencies.
- Script discovery must not execute scripts (header bytes only).
- Host dispatch and rendering must not switch on plugin ids; the folder-count check in the Settings
  window is the one temporary exception and is labelled as such in the turn summary.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes, including `OddFrogAppsKitTests` and `OddFrogScriptsKitTests`.
- `swift test --filter OddFrogScriptsKitTests` and `swift test --filter OddFrogAppsKitTests` pass.
- `make bundle` succeeds; `build/OddFrog.app/Contents/PlugIns/applications/OddFrogAppsPlugin` and
  `…/scripts/OddFrogScriptsPlugin` exist and are signed.
- Manual after `make run`: `xcode` finds Xcode with its real icon; two same-named apps show folder
  subtitles; a script folder added in Settings shows its scripts within a few seconds; `kp 3000`
  runs a script with an argument and shows its notification; ⌘↩ on a script opens the terminal; adding
  a new script file to a watched folder makes it appear without any menu action; disabling
  `[plugins.scripts] enabled = false` in `settings.toml` removes every script and
  `pgrep -f OddFrogScriptsPlugin` finds no process.

## Out of scope
- Commands, links, calculator (tasks 27–28); removing `LegacyAdapters.commands` and
  `LegacySettings` (tasks 27, 29); the Plugins pane (task 30).
- Changing scan roots, depth, or Raycast header semantics.

## Open questions
none
