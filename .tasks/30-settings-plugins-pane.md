# Task: Plugin system rework 12/13 — Settings: replace Script Folders with a Plugins pane

Twelfth of thirteen tasks (19–31). Requires tasks 19–29: every feature is a plugin, the host has
no feature-specific code, and settings for scripts folders, web search, currency, window
management, and cascade step are manifest-declared plugin settings stored under
`[plugins.<id>]` in `~/.config/odd-frog/v2/settings.toml`. Until now those settings had either
no UI or a UI left over from the pre-plugin General/Script Folders panes. This task gives every
plugin one page in Settings.

## Goal
Settings has three panes: **General** (keyboard shortcut, launch at login), **Plugins**, and
**Items**. The Plugins pane lists every discovered package with source, execution mode, query
activation, status, and an enable switch, and shows for the selected package its description,
version, error text, a Reload button, an Accessibility helper when relevant, and every
manifest-declared setting rendered by type. Edits persist immediately through the existing
`onChange(Settings)` path and reach running providers via `configure`. The Script Folders pane and
the General pane's Search and Extras groups are gone.

## Files
- Sources/OddFrog/SettingsSidebar.swift                    (modify — `SettingsPane` cases)
- Sources/OddFrog/SettingsWindowController.swift           (modify — remove Folders pane + Extras/Search groups; host the Plugins pane)
- Sources/OddFrog/PluginsPane.swift                        (create)
- Sources/OddFrog/PluginSettingControls.swift              (create — per-type setting rows)
- Sources/OddFrog/FolderListView.swift                     (create — folder list extracted from the old Folders pane)
- Sources/OddFrog/AppDelegate.swift                        (modify — pass registry/runtime/store to the settings window; refresh on status changes)
- README.md                                                (modify — Settings section)
- Sources/OddFrog/LinkService.swift                        (read — how the links capability is resolved, created by task 27)
- Sources/OddFrogCore/PluginRegistry.swift                 (read — created by task 21)
- Sources/OddFrogCore/PluginRuntime.swift                  (read — created by task 22)
- Sources/OddFrogCore/PluginSettingsStore.swift            (read — created by task 24)
- Sources/OddFrogPluginAPI/PluginManifest.swift            (read — `SettingDefinition`, `SettingValue`, `ProviderSpec`, `QuerySpec`, created by task 19)
- Sources/OddFrog/GroupBox.swift                           (read — rounded container used by every pane)
- Sources/OddFrog/IconTile.swift                           (read — `IconTile(color:symbol:side:radius:pointSize:)`)
- Sources/OddFrog/HoverRowView.swift                       (read — row hover pattern used by the Items table)

## Context
- `SettingsPane` (Sources/OddFrog/SettingsSidebar.swift) is `enum SettingsPane: Int, CaseIterable
  { case general, folders, items }` with `title`, `symbol` (`gearshape.fill`, `folder.fill`,
  `square.grid.2x2.fill`), `tint` (`.systemGray`, `.systemTeal`, `.controlAccentColor`). The
  sidebar table uses `rawValue` as the row index; `SidebarCellView(pane:)` draws an `IconTile` and
  the title.
- `SettingsWindowController` (Sources/OddFrog/SettingsWindowController.swift) builds panes in
  `buildContent()` into a `panes: [SettingsPane: NSView]` dictionary; `showPane(_:)` toggles
  `isHidden`. Pane content is built with helpers `settingRow(title:subtitle:control:)`,
  `groupedBox(_:)`, `hairline()`, `sectionHeader(_:)`, `stackedPane(_:)`, `style(helper:)`; the
  Items pane is the only one pinned to the container bottom. The window is 760×560 minimum with a
  200 pt sidebar. Existing General pane groups after task 28: "shortcuts" (hotkey recorder, launch
  at login), "Search" (web search field + helper, `controlTextDidEndEditing` validation), "Extras"
  (window switch, `accessLine` with `windowAccessButton`, `buildAccessLine()`,
  `refreshWindowManagement()`, `toggleWindowManagement()`, `openAccessibilitySettings()`,
  `applicationDidBecomeActive` re-check). After task 29 the Search/Extras groups write through
  `PluginSettingsStore` to the `web`/`windows` packages' settings; they are removed here because the
  Plugins pane renders the same settings from the manifests.
- Folders pane pieces to extract and delete: `FolderTable` (Delete/Backspace → `onDelete`),
  `FolderRowView`, `FolderCellView` (folder symbol, path, "N scripts" count),
  `makeFoldersPane()`, `makeFoldersIntro()`, `addFolder()` (NSOpenPanel, `canChooseDirectories`,
  `allowsMultipleSelection`, `~` abbreviation of `homeDirectoryForCurrentUser.path`),
  `removeFolder()`, `toggleWatch()`, `updateFolderListHeight()` (rows clamped 1…5 × 44 pt),
  `reloadFolders()`, `recomputeFolderCounts()`, `folderCounts`, `folderEmptyLabel`
  ("No script folders yet. Click + to add one."), `addFolderButton`/`removeFolderButton` (26 pt
  wide, `.rounded`, `.small`), `watchSwitch`.
- Plugin data available to the UI:
  - `PluginRegistry.packages: [PluginPackage]` (`id`, `manifest: PluginManifest?`, `directory`,
    `source: PluginSource` (`bundled`/`user`), `error: String?`), `status(for:) -> PluginStatus`
    (`disabled`, `idle`, `running`, `failed(String)`, `invalid(String)`), `declaredServices(for:)
    -> Set<HostService>`, `rescan()`, `onChange`.
  - `PluginRuntime.reload(_ package: PluginPackage) async`, `status(for:) -> PluginStatus?`, `onStatusChanged`.
  - `PluginSettingsStore.effective(for:) -> [String: SettingValue]`, `set(id:key:value:)`,
    `setEnabled(id:_:)`, `isEnabled(id:)`.
  - `PluginManifest` (task 19): `name`, `version`, `description`, `provider: ProviderSpec?`
    (`mode: .persistent/.oneshot`, `catalog`), `query: QuerySpec?` (`role`, `prefix`, `activation`,
    `keywords`), `settings: [SettingDefinition]` (`key`, `type`, `title`, `description`,
    `defaultValue`, `min`, `max`, `choices`, `mustContain`, `validate(_:) -> SettingValue?`).
    `SettingValue` cases: `bool`, `string`, `number`, `folders`; choice values are `.string`.
- `WindowManager.hasAccess` (`AXIsProcessTrusted()`), `WindowManager.requestAccess()`, and
  `WindowManager.openAccessibilitySettings()` are static and stay in the host.
- `LinkService` (task 27) exposes a way to resolve the running provider that `provides = ["links"]`;
  `showLinks` already uses it. The "Manage Links…" button must be enabled only when it resolves.
- Settings persistence: `SettingsWindowController.commit()` calls `onChange?(settings)`;
  `AppDelegate.applySettings(_:persist:)` saves `settings.toml`, updates the store, starts/stops
  providers on enable changes, and calls `configure` on running providers whose effective settings
  changed (task 24). The pane therefore mutates through the store and then calls `commit()`.
- The `⌘I` reveal flow (`present(settings:items:hotkey:focusing:)` selecting the Items pane and
  starting an alias edit) must keep working unchanged.

## Plan
1. `SettingsSidebar.swift`: `SettingsPane` becomes `general, plugins, items` with titles
   "General", "Plugins", "Items"; symbols `gearshape.fill`, `puzzlepiece.extension.fill`,
   `square.grid.2x2.fill`; tints `.systemGray`, `.systemOrange`, `.controlAccentColor`.
2. Create `Sources/OddFrog/FolderListView.swift`: `@MainActor final class FolderListView: NSView`
   wrapping the extracted list (`GroupBox` containing the table, empty label, hairline, `+`/`−`
   bar; height rule 1…5 rows × 44 pt). API: `var folders: [String]` (display strings with `~`),
   `var counts: [Int]` (per folder; the "N scripts" cell text uses "1 script"/"N scripts"),
   `var onChange: (([String]) -> Void)?`, `func present(in window: NSWindow)` needed for the
   NSOpenPanel sheet (use `self.window` when non-nil). Move `FolderTable`, `FolderRowView`,
   `FolderCellView`, add/remove logic, and the `~` abbreviation here verbatim.
3. Create `Sources/OddFrog/PluginSettingControls.swift`: `@MainActor enum PluginSettingControls`
   with `static func row(for definition: SettingDefinition, value: SettingValue, onChange:
   @escaping (SettingValue) -> Void, validationMessage: NSTextField) -> NSView` returning a view
   shaped like `settingRow(title:subtitle:control:)` (copy that helper into this file as a static
   so both files can use it, or keep it in the controller and expose it `fileprivate`→`internal`;
   choose the latter to avoid duplication). Controls by type:
   - `bool` → `NSSwitch` (`controlSize = .small`), action → `.bool`.
   - `string` → `NSTextField` (`roundedBezel`, 290 pt wide, placeholder = default value); on end
     editing, trim, build `.string`, run `definition.validate`; nil → helper text
     `"Enter a value containing \(mustContain)."` when `mustContain` is set, otherwise
     `"Invalid value."`, red, and the field reverts; success → helper shows `description` in
     secondary color.
   - `number` → `NSTextField` (80 pt) + `NSStepper` (min/max from the definition, default
     0…1_000_000 when absent, increment 1); values clamped through `validate`; invalid text reverts.
   - `choice` → `NSPopUpButton` with `choices`; selection → `.string`.
   - `folders` → a `FolderListView`; `onChange` → `.folders`.
   Each row's subtitle is `definition.description ?? ""`.
4. Create `Sources/OddFrog/PluginsPane.swift`: `@MainActor final class PluginsPane: NSView,
   NSTableViewDataSource, NSTableViewDelegate`.
   - Init `init(registry: PluginRegistry, runtime: PluginRuntime, store: PluginSettingsStore,
     scriptCounts: @escaping (String, [String]) -> [Int])` — the count closure is supplied by the
     controller (it has `allItems`) and returns per-folder counts for a plugin id and folder list
     by matching catalog items of that plugin whose local id has the expanded folder path as
     prefix.
   - Layout: left `GroupBox` 260 pt wide with an `NSTableView` (one column, row height 52,
     `HoverRowView` rows, `selectionHighlightStyle = .none` drawn like the Items table); right side
     a vertical `NSStackView` inside an `NSScrollView` for the detail.
   - Row cell: `IconTile` (bundled → `.systemGray` `shippingbox.fill`; user → `.systemTeal`
     `person.crop.circle.fill`), name (13 pt), caption (11 pt secondary) built as
     `"<Source> · <Mode> · <Queries>"` where Source is "Bundled"/"User", Mode is "Declarative"
     when `provider == nil`, else "Persistent"/"One-shot", and Queries is absent when `query ==
     nil`, else "Exclusive “>”" (prefix quoted) / "Live queries" / "Fallback" with " · keyword
     kp, …" appended for keyword activation; a 8 pt status dot (`.systemGreen` running,
     `.systemGray` idle/disabled, `.systemRed` failed/invalid, `.systemOrange` when enabled but the
     manifest is nil); an `NSSwitch` (`.small`) bound to `store.isEnabled(id:)`, disabled when the
     package is invalid.
   - Detail for the selected package: title (15 pt semibold) + version (secondary), description,
     a status line (`"Running"`, `"Not running"`, `"Disabled"`, or the failure/invalid message in
     `.systemRed`, wrapping), a "Reload" button (`.rounded`) calling `Task { await runtime.reload(package) }` when
     the package has a provider and `registry.rescan()` always, the Accessibility line ("Allow Odd
     Frog under Privacy & Security › Accessibility." + "Open System Settings…" button, shown only
     when the plugin is enabled, `registry.declaredServices(for:)` contains `.window`, and
     `!WindowManager.hasAccess`; enabling such a plugin calls `WindowManager.requestAccess()`),
     then one `groupedBox` of `PluginSettingControls.row` views for `manifest.settings` with
     values from `store.effective(for:)`.
   - Changes: switch → `store.setEnabled(id:_:)`; control → `store.set(id:key:value:)`; then
     `onChange?()` (the controller wires this to `commit()`).
   - `func reload()` re-reads packages/statuses and reloads the table keeping the selection by id;
     `func refreshAccess()` re-evaluates the Accessibility line.
5. `SettingsWindowController.swift`:
   - `init(icons:registry:runtime:store:)`; build `PluginsPane` in `buildContent()` under
     `.plugins`; delete everything listed under "Folders pane pieces" and the Search/Extras groups
     in Context (`webSearchField`, `webSearchHelper`, `resetWebSearchHelper`, the
     `controlTextDidEndEditing` web-search branch, `windowSwitch`, `windowHelper`, `accessLine`,
     `windowAccessButton`, `buildAccessLine`, `refreshWindowManagement`, `toggleWindowManagement`,
     `openAccessibilitySettings`, `update(windowSettings:)`). `applicationDidBecomeActive` now calls
     `pluginsPane.refreshAccess()`.
   - `present(...)` calls `pluginsPane.reload()`; `update(items:)` also refreshes plugin folder
     counts.
   - `showPane(.items)` keeps its first-responder handling; `showPane(.plugins)` selects the first
     row when nothing is selected.
   - "Manage Links…" `isEnabled` follows `LinkService` resolution; re-evaluate on `present`, on
     `pluginsPane.onChange`, and on status changes.
   - `numberOfRows`/`viewFor` lose their `folderTable` branches.
6. `AppDelegate.swift`: construct `SettingsWindowController(icons:registry:runtime:store:)`;
   delete `settingsWindow.update(windowSettings:)` calls; subscribe `runtime.onStatusChanged` and
   `registry.onChange` (chain to any existing handlers rather than replacing them) to call
   `settingsWindow.refreshPlugins()` (a thin wrapper around `pluginsPane.reload()`) when the window
   is visible.
7. `README.md` Settings section: describe the three panes; replace the Script folders / Web
   search / Currency / Window management bullets with a "Plugins" bullet (enable switch, source,
   status, Reload, per-plugin settings: the Scripts plugin's folders and watch switch, the Web
   plugin's search URL, the Calculator's currency switch, the Windows plugin's cascade step and
   Accessibility prompt); update the `settings.toml` example to the v2 shape:
   ```toml
   [[items]]
   id = "applications:/Applications/Xcode-Beta.app"
   enabled = false

   [[items]]
   id = "scripts:/Users/me/Projects/raycast-scripts/kill-port.sh"
   aliases = ["kp"]

   [plugins.scripts]
   folders = ["~/Projects/raycast-scripts"]
   watch = true

   [plugins.web]
   search_url = "https://duckduckgo.com/?q={query}"

   [plugins.calculator]
   currency = true

   [plugins.windows]
   enabled = true
   cascade_step = 32
   ```
   and the item-id sentence to "Item ids are `<plugin id>:<item id>`, for example
   `applications:/Applications/Xcode.app`, `commands:github`, `scripts:<path>`,
   `windows:place-left-1-2`, `windows:maximize`, `windows:tidy`."

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; all UI classes `@MainActor`.
- No plugin id literal in `Sources/OddFrog` (everything is driven by manifests and registry data).
- Reuse `GroupBox`, `IconTile`, `HoverRowView`, `SelectionPalette`, and the existing row helpers;
  no new dependencies; no emojis in UI strings.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes.
- `make bundle` succeeds.
- Manual after `make run`, menu bar → Settings…:
  - Sidebar shows General, Plugins, Items. General shows only the shortcut and launch-at-login rows.
  - Plugins lists seven bundled packages; captions read e.g. "Bundled · Persistent · Live queries"
    for Calculator, "Bundled · Declarative" for Windows, "Bundled · Persistent · Exclusive “>”" for
    Terminal. Green dots for running providers, gray for Windows (disabled by default).
  - Select Scripts: the folders list with `+`/`−` and the Watch switch appear; adding a folder makes
    its scripts show in the launcher within a few seconds; `~/.config/odd-frog/v2/settings.toml`
    gains `[plugins.scripts] folders = […]`.
  - Select Web: entering a URL without `{query}` shows a red helper and reverts; a valid one is
    used by the "Search for …" fallback immediately.
  - Select Windows: toggle enabled → the Accessibility line appears if access is missing, the ten
    Window items appear in the launcher; cascade step stepper refuses values outside 16–120.
  - Select Calculator: toggling currency off removes the currency row without restart.
  - Copy `Plugins/calculator` to `~/.config/odd-frog/plugins/broken/` and blank its `plugin.toml`
    → the list shows a red-dot "broken" entry whose detail shows the parse error; Reload after
    fixing the file turns it green; the other plugins are unaffected.
  - Items › "Manage Links…" is enabled while the Commands plugin is running and disabled after
    turning it off.
  - ⌘I from the launcher still opens Items with the alias cell editing.

## Out of scope
- Makefile packaging targets, docs, README sections other than Settings (task 31).
- Any change to plugin manifests, providers, or the settings file format.
- Drag-and-drop ordering of plugins, per-plugin logs viewer.

## Open questions
none
