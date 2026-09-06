# Task: Settings Items table — alias cell states, row styling, hover

Task 4 of 4 for the "Odd Frog" design. Requires task 3 (`03-settings-layout-general-folders.md`)
merged: the table lives inside the grouped box with fixed/proportional columns from that task.
Uses `IconCache.icon(for:size:)` from task 2; if task 2 is not merged, keep `icon(for:)` and
size the image view to 16 anyway.

## Goal
Each Items row shows a 16 pt icon (45 % opacity when the item is disabled), the name in
`labelColor` (tertiary when disabled), the kind in 12 pt secondary, and an alias cell that
renders built-in aliases in tertiary grey followed by custom aliases in label colour. Hovering a
row without custom aliases shows an `Add alias` placeholder on a faint fill; clicking the cell or
pressing Return on the selected row opens an inline editor holding only the custom aliases; Return
saves, Escape restores. Selected rows are accent-filled with white text.

## Files
- Sources/OddFrog/SettingsWindowController.swift  (modify — `itemTable` delegate/data-source methods and cell construction)
- Sources/OddFrog/AliasCellView.swift              (create — `NSTableCellView` subclass with display and edit modes)
- Sources/OddFrog/HoverRowView.swift               (create — `NSTableRowView` with hover flag and accent selection)
- Sources/OddFrog/IconCache.swift                  (read — `icon(for:size:)`)
- Sources/OddFrogCore/Settings.swift               (read — `ItemOverride(id:enabled:aliases:)`, `override(for:)`, `setOverride`; `isDefault` drops empty overrides)
- Sources/OddFrogCore/Item.swift                   (read — `LauncherItem.aliases` are the built-ins for apps/commands/scripts; overrides are merged by `Settings.apply`)

## Context
- Package: SwiftPM, Swift 6 strict concurrency, macOS 14 deployment target, AppKit only,
  `@MainActor final class`. Build `swift build -c release`; tests `swift test`.
- Today `SettingsWindowController.tableView(_:viewFor:row:)` builds four cells by column id
  (`enabled`, `name`, `kind`, `aliases`): a checkbox with `tag = row` → `toggleEnabled(_:)`; a
  name cell with an image view (20 pt) and label whose colour is `tertiaryLabelColor` when the
  override disables the item; a kind label in `secondaryLabelColor` (`item.kindLabel ?? "App"`);
  and an always-editable borderless `NSTextField` for aliases whose `stringValue` is the custom
  aliases joined by `", "`, with placeholder `built-in: a, b`, committing in
  `controlTextDidEndEditing` (split on `,`, trim, lowercase, drop empties → `ItemOverride.aliases`
  → `settings.setOverride` → `commit()` → `onChange`). `visibleItems` is the filtered list;
  `allItems` the full one. `applyFilter()` matches title, aliases and kind.
- `LauncherItem.aliases` are the built-in aliases (from config for commands, none for apps,
  Raycast headers for scripts). Custom aliases live only in `Settings.items[].aliases`. The
  launcher merges both via `Settings.apply(to:)`; nothing here needs to change in Core.
- After task 3 the table has `rowHeight 28`, no alternating rows, transparent background,
  `selectionHighlightStyle` default, columns enabled 30 / name 2fr / kind 68 / aliases 1.6fr.
- Design values (points):

  | element | value |
  |---|---|
  | row | 28 tall, radius 6, 2 pt side padding inside the 4 pt table padding |
  | selected row | `controlAccentColor` fill, all text white; built-in aliases white 70 %; kind white 80 % |
  | hovered row | faint fill `quaternaryLabelColor` (design `--mac-row-alt`), no text change |
  | icon | 16×16, `alphaValue 0.45` when disabled |
  | name | 13 pt `labelColor`; `tertiaryLabelColor` when disabled |
  | kind | 12 pt `secondaryLabelColor`; `App` for apps |
  | alias cell (display) | height 20, radius 5, 6 pt side padding, 12 pt text: built-ins joined by `, ` in `tertiaryLabelColor`, then a trailing `,` when custom aliases exist or the row is hovered; custom aliases joined by `, ` in `labelColor`; both tail-truncated |
  | alias placeholder | `Add alias` in `tertiaryLabelColor` on a `labelColor` 5 % fill, only when hovered or selected and no custom aliases |
  | alias cell (editing) | `NSTextField` 12 pt, `textBackgroundColor` fill, radius 5, standard focus ring (accent), contains only the custom aliases; Return commits, Escape restores the previous value and closes; clicking elsewhere commits |

## Plan
1. `Sources/OddFrog/HoverRowView.swift` (new): `final class HoverRowView: NSTableRowView` with
   `isHovered` toggled by an `NSTrackingArea` (`.mouseEnteredAndExited, .activeAlways,
   .inVisibleRect`), `onHoverChange: ((Bool) -> Void)?` so the cell can redraw the placeholder,
   `drawSelection(in:)` filling a 6 pt rounded rect with `controlAccentColor` (override
   `isEmphasized` → `true`), `drawBackground(in:)` filling `quaternaryLabelColor` when hovered
   and not selected. Reuse for the folder table from task 3 if that one was implemented as a
   separate class; otherwise leave task 3's class alone.
2. `Sources/OddFrog/AliasCellView.swift` (new): `final class AliasCellView: NSTableCellView`.
   - Display mode: a rounded container (radius 5, height 20) with two labels: `builtinLabel`
     (tertiary) and `customLabel` (label colour); `configure(builtin: [String], custom:
     [String], hovered: Bool, selected: Bool)` computes the strings per the table above and the
     placeholder state.
   - Edit mode: a single `NSTextField` (12 pt, `isBordered = false`, `drawsBackground = true`,
     `backgroundColor = textBackgroundColor`, `focusRingType = .exterior`, layer radius 5),
     `stringValue` = custom aliases joined by `", "`. `beginEditing()` swaps to the field and
     makes it first responder with the caret at the end; `endEditing(commit: Bool)` reads the
     field when committing, restores the display, and calls `onCommit([String])` with the
     normalised list (split on `,`, trim whitespace, lowercase, drop empties).
   - Escape: implement `control(_:textView:doCommandBy:)` for `cancelOperation(_:)` →
     `endEditing(commit: false)`; `insertNewline(_:)` → `endEditing(commit: true)`. Field
     `controlTextDidEndEditing` (focus loss) → commit.
   - `backgroundStyle` `didSet`: `.emphasized` → white text (built-ins at 70 %), else the
     colours above.
3. `SettingsWindowController.swift`
   - `tableView(_:rowViewForRow:)` for `itemTable` returns `HoverRowView`; its `onHoverChange`
     asks the table to redisplay that row's alias cell (`tableView.view(atColumn:row:makeIfNecessary:false)`
     cast to `AliasCellView` → `configure` again with the new `hovered`).
   - Name cell: image view 16×16 using `icons.icon(for: item, size: 16)`, `alphaValue` 0.45 when
     disabled; label colour as today.
   - Kind cell: font 12 pt.
   - Aliases column: return an `AliasCellView` configured from `item.aliases` (built-in) and
     `settings.override(for: item.id)?.aliases ?? []` (custom), `hovered` from the row view,
     `selected` from `itemTable.selectedRow == row`. `onCommit` builds the `ItemOverride` and
     commits exactly as `controlTextDidEndEditing` does today; then remove that method's alias
     branch and the `Column.aliases` field-delegate wiring.
   - Open the editor on a single click in the alias column (`tableView.action` → check
     `clickedColumn` is the aliases column → `beginEditing()` on that cell) and on Return while
     the table has focus and a row is selected (`keyDown` on the table, key code 36 → same).
     Because the table now handles Return, make sure the filter field keeps its own Return.
   - Selection change reconfigures alias cells of the previously and newly selected rows so
     the placeholder follows selection.
   - Filter changes must end any open editor without committing before `reloadData()`.
4. Manual check: `make run` → Settings…; hover a row without custom aliases (`Add alias`
   appears, with the built-ins now ending in a comma); click it, type `vsc, vscode`, Return (row
   shows `code, vsc, vscode` with `code,` in grey); relaunch the app and confirm the aliases
   persist in `~/.config/odd-frog/settings.toml` and in the launcher (`vsc` opens the app);
   start an edit, type garbage, press Escape (previous value restored); disable an item with the
   checkbox (name goes tertiary, icon fades).

## Constraints
- No comments in source.
- Swift 6 strict concurrency; `@MainActor`; `[weak self]` in stored closures.
- Semantic AppKit colours only (`controlAccentColor`, `labelColor` + secondary/tertiary/
  quaternary, `textBackgroundColor`, `white`).
- Keep the alias normalisation identical to today's (split `,`, trim, lowercase, drop empties);
  `Settings.setOverride` already drops overrides that end up default.
- Do not touch `Sources/OddFrogCore/`, the launcher files, or the General/Folders groups from
  task 3 beyond sharing `HoverRowView`.

## Acceptance
- `swift build -c release` passes.
- `swift test` passes.
- In Settings, a row with built-in `code` and no custom aliases shows `code` in grey; on hover it
  shows `code,` plus `Add alias` on a faint fill; clicking opens an editor that contains nothing
  (built-ins are not editable); typing `vsc` and pressing Return shows `code, vsc` with `vsc` in
  label colour; `~/.config/odd-frog/settings.toml` gains `[[items]]` with `aliases = ["vsc"]`.
- Escape during editing restores the previous aliases and writes nothing.
- The selected row is an accent rounded rectangle with white text; hovering another row shows a
  faint fill only.
- Disabled items show the name in tertiary colour and the icon at 45 % opacity.

## Out of scope
- Column layout, group boxes, General and Folders groups (task 3).
- Launcher (tasks 1–2).
- Editing built-in aliases (they come from config/Raycast headers and stay read-only).

## Open questions
none
