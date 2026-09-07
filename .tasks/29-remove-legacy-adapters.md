# Task: Plugin system rework 11/13 — remove the temporary adapters and every feature-specific host branch

Eleventh of thirteen tasks (19–31). Requires tasks 19–28: all seven feature packages are
extracted and the host runs them through `PluginRegistry`, `PluginRuntime`, `SearchCoordinator`,
and `HostServices`. What is left in the host is scaffolding that kept the tree buildable during the
extraction: `LegacyAdapters`, `LegacyProviders`, `LegacySettings`, the legacy item structs,
`QuickAction`, `WindowAction`'s item half, `[[commands]]` parsing in `ConfigParser`, and a handful
of `pluginID == "…"` checks in the UI. This task deletes all of it. Behaviour does not change.

## Goal
`Sources/OddFrogCore` and `Sources/OddFrog` contain no legacy item types, no adapters, no
in-process providers, no plugin-identity checks, and no command parsing; the grep in Acceptance
prints nothing; `swift test` passes with the obsolete tests removed or ported; the app behaves
exactly as after task 28.

## Files
- Sources/OddFrogCore/ItemAdapters.swift                  (delete)
- Sources/OddFrogCore/Item.swift                          (delete if still present — task 26 removed the app/script types and task 27 deleted the file with `CommandItem`; `WindowItem` may survive in it or in ItemAdapters.swift)
- Sources/OddFrogCore/QuickAction.swift                   (delete)
- Sources/OddFrogCore/WindowAction.swift                  (modify — keep `WindowEdge`, `WindowFraction`, `WindowLayout`; delete `WindowAction`)
- Sources/OddFrogCore/Config.swift                        (modify — delete command types, command validation, `RawCommand`, command error cases)
- Sources/OddFrogCore/LauncherItem.swift                  (modify — only if it still references a deleted type)
- Sources/OddFrogCore/SearchEngine.swift                  (modify — only if it still references a deleted type)
- Sources/OddFrog/AppDelegate.swift                       (modify — delete legacy state and wiring)
- Sources/OddFrog/HostServices.swift                      (modify — window action dispatch on `WindowOperation` without `WindowAction`)
- Sources/OddFrog/WindowManager.swift                     (modify — `perform(operation:edge:fraction:cascadeStep:)`)
- Sources/OddFrog/SettingsWindowController.swift          (modify — folder counts and Manage Links without identity checks)
- Sources/OddFrog/LauncherViewController.swift            (modify — only if an identity check remains)
- Sources/OddFrog/IconCache.swift                         (modify — only if a legacy branch remains)
- Tests/OddFrogCoreTests/QuickActionTests.swift           (delete)
- Tests/OddFrogCoreTests/ItemAdaptersTests.swift          (delete — created by task 20)
- Tests/OddFrogCoreTests/WindowLayoutTests.swift          (modify — port to the new `WindowLayout.frame(edge:fraction:in:)`; delete `actionIdsAndTitles`)
- Tests/OddFrogCoreTests/ConfigTests.swift                (modify — delete command cases)
- Tests/OddFrogCoreTests/ScriptTests.swift                (delete if only adapter/settings cases remain; task 26 moved the scanner cases to `OddFrogScriptsKitTests` and task 24 moved settings cases to `SettingsTests`)
- Tests/OddFrogCoreTests/SearchEngineTests.swift          (modify — helpers build `LauncherItem(pluginID:item:)` directly)
- Tests/OddFrogCoreTests/SearchCoordinatorTests.swift     (modify — same, if it used adapters)
- Sources/OddFrogCore/PluginRegistry.swift                (read — `declaredServices(for:)`, `manifest(for:)`, created by task 21)
- Sources/OddFrogCore/PluginSettingsStore.swift           (read — `effective(for:)`, created by task 24)
- Sources/OddFrog/LinkService.swift                       (read — capability-based link editing, created by task 27)

## Context
- `LauncherItem` (task 20) is `struct LauncherItem { pluginID: String; item: PluginItem }`; tests
  that used `LegacyAdapters.apps(...)` or `.app(AppItem(...))` helpers must construct
  `LauncherItem(pluginID: "applications", item: PluginItem(id: "/Applications/X.app", title: "X",
  action: .launch(path: "/Applications/X.app")))` directly. `PluginItem`'s memberwise init (task 19)
  defaults `aliases: []`, `recordable: true`, all optionals nil.
- Today's `WindowAction` (Sources/OddFrogCore/WindowAction.swift) carries `id`, `title`,
  `subtitle`, `kindLabel`, `all`; the manifest `Plugins/windows/plugin.toml` (task 25) owns those
  now. `WindowLayout.frame(for action: WindowAction, in visible: CGRect) -> CGRect?` returns
  `visible` for `.maximize`, nil for `.tidy`, and an edge/fraction rectangle for `.place`.
  `WindowLayout.cascade(count:in:step:)` and `flipped(_:primaryHeight:)` are action-free and stay.
- `WindowManager.perform(_ action: WindowAction, cascadeStep:)` (Sources/OddFrog/WindowManager.swift)
  branches on `WindowLayout.frame(for:in:)` returning nil to run the tidy path; it logs
  `"window: \(action.title) → …"`. `HostServices` (task 20) currently converts
  `PluginAction.window(operation:edge:numerator:denominator:)` into a `WindowAction` before calling
  it, validating `edge` against `WindowEdge(rawValue:)` and `numerator/denominator` against
  `WindowFraction`'s precondition (`numerator > 0 && denominator >= numerator`).
- `ConfigParser` (Sources/OddFrogCore/Config.swift) still parses `[[commands]]` because the legacy
  commands adapter used it until task 27 moved command parsing into `OddFrogCommandsKit`. After 27
  the host reads only `[general]`. `ConfigError` cases to delete: `commandMissingAction`,
  `commandMultipleActions`, `commandInvalidURL`, `commandTerminalWithoutShell`,
  `duplicateCommandName`, `duplicateAlias`, `emptyName`. `ConfigTests` cases to delete:
  `rejectsMissingAction`, `rejectsMultipleActions`, `rejectsDuplicateAlias`,
  `rejectsTerminalWithoutCommand`; `parsesExample` must assert only `[general]` values (the example
  file lost its commands in task 24). Keep `expandTilde`, hotkey handling, `replacingHotkey`,
  `ensureExists`.
- `QuickAction` (Sources/OddFrogCore/QuickAction.swift) after task 28 contains `openURL`,
  `webSearch`, `terminal`, `detectURL`, `fallbacks`. The web plugin owns URL detection
  (`Sources/OddFrogWebPlugin/URLDetection.swift`, task 25) and the terminal plugin owns `>`; nothing
  in the host may still call these. `QuickActionTests.detectURL*`,
  `terminalPrefixYieldsSingleTerminalAction`, `nonURLQueryYieldsWebSearchFallback`,
  `noSearchTemplateAndNoURLYieldsNoFallbacks` go with it (task 25 recorded that they were kept only
  until this task).
- Identity checks known to exist in the host after task 28 (verify with grep, there may be more):
  - `SettingsWindowController.recomputeFolderCounts` matches `pluginID == "scripts"` and reads the
    local id as a path to count scripts per folder. Replace with a data-driven lookup: find the
    enabled package whose manifest declares a `folders`-typed setting, then count that package's
    catalog items (`LauncherItem.pluginID == package.id`, a comparison against a looked-up value,
    not a literal) whose local id has the folder path as prefix.
  - `SettingsWindowController.showLinks` filters `pluginID == "commands"`; task 27 replaced the
    data source with `LinkService` (`links.list`), so only the enabling condition remains: the
    button is enabled when `LinkService.resolve(registry:runtime:)` returns a provider. Delete any
    remaining identity check.
  - `AppDelegate` may still hold `apps`, `scripts`, `config.commands`, `scriptWatcher`,
    `appWatcher`, `rewatchScripts`, `refreshScripts`, `refreshApps`, `rearmAppWatcher`,
    `lastScriptScan`, `indexer`; task 26 removed most. Delete anything left. `rebuildItems` must be
    exactly: catalog = `registry.declarativeItems() + runtime.catalogItems()`, then
    `settings.apply(to:)`, then hand to the coordinator and (if visible) the settings window.
  - `LauncherViewController.isQuick`/`transient` checks and `detail(for:)` were generalized in
    task 20; confirm no `pluginID ==` remains.
- Grep that must print nothing at the end (run from the repo root):
  ```
  grep -rnE 'LegacyAdapters|LegacyProviders|LegacySettings|QuickAction|CalculationKind|\bAppItem\b|\bCommandItem\b|\bCommandAction\b|\bScriptItem\b|\bScriptMode\b|\bScriptArgument\b|\bWindowItem\b|\bWindowAction\b|\.app\(|\.command\(|\.script\(|\.quick\(|\.window\(|pluginID == "' Sources/OddFrogCore Sources/OddFrog Tests/OddFrogCoreTests
  ```
  (`Sources/OddFrogAppsKit`, `Sources/OddFrogScriptsKit`, `Sources/OddFrogCommandsKit` and their
  plugins own their own `AppItem`/`ScriptItem`/`CommandItem` types and are excluded on purpose.)
- The Script Folders pane still exists after this task (task 30 replaces it with the Plugins
  pane). It must read and write only through `PluginSettingsStore` (task 24):
  `store.effective(for: id)["folders"]` / `["watch"]` and `store.set(id:key:value:)`, where `id` is
  the id of the first enabled package whose manifest has a `folders`-typed setting (data-driven,
  not a literal `"scripts"`). If no such package exists the pane shows its empty state and disables
  `+`.

## Plan
1. Delete `Sources/OddFrogCore/ItemAdapters.swift`, `Sources/OddFrogCore/QuickAction.swift`,
   `Sources/OddFrogCore/Item.swift` (if task 27 has not already removed it), `Tests/OddFrogCoreTests/QuickActionTests.swift`,
   `Tests/OddFrogCoreTests/ItemAdaptersTests.swift` with `git rm`. Build; fix every reference the
   compiler reports by following steps 2–7 (do not reintroduce any deleted type).
2. `Sources/OddFrogCore/WindowAction.swift`: delete `enum WindowAction`. Replace
   `WindowLayout.frame(for:in:)` with
   `public static func frame(edge: WindowEdge, fraction: WindowFraction, in visible: CGRect) -> CGRect`
   containing the existing `.place` arithmetic. Maximize is `visible` itself; callers handle it.
3. `Sources/OddFrog/WindowManager.swift`: change `perform` to
   `func perform(operation: WindowOperation, edge: WindowEdge?, fraction: WindowFraction?, cascadeStep: CGFloat) -> Outcome`.
   `.maximize` → `setFrame(flipped(visible))`; `.place` → requires `edge` and `fraction` (return
   `.failed("place needs an edge and a fraction")` otherwise) and uses `WindowLayout.frame(edge:
   fraction:in:)`; `.tidy` → the existing cascade path. Log lines use `operation.rawValue` plus
   edge/fraction label (`WindowFraction.label` stays) instead of `action.title`.
4. `Sources/OddFrog/HostServices.swift`: the `.window` branch validates `edge` with
   `WindowEdge(rawValue:)` and `numerator`/`denominator` (`numerator > 0`, `denominator >=
   numerator`) before constructing `WindowFraction`, refusing with a logged failure
   `"window: invalid parameters"` otherwise, then calls the new `perform`. Delete the `WindowAction`
   conversion.
5. `Sources/OddFrogCore/Config.swift`: delete `CommandItem`-related types and validation, the
   `RawCommand` struct, `RawConfig.commands`, the seven command error cases, and the `commands`
   property of `Config` (with its `init` parameter). `Config` becomes `general` only.
   `ConfigParser.build` keeps only the `[general]` block.
6. `Sources/OddFrog/AppDelegate.swift` and `SettingsWindowController.swift`: apply the Context
   list — delete leftover legacy state, make `rebuildItems` the three-line form, make folder counts
   and the Folders pane data-driven through `PluginSettingsStore`/`PluginRegistry` (the folder-setting
   plugin id is looked up, never written as a literal), and confirm `showLinks` has no identity
   check.
7. Tests:
   - `WindowLayoutTests`: `placementsAnchorToEdges` calls `WindowLayout.frame(edge:fraction:in:)`;
     delete `actionIdsAndTitles`. Add one `SearchEngineTests` case that constructs the ten window
     items as `LauncherItem(pluginID: "windows", item: …)` (ids `place-left-1-2`, …, `maximize`,
     `tidy`, kind `Window`) and asserts `Settings.apply` disables `windows:maximize` and an alias
     override on `windows:tidy` makes `cascade` find it — this preserves the behavioural half of the
     deleted test.
   - `ConfigTests`: delete the four command cases; `parsesExample` asserts hotkey/terminal/shell/
     max_results only.
   - `SearchEngineTests`, `SearchCoordinatorTests`: replace adapter-based helpers with direct
     `LauncherItem(pluginID:item:)` construction; keep every assertion.
   - Delete `ScriptTests.swift` if nothing but adapter/settings cases remain; otherwise delete only
     those cases.
8. Run the grep from Context; it must print nothing. Run `swift test`.

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `OddFrogCore` stays AppKit-free.
- No hard-coded plugin id string anywhere in `Sources/OddFrogCore` or `Sources/OddFrog` (test files
  may use ids as data).
- Behaviour must not change: no new features, no UI changes beyond removing dead code paths.
- Use `git rm`/`git mv` so history is preserved.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- The grep in Context prints nothing.
- `swift build` succeeds (from the repo root).
- `swift test` passes.
- `swift build -c release` and `make bundle` succeed.
- Manual after `make run`: apps, commands, scripts, calculator rows, `>` terminal row, URL/search
  fallbacks, and (after enabling the Windows plugin in `settings.toml` with
  `[plugins.windows]\nenabled = true`) the ten Window items all behave as before; Settings › Script
  Folders still lists folders with script counts and `+`/`−` work; Settings › Items › Manage Links…
  still opens and saves.

## Out of scope
- The Plugins pane and removal of the Script Folders pane (task 30).
- Makefile packaging targets and documentation (task 31).
- Any change inside `Sources/OddFrog*Kit`, `Sources/OddFrog*Plugin`, or `Plugins/`.

## Open questions
none
