# Task: Settings — Script Folders pane and Items pane restyle

Task 18. Requires task 17 (`17-settings-sidebar-general-pane.md`) merged: it assumes the
sidebar, `paneContainer`, `showPane(_:)`, `settingRow(title:subtitle:control:)`, `hairline()`,
`sectionHeader(_:)`, `IconTile` and a 12 pt `GroupBox` radius exist. Source of truth for the
visuals: the Claude Design artboard `Odd Frog Settings.dc.html` in the "app_launch_" project.

## Goal
The Script Folders pane is an intro card (teal folder tile, title, one-sentence description),
a "Folders" section with the folder list in a grouped box (44 pt rows, script count at the
trailing edge, a 40 pt bottom bar with + and −), and a second box with a "Watch for changes"
row and switch. The Items pane is a full-width filter field, a grouped box holding the table
(36 pt rows, 20 pt icons, 13 pt text), and a footer line with the alias helper sentence on the
left and a "Manage Links…" button on the right. Behaviour is unchanged: add/remove/Delete-key
for folders, filtering, enabling, alias editing, link management.

## Files
- Sources/OddFrog/SettingsWindowController.swift   (modify — `makeFoldersGroup()`, `makeItemsGroup()`, folder row/cell/bar classes, `updateFolderListHeight()`)
- Sources/OddFrog/AliasCellView.swift              (modify — 13 pt labels, 22 pt pill)
- Sources/OddFrog/HoverRowView.swift               (modify — corner radius 7)
- Sources/OddFrog/IconTile.swift                   (read — tile from task 17, reused for the intro card)
- Sources/OddFrog/IconCache.swift                  (read — `icon(for:size:)`)

## Context
- Build `swift build -c release`; tests `swift test` (109 Swift Testing tests, none UI);
  `make run` bundles and relaunches. Snapshot: write `@settings` to
  `~/Library/Logs/odd-frog-query.txt`, run `pkill -USR2 -x OddFrog`, read
  `~/Library/Logs/odd-frog-settings.png` (renders whichever pane is showing).
- After task 17 the panes live in `paneContainer` (20 pt side/bottom padding, below the 52 pt
  header). `makeFoldersGroup()` still returns its old container: a "Script Folders" group title,
  a `GroupBox` with `folderScroll`/`folderTable` (28 pt rows, list capped at 3 rows via
  `folderListHeight`, `updateFolderListHeight()`), `folderEmptyLabel`, a `FolderBar` (32 pt,
  5 % label fill, top hairline, `addFolderButton` `+`, `removeFolderButton` `−`, a "Watch for
  changes" label and `watchSwitch` at the trailing edge), and an 11 pt helper sentence under the
  box. `makeItemsGroup()` returns an "Items" title + `itemsHelper` + "Manage Links…" button +
  `filterField` (`NSSearchField`, `.small`, 200 wide) in one header row, then a `GroupBox`
  containing `itemScroll`/`itemTable` (28 pt rows, `.fullWidth`, native header view, columns
  enabled 30 / name / kind 68 / aliases sized by `layoutColumns()`, `HoverRowView` rows) and
  `itemsEmptyLabel`.
- `FolderCellView`: `folder.fill` symbol 16 pt tinted `systemTeal` (ink colour when selected),
  path 13 pt middle-truncated, count 11 pt tertiary right-aligned; `FolderRowView` fills a 6 pt
  rounded rect inset 1 vertically with `SelectionPalette.fill`. `reloadFolders()` sets the count
  strings (`"1 script"` / `"N scripts"`), the empty label, the `−` enabled state and the list
  height; `folderTable.onDelete` removes the selected folder.
- Item cells: name cell = `icons.icon(for: item, size: 16)` at 16 × 16 with `alphaValue` 0.45
  when disabled + 13 pt label; kind cell 12 pt secondary; `AliasCellView` labels 12 pt inside a
  20 pt pill (`AliasPill`, radius 5) and a 22 pt editor. `HoverRowView.cornerRadius` is 6 with a
  2 pt side inset.
- Design values (points), from the artboard:

  | element | value |
  |---|---|
  | Folders intro card | `GroupBox`; padding 14 top/bottom 16 sides; `IconTile` 28 × 28 radius 7 `systemTeal` `folder.fill` (symbol 15 pt); 12 gap; title 13 pt `labelColor` over description 11 pt `secondaryLabelColor`, 3 apart, wraps |
  | section header | `Folders`, 13 pt semibold, 6 top and 2 leading inset (task 17's `sectionHeader`) |
  | folder list box | `GroupBox`; rows 44 tall, padding 0 16; folder symbol 16 pt `systemTeal`; 12 gap; path 13 pt `labelColor`; count 13 pt `tertiaryLabelColor` at the trailing edge; selected row: `SelectionPalette.fill` edge to edge (no inset, no radius — the box clips the corners), path and symbol `ink.primary`, count `ink.tertiary` |
  | list height | 44 × clamp(count, 1, 5); scrolls beyond 5 rows |
  | list bottom bar | hairline (0.5 `separatorColor`, inset 16) then a 40 pt bar, no fill, padding 0 12, `+` and `−` `.rounded` `.small` buttons 26 wide, 6 apart, at the leading edge |
  | folder empty state | `No script folders yet. Click + to add one.` 13 pt secondary centred in the single empty row |
  | watch box | `GroupBox` with one `settingRow`: title `Watch for changes`, subtitle `Rescan when a script is added, removed or edited.`, control `watchSwitch` (`.small`) |
  | pane stacking | intro card, header, list box, watch box in a vertical stack with 12 gap, pinned top; nothing stretches |
  | Items filter | `NSSearchField`, `controlSize = .regular`, 13 pt, placeholder `Filter`, full pane width, 22 tall |
  | Items box | `GroupBox` taking all remaining height (min 150); native table header (11 pt secondary titles `Item`, `Kind`, `Aliases`, blank for the checkbox column, bottom hairline as the system draws it); table body padding 0 4 |
  | item rows | 36 tall, radius 7 (`HoverRowView.cornerRadius`), 6 side padding inside the row; columns: checkbox 32 (fixed) / name / kind 64 (fixed) / aliases, name : aliases = 2 : 1.4 of the remaining width |
  | item cells | icon 20 × 20 (`icon(for:size: 20)`, 45 % alpha when disabled), 8 gap, name 13 pt; kind 13 pt `secondaryLabelColor`; alias pill 22 tall radius 5, labels 13 pt |
  | items footer | 12 gap row under the box: `itemsHelper` (`Grey aliases are built in. Click a cell to add your own; Return saves.` 11 pt secondary, tail-truncated, takes the free width) and `Manage Links…` `NSButton` `.rounded` `.regular` 13 pt at the trailing edge |
  | items empty state | `No items match “<filter>”.` 13 pt secondary centred in the table body (unchanged) |

## Plan
1. `SettingsWindowController.swift` — `makeFoldersGroup()` (rename to `makeFoldersPane()` if
   task 17 did not already):
   - Return a vertical `NSStackView` (spacing 12) of: intro card (`GroupBox` with an
     `IconTile(color: .systemTeal, symbol: "folder.fill", side: 28, radius: 7, pointSize: 15)`,
     title label `Script Folders`, description label with today's helper sentence "Executable
     scripts in these folders appear in the launcher. Raycast script metadata is optional."),
     `sectionHeader("Folders")`, the list `GroupBox`, and the watch `GroupBox`.
   - List box: `folderScroll` pinned to the box top/sides (no 4 pt inset any more), height
     constraint `folderListHeight`; `folderEmptyLabel` centred in the scroll area; `hairline()`
     under the scroll; a 40 pt bar view (plain `NSView`, delete `FolderBar`'s fill and top line —
     delete the class if nothing else uses it) with `addFolderButton` at 12 leading and
     `removeFolderButton` 6 after it, both 26 wide, centred vertically.
   - `folderTable.rowHeight = 44`. `updateFolderListHeight()`: `44 × max(1, min(count, 5))`.
   - Watch box: `GroupBox` containing `settingRow(title: "Watch for changes", subtitle: <label
     with "Rescan when a script is added, removed or edited.">, control: watchSwitch)`; set
     `watchSwitch.controlSize = .small`. Remove the old `watchLabel` from the bar.
   - `FolderCellView`: symbol leading 16, path leading = symbol + 12, count 13 pt at trailing 16;
     keep middle truncation for the path (paths differ at the end, so tail truncation would hide
     the useful part; deliberate deviation from the artboard's tail ellipsis). `FolderRowView.draw`
     fills `bounds` with `SelectionPalette.fill` when selected (no inset, no rounding).
2. `SettingsWindowController.swift` — `makeItemsGroup()` (rename to `makeItemsPane()` if not
   already):
   - Return a container with three parts pinned vertically: `filterField` at the top (full
     width, `controlSize = .regular`, 13 pt font, height 22), the `GroupBox` 12 below it taking
     the remaining height (`≥ 150`, priority 999 as today), and a footer row 12 below the box
     (`itemsHelper` + `manageLinks` button in a horizontal `NSStackView`, helper hugging low and
     compressing first, button `.rounded` `.regular` 13 pt). Delete the "Items" title label and
     the old header stack. `itemsHelper` is no longer hidden by any metric.
   - `itemTable.rowHeight = 36`. Column widths: enabled 32 (min = max = 32), kind 64
     (max 64); in `layoutColumns()` subtract 32 + 64 and split the rest `2 : 1.4` (name =
     available × 2 / 3.4, aliases = available × 1.4 / 3.4). Give the scroll view a 4 pt
     leading/trailing inset inside the box.
   - Name cell: image view 20 × 20, `icons.icon(for: item, size: 20)`, leading 6, label 8 after
     the image. Kind cell font 13. Checkbox cell unchanged.
3. `HoverRowView.swift`: `cornerRadius = 7`, `sideInset = 0` (the table now has the 4 pt
   inset).
4. `AliasCellView.swift`: labels 13 pt, editor 13 pt, pill height 22, editor height 24.
5. Manual check: `make run` → Settings… → Script Folders: with no folders the box shows the
   empty sentence in one 44 pt row; `+` adds a folder (row shows the teal folder, the path, and
   "N scripts" on the right); selecting fills the whole row with the selection colour; Delete
   removes it; six folders make the list scroll at five rows. Items: the filter spans the pane;
   rows are 36 pt with 20 pt icons; hovering a row without custom aliases shows "Add alias";
   Return on a selected row opens the editor; "Manage Links…" in the footer opens the links
   sheet. Take the `@settings` snapshot on each pane and compare with the artboard.

## Constraints
- No comments in source.
- Swift 6 strict concurrency; `@MainActor`; `[weak self]` in stored closures.
- Semantic AppKit colours only plus `SelectionPalette`; system controls (`NSSwitch`,
  `NSButton`, `NSSearchField`, `NSTableView`); Auto Layout throughout.
- Keep the public API of `SettingsWindowController`, the column identifiers in `Column`, the
  `ItemTable`/`FolderTable` key handling, and alias normalisation as they are.
- Copy strings exactly as listed in Context.
- Do not change `Sources/OddFrogCore/`, `AppDelegate.swift`, `LinkManagerController.swift`,
  `SettingsSidebar.swift`, the General pane, or the launcher files.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build -c release` passes from the repo root.
- `swift test` passes from the repo root (109 tests, unchanged).
- `make run` → Settings… → Script Folders: intro card with a teal folder tile and the
  description, a "Folders" header, the list box with 44 pt rows and a + / − bar, and a separate
  box with the "Watch for changes" row and its switch. No "Watch for changes" control remains
  in the list's bottom bar.
- Adding, selecting, removing (button and Delete key) folders works; the `−` button is enabled
  only with a selection; the count column reads "1 script" / "N scripts"; the list scrolls once
  there are more than five folders.
- Items: the filter field spans the pane width above the box; the footer shows the alias helper
  sentence on the left and "Manage Links…" on the right; rows are 36 pt with 20 pt icons and
  13 pt text; selection, hover placeholder, checkbox toggling, alias editing (click, Return,
  Escape) and the empty-filter sentence behave as before.
- Resizing the window taller grows only the Items box; the Script Folders pane stays pinned to
  the top.

## Out of scope
- Sidebar, header, General pane (task 17). Column reordering, sorting, a custom table header
  view, folder path tail truncation, drag-and-drop of folders.
- Any change to `Settings` in Core or to `settings.toml`.

## Open questions
none
