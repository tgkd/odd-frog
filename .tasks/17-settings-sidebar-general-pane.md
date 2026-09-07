# Task: Settings window — sidebar navigation, unified title bar, General pane as grouped rows

Task 17. First of two for the "Odd Frog Settings" design; task 18
(`18-settings-folders-items-panes.md`) restyles the Script Folders and Items panes and builds on
this one. Source of truth for the visuals: the Claude Design artboard `Odd Frog Settings.dc.html`
in the "app_launch_" project (System Settings–style window: sidebar on the left, one pane on the
right, settings as rows inside rounded grouped boxes).

## Goal
Settings opens as a 760 × 560 window with a translucent 200 pt sidebar holding three rows
(General, Script Folders, Items, each with a coloured icon tile), the traffic lights inside the
sidebar's 52 pt top strip, and a 52 pt header on the right showing the current pane's title.
Clicking a sidebar row swaps the pane. The General pane is three grouped boxes of full-width rows
(title + subtitle on the left, control on the right): Keyboard shortcut and Launch at login; a
"Search" box with Web search; an "Extras" box with Window management (plus an Accessibility line
with an "Open System Settings…" button when access is missing) and Currency conversion. The
Script Folders and Items panes show today's folder and item groups unchanged apart from the box
radius; `⌘I` from the launcher still lands on the Items pane with the alias editor open.

## Files
- Sources/OddFrog/SettingsWindowController.swift   (modify — window setup, root layout, General pane, present/refresh)
- Sources/OddFrog/SettingsSidebar.swift             (create — `SettingsPane`, sidebar table, row and cell views)
- Sources/OddFrog/IconTile.swift                    (create — coloured rounded tile with a white SF Symbol)
- Sources/OddFrog/GroupBox.swift                    (modify — corner radius 10 → 12)
- README.md                                        (modify — "Settings" section intro)
- Sources/OddFrog/SelectionPalette.swift            (read — `SelectionPalette.fill`, `ink(_:)` for selected-row colours)
- Sources/OddFrog/HotkeyRecorder.swift              (read — 22 pt tall self-drawn control; unchanged)
- Sources/OddFrog/AppDelegate.swift                 (read — `showSettings`, `present(...focusing:)`, `@settings` snapshot hook; unchanged)

## Context
- SwiftPM package, Swift 6 strict concurrency, macOS 14 deployment target, AppKit only, no
  Xcode project. `swift build -c release` builds; `swift test` runs 109 Swift Testing tests in
  `OddFrogCoreTests` (none cover the UI); `make run` bundles `build/OddFrog.app` and relaunches it.
- `SettingsWindowController` (`@MainActor final class`, `NSWindowController` + table/text
  delegates, `NSWindowDelegate`) today builds one window 960 × 640 (min 920 × 420) whose content
  view holds three vertically stacked groups made by `makeGeneralGroup()`, `makeFoldersGroup()`,
  `makeItemsGroup()`. A `Metrics` struct (`regular`/`compact`) plus `apply(_:)`,
  `windowDidResize`, `isCompact`, `gapConstraints`, `paddingLeading/Trailing/Bottom`,
  `folderBarHeight`, `searchFieldWidth`, `itemsBoxHeight` implement a compact mode below 600 pt
  width. All of that compact machinery goes away in this task; `layoutColumns()` (proportional
  item-table columns, called from `windowDidResize` and `present`) stays.
- `makeGeneralGroup()` builds five equal-width `settingBlock(title:control:helper:)` boxes in a
  horizontal stack: Shortcut (`hotkeyRecorder` + `hotkeyHelper`), Launch at login (`loginSwitch`
  + `loginButton` "Open Login Items…" + `loginStatus`), Web search (`webSearchField` +
  `webSearchHelper`), Window management (`windowSwitch` + `windowAccessButton` "Open System
  Settings" + `windowHelper`), Currency (`currencySwitch` + `currencyHelper`). The controls, their
  targets/actions and the refresh methods (`showHotkey(_:note:)`, `refreshLogin()`,
  `refreshWindowManagement()`, `refreshCurrencyHelper()`, `resetWebSearchHelper()`,
  `controlTextDidEndEditing` for the web-search validation) already exist and keep their
  behaviour; only the layout and some strings change.
- Public API used by `AppDelegate` and kept as is: `init(icons:)`, `present(settings:items:hotkey:)`,
  `present(settings:items:hotkey:focusing:)`, `update(items:)`, `update(windowSettings:)`,
  `refreshLogin()`, `showHotkey(_:note:)`, `onChange`, `onHotkey`, `onApplyLink`, `settings`.
  `present(focusing: id)` with a non-nil id selects that item in the Items table and calls
  `beginAliasEdit(row:)`; with nil it puts focus in `filterField`.
- `GroupBox` is a layer-backed `NSView`: `controlBackgroundColor` fill, 0.5 pt `separatorColor`
  border, `cornerRadius = 10`, continuous curve, `masksToBounds`. Every grouped box in the
  window uses it.
- `SelectionPalette.fill` is `selectedContentBackgroundColor`; `SelectionPalette.ink(appearance)`
  returns primary/secondary/tertiary text colours for use on that fill. `FolderRowView` in the
  controller file draws its selection with `SelectionPalette.fill`, and `FolderCellView` recolours
  its labels through `isRowSelected` — the pattern to mirror for sidebar rows.
- `FolderTable` (private `NSTableView` subclass at the bottom of the controller file) shows how
  tables are configured here: single `NSTableColumn`, `headerView = nil`,
  `selectionHighlightStyle = .none`, `intercellSpacing = .zero`, `backgroundColor = .clear`,
  `style = .plain`, inside an `NSScrollView` with `drawsBackground = false`,
  `borderType = .noBorder`.
- `LoginItem.status` (`SMAppService.Status`) has four cases mapped in `refreshLogin()`:
  `.enabled` → "Odd Frog opens when you log in."; `.requiresApproval` → orange "Waiting for
  approval in System Settings › Login Items." plus the visible `loginButton`; `.notFound` →
  switch disabled, "Move Odd Frog to your Applications folder to enable this."; default (not
  registered) → "Open Odd Frog automatically when you log in.".
- `refreshWindowManagement()` today: switch off → helper "Adds Left ⅔, Top ¾, Tidy Windows and
  friends to the launcher. Needs Accessibility access."; on with `WindowManager.hasAccess` →
  "Accessibility access granted."; on without access → red "Allow Odd Frog under Privacy &
  Security › Accessibility." and `windowAccessButton` shown. It also syncs `currencySwitch` and
  is re-run from `applicationDidBecomeActive` while the window is visible.
- `refreshCurrencyHelper()` today toggles between "Rates from exchangerate-api.com." and "No
  currency row, no network.".
- `AppDelegate.snapshotPanel()` renders the settings window: write `@settings` to
  `~/Library/Logs/odd-frog-query.txt`, run `pkill -USR2 -x OddFrog`, and
  `~/Library/Logs/odd-frog-settings.png` appears 0.5 s later. It renders the window's content
  view, so a full-size content view captures the sidebar too.
- Design values (points), taken from the artboard:

  | element | value |
  |---|---|
  | window | 760 × 560, radius from the system; content area background `windowBackgroundColor` |
  | sidebar | 200 wide, `NSVisualEffectView` material `.sidebar`, blending `.behindWindow`, 0.5 pt `separatorColor` line on its right edge |
  | sidebar top strip | 52 tall, empty (traffic lights live there) |
  | sidebar rows | list padding 4 top/bottom, 10 sides; rows 36 tall, 2 apart, 6 side padding, radius 7; tile 24 × 24 radius 6 with a white symbol; 8 gap; label 13 pt `labelColor`; selected row `SelectionPalette.fill` with `ink.primary` label |
  | tiles | General: `systemGray` + `gearshape.fill`; Script Folders: `systemTeal` + `folder.fill`; Items: `controlAccentColor` + `square.grid.2x2.fill`; symbol point size 13, weight medium |
  | content header | 52 tall, 20 side padding, pane title 15 pt semibold `labelColor` |
  | pane body | padding 0 20 20; sections stacked with 12 gap; a section header is 13 pt semibold with 6 extra top space and a 2 pt leading inset |
  | grouped box | `GroupBox`, radius 12 |
  | setting row | min height 44, padding 8 top/bottom 16 sides; left column: title 13 pt `labelColor` over subtitle 11 pt `secondaryLabelColor`, 2 apart, subtitle wraps; 16 gap; right cluster hugs its content, centred vertically; rows separated by a 0.5 pt `separatorColor` hairline inset 16 on both sides |
  | shortcut control | `HotkeyRecorder` as is (22 tall, radius 8) |
  | switches | `NSSwitch`, `controlSize = .small` |
  | web search field | `NSTextField`, `.roundedBezel`, 290 wide, 22 tall, 13 pt |
  | accessibility line | below the Window management row inside the same box: min height 36, padding 0 16 10, pulled up 4; red 11 pt sentence taking the free width, then `windowAccessButton` (`.rounded`, `.small`, 11 pt) |
  | small buttons | `bezelStyle = .rounded`, `controlSize = .small`, 11 pt font (`loginButton`, `windowAccessButton`) |

  Copy (exact strings):
  - Row titles: `Keyboard shortcut`, `Launch at login`, `Web search`, `Window management`,
    `Currency conversion`. Section headers: `Search`, `Extras` (the first box has none).
  - Sidebar rows and pane titles: `General`, `Script Folders`, `Items`.
  - Keyboard shortcut subtitle: today's `hotkeyHelper` strings unchanged ("Click, then press a
    new combination.", "Press the keys you want to use.", conflict note + " Try another
    combination." in red).
  - Launch at login subtitle: `.enabled`, `.requiresApproval`, `.notFound` strings unchanged;
    not registered → empty subtitle.
  - Web search subtitle: `Used when nothing matches. {query} is replaced with your search.`;
    validation failure keeps today's red `Enter a full URL containing {query}.`.
  - Window management subtitle, always: `Move and resize the front window from the launcher.`
    Accessibility line (only when the switch is on and `WindowManager.hasAccess` is false):
    `Allow Odd Frog under Privacy & Security › Accessibility.` + button `Open System Settings…`.
  - Currency conversion subtitle, always: `Rates from exchangerate-api.com.`
  - Window title stays `Odd Frog Settings` (hidden from the title bar, still used by the Window
    menu and accessibility).

## Plan
1. `Sources/OddFrog/IconTile.swift` (new): `final class IconTile: NSView`, `init(color:
   NSColor, symbol: String, side: CGFloat, radius: CGFloat, pointSize: CGFloat)`. Layer-backed,
   continuous corners, background = `color`; a centred `NSImageView` with
   `NSImage(systemSymbolName:)`, `SymbolConfiguration(pointSize:weight: .medium)`,
   `contentTintColor = .white`. Fixed width/height constraints from `side`. Re-apply the layer
   colour in `viewDidChangeEffectiveAppearance` and `updateLayer` the way `GroupBox` does so
   `controlAccentColor` tracks the system accent.
2. `Sources/OddFrog/GroupBox.swift`: `layer.cornerRadius = 12`.
3. `Sources/OddFrog/SettingsSidebar.swift` (new):
   - `enum SettingsPane: Int, CaseIterable { case general, folders, items }` with `title`
     ("General", "Script Folders", "Items"), `symbol`, and `tint`.
   - `final class SettingsSidebar: NSView` wrapping an `NSVisualEffectView` (`.sidebar`,
     `.behindWindow`, `state = .followsWindowActiveState`), a 0.5 pt trailing separator view, and
     an `NSTableView` (configured like `FolderTable`, `rowHeight 36`, `allowsEmptySelection =
     false`) in a non-scrolling `NSScrollView` (`hasVerticalScroller = false`) pinned 52 from the
     top, 10 from the sides, 4 below the strip. Data source/delegate live in this class:
     `SettingsPane.allCases.count` rows; the cell is `SidebarCellView` (an `IconTile` 24/6/13 +
     13 pt label, 6 side padding, 8 gap); the row view draws `SelectionPalette.fill` in a
     7 pt rounded rect when selected and flips the label to `SelectionPalette.ink(...).primary`
     (mirror `FolderRowView`/`FolderCellView`).
   - API: `var selected: SettingsPane` (get: selected row; set: selects the row without
     firing the callback) and `var onSelect: ((SettingsPane) -> Void)?` fired from
     `tableViewSelectionDidChange` when the selection came from the user.
4. `SettingsWindowController.swift`
   - Window: `contentRect` 760 × 560, `styleMask` `[.titled, .closable, .miniaturizable,
     .resizable, .fullSizeContentView]`, `minSize` 760 × 560, `titlebarAppearsTransparent =
     true`, `titleVisibility = .hidden`, `titlebarSeparatorStyle = .none`, `toolbarStyle =
     .unified`, and an empty `NSToolbar(identifier: "settings")` with `showsBaselineSeparator =
     false` assigned to `window.toolbar` (the empty unified toolbar is what makes the title bar
     52 pt tall and centres the traffic lights in it). Keep `isReleasedWhenClosed = false`,
     `backgroundColor = .windowBackgroundColor`, `center()`.
   - Delete `Metrics`, `isCompact`, `apply(_:)`, `gapConstraints`, `paddingLeading`,
     `paddingTrailing`, `paddingBottom`, `folderBarHeight`, `searchFieldWidth`,
     `itemsBoxHeight`, and the compact branch of `windowDidResize` (keep the `layoutColumns()`
     call). Replace the hard-coded `Metrics.regular.*` reads in `makeFoldersGroup()` and
     `makeItemsGroup()` with the literal regular values (folder row 28, bar 32, search width
     200, items min height 150, helper shown).
   - `buildContent()`: content view gets `sidebar` (leading, top, bottom, width 200) and a
     `paneHost` view on the right. `paneHost` = 52 pt header (`paneTitle` label 15 pt semibold at
     20 leading, centred vertically) + `paneContainer` below it with 20 pt side and bottom
     padding. `paneContainer` holds three pane views pinned to all edges; only the selected one
     is visible (`isHidden`). Pane views: `makeGeneralPane()` (new), and the existing
     `makeFoldersGroup()` / `makeItemsGroup()` results unchanged, each wrapped so it pins to the
     top and sides of the container (the Items group also pins to the bottom, since its box
     takes the remaining height).
   - `showPane(_ pane: SettingsPane)`: set `sidebar.selected`, `paneTitle.stringValue`,
     hidden flags; when the Items pane appears and no alias edit is in progress make
     `filterField` first responder; when leaving the Items pane call `endAliasEdit(commit:
     true)`. Store `currentPane` (starts `.general`); `sidebar.onSelect` calls `showPane`.
   - `makeGeneralPane()`: a vertical `NSStackView` (spacing 12, alignment leading/trailing
     stretched) containing:
     1. `GroupBox` with `settingRow(title: "Keyboard shortcut", subtitle: hotkeyHelper,
        control: hotkeyRecorder)` and `settingRow(title: "Launch at login", subtitle:
        loginStatus, control: loginControl)` (the existing horizontal stack of `loginSwitch` +
        `loginButton`), separated by a hairline;
     2. section header `Search`; `GroupBox` with `settingRow(title: "Web search", subtitle:
        webSearchHelper, control: webSearchField)` where the field is 290 wide;
     3. section header `Extras`; `GroupBox` with `settingRow(title: "Window management",
        subtitle: windowHelper, control: windowSwitch)`, then the `accessLine` view (red
        `accessLabel` + `windowAccessButton`, hidden by default), a hairline, and
        `settingRow(title: "Currency conversion", subtitle: currencyHelper, control:
        currencySwitch)`.
     `settingRow(title:subtitle:control:)` returns a view laid out per the design table: title
     and subtitle labels in a vertical stack on the left (subtitle wraps, `maximumNumberOfLines
     = 0`, low compression resistance horizontally), control on the right with required hugging,
     min height 44, padding 8/16. A `hairline()` helper returns a 0.5 pt `separatorColor` view
     with 16 pt side insets; `sectionHeader(_:)` returns the 13 pt semibold label with 6 pt top
     and 2 pt leading insets. Delete `settingBlock(title:control:helper:)`. Section headers and
     boxes are added to the stack as full-width arranged subviews.
   - Strings: `refreshLogin()` default case → `loginStatus.stringValue = ""`.
     `resetWebSearchHelper()` → "Used when nothing matches. {query} is replaced with your
     search.". `refreshCurrencyHelper()` → always "Rates from exchangerate-api.com." (keep the
     method so its call sites compile, or inline the constant and delete it).
     `refreshWindowManagement()`: `windowHelper` is always "Move and resize the front window
     from the launcher." in `secondaryLabelColor`; `accessLine.isHidden = !(settings.window.enabled
     && !WindowManager.hasAccess)`. Everything else in that method (switch states, currency
     sync) stays.
   - `present(...focusing:)`: with a target id call `showPane(.items)` before selecting the row
     and beginning the alias edit; with nil keep `currentPane` and, if it is `.items`, focus
     `filterField`, otherwise `window?.makeFirstResponder(nil)`. `update(items:)` and
     `update(windowSettings:)` are unchanged.
   - Move `FolderTable`, `FolderRowView`, `FolderCellView`, `FolderBar`, `ItemTable` only if you
     touch them; they can stay where they are.
5. `README.md`, "## Settings" section: replace the opening line with a short paragraph: the
   window has a sidebar with three panes, **General** (keyboard shortcut, launch at login, web
   search, window management, currency), **Script Folders**, and **Items**; `settings.toml` is
   still hot-reloaded. Leave the bullet list and TOML example as they are.
6. Manual check: `make run`, menu bar → Settings…. Take the `@settings` snapshot (Context) and
   compare with the artboard: sidebar with three tiles, General selected, the three boxes. Click
   each sidebar row; press `⌘I` in the launcher on an app to confirm the Items pane opens with
   the alias editor active; toggle Window management on without Accessibility access to see the
   red line and button appear inside the Extras box.

Approach decisions:
- Sidebar as a custom-drawn `NSTableView` inside an `NSVisualEffectView`, not
  `NSSplitViewController`/source list: the app already draws its own selection rows with
  `SelectionPalette`, and a split view would add a draggable divider the design does not have.
- Panes are hidden/shown views in one container, not an `NSTabView`: no tab chrome, no
  re-layout when switching, and the Items table keeps its state.
- The design's back/forward capsule in the header is decorative (no history to navigate); it is
  not built. The ✕ inside the shortcut field is not built either: there is no "no hotkey"
  state (decided in task 03).
- Switches use `controlSize = .small` because the artboard uses the 26 × 16 switch.

## Constraints
- No comments in source.
- Swift 6 strict concurrency; every new class is `@MainActor final class`; `[weak self]` in
  stored closures; delayed work uses `DispatchQueue.main.asyncAfter { MainActor.assumeIsolated
  { … } }` as the file already does; notification observers use the selector form.
- Semantic AppKit colours only (`windowBackgroundColor`, `controlBackgroundColor`,
  `separatorColor`, `labelColor`/`secondaryLabelColor`/`tertiaryLabelColor`,
  `controlAccentColor`, `systemGray`, `systemTeal`, `systemRed`, `systemOrange`, `white`) plus
  `SelectionPalette` for selected rows.
- Auto Layout throughout (`translatesAutoresizingMaskIntoConstraints = false`); no frame math
  except inside `draw(_:)`.
- Copy strings exactly as listed in Context.
- Do not change `Sources/OddFrogCore/`, `AppDelegate.swift`, `HotkeyRecorder.swift`,
  `AliasCellView.swift`, `HoverRowView.swift`, `LinkManagerController.swift`, or the launcher
  files.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build -c release` passes from the repo root.
- `swift test` passes from the repo root (109 tests, unchanged).
- `make run` → menu bar → Settings…: the window is 760 × 560, cannot shrink below that, has no
  visible title text, and shows the traffic lights inside the translucent sidebar's top strip.
  The sidebar lists General (grey gear), Script Folders (teal folder), Items (accent grid);
  General is selected on first open and the header on the right reads "General".
- General pane: box 1 has "Keyboard shortcut" with the recorder on the right and "Launch at
  login" with a small switch; "Search" header above a box with "Web search" and a 290 pt field;
  "Extras" header above a box with "Window management" and "Currency conversion" switches. Rows
  are separated by hairlines inset from the box edges.
- With Window management switched on and Accessibility not granted, a red "Allow Odd Frog under
  Privacy & Security › Accessibility." line with an "Open System Settings…" button appears under
  that row inside the box; granting access and returning to the window removes the line.
- Clicking "Script Folders" and "Items" swaps the pane and the header title; the folder list
  and item table behave as before (add/remove folders, filter, alias editing).
- From the launcher, `⌘I` on an item opens Settings on the Items pane with that item selected
  and its alias editor active; `⌘,` opens Settings on whichever pane was last shown.
- The README "Settings" section mentions the sidebar and its three panes.

## Out of scope
- Restyling the Script Folders pane (intro card, 44 pt rows, watch box) and the Items pane
  (full-width filter, 36 pt rows, footer with Manage Links) — task 18.
- Back/forward navigation buttons, a ✕ clear button in the shortcut field, keyboard shortcuts
  for switching panes, remembering the pane across app launches.
- Any change to `Settings` in Core or to `settings.toml`.

## Open questions
none
