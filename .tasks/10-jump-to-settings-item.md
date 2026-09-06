# Task: ⌘I reveals the selected row in Settings › Items; ⌘, opens Settings

Task 10 of the "user flow" series. Requires task 06 (`LauncherPanel.onKeyEquivalent` and
`LauncherViewController.handleKeyEquivalent`).

## Goal
From the launcher, ⌘I hides the panel and opens the Settings window with the Items filter set
to the selected item's title and that item's row selected, so an alias can be added in one
step. ⌘, hides the panel and opens Settings unchanged.

## Files
- Sources/OddFrog/LauncherViewController.swift    (modify — two key equivalents, `onReveal`, `onSettings`)
- Sources/OddFrog/AppDelegate.swift               (modify — wiring)
- Sources/OddFrog/SettingsWindowController.swift  (modify — `present(..., focusing:)`)
- README.md                                       (modify — Usage)

## Context
- Swift 6 strict concurrency, AppKit only, `@MainActor final class` for UI.
- `LauncherViewController.handleKeyEquivalent(_:)` (task 06) receives ⌘-only key downs and
  returns whether it consumed them. `event.charactersIgnoringModifiers` is `"i"` for ⌘I and
  `","` for ⌘,. `selectedItem` returns the selected `LauncherItem?`.
- `AppDelegate.showSettings()` calls
  `settingsWindow.present(settings:items:hotkey:)` with `allItems` (apps + config commands +
  scripts, before settings overrides) and the current hotkey. `hidePanel()` dismisses.
- `SettingsWindowController.present` seeds state, calls `applyFilter()`, activates the app,
  shows the window and makes `filterField` first responder. `applyFilter()` reads
  `filterField.stringValue`, computes `visibleItems` by case-insensitive `contains` on title,
  aliases and kind, reloads `itemTable`, and updates `selectedItemRow`. Items are identified
  by `LauncherItem.id`. `itemTable.selectRowIndexes` + `scrollRowToVisible` select a row;
  `tableViewSelectionDidChange` keeps `selectedItemRow` in sync and refreshes alias cells.
  `beginAliasEdit(row:)` starts alias editing in a row (also bound to Return in `ItemTable`).
- The Settings window is a normal window; the launcher panel is non-activating, so
  `NSApp.activate(ignoringOtherApps: true)` in `present` is what brings Settings forward.
- If task 09 has landed, `LauncherItem.quick` rows exist; they are not in `allItems` and must
  be ignored by ⌘I.

## Plan
1. `LauncherViewController` — add `var onReveal: ((LauncherItem) -> Void)?` and
   `var onSettings: (() -> Void)?`. In `handleKeyEquivalent`: `"i"` → if `selectedItem` is
   non-nil and not a `.quick` case (when that case exists), call `onReveal`, return true;
   `","` → `onSettings`, return true.
2. `SettingsWindowController` — add `func present(settings:items:hotkey:focusing id: String?)`
   and make the existing signature call it with `nil`. When `id` is non-nil: after seeding, set
   `filterField.stringValue` to the title of the item with that id (from `items`), run
   `applyFilter()`, select and scroll to the row whose `visibleItems[row].id == id`, make
   `itemTable` the first responder instead of `filterField`, and call `beginAliasEdit(row:)`
   so the alias cell is already editable. If the id is not found, behave like the plain
   `present`.
3. `AppDelegate.wirePanel` — `controller.onReveal = { [weak self] item in self?.hidePanel();
   self?.settingsWindow.present(settings:items:hotkey:focusing: item.id) }` using the same
   arguments `showSettings()` uses; `controller.onSettings = { hidePanel(); showSettings() }`.
4. `README.md` Usage: add `⌘I` (edit the selected item in Settings) and `⌘,` (Settings).

## Constraints
- No code comments of any kind.
- Swift 6 strict concurrency; UI stays `@MainActor`. No new dependencies.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes; `swift build -c release` succeeds.
- Manual after `make run`:
  1. ⌥Space, type `saf`, press ⌘I: the panel hides, Settings opens, the Items filter reads
     `Safari`, the Safari row is selected and its Aliases cell is in edit mode. Type `web`,
     press Return: the alias is saved (settings.toml gains an override) and `web` now finds
     Safari in the launcher.
  2. ⌥Space, ⌘, : Settings opens with the filter empty and focused.
  3. ⌘I with no rows (empty query, fresh install) does nothing and types nothing.

## Out of scope
- Editing aliases inside the launcher itself. Any Settings layout change.

## Open questions
none
