# Task: Launcher keyboard flow — selection reset on typing, argument entry on Return, Tab completion

Task 05 of the "user flow" series (05–11). Independent of the others; run it first because
06, 10 and 11 assume `refresh(keepSelection:)` from this task exists.

## Goal
Typing always re-targets the top match; arrow-key selection survives only background data
reloads. Pressing Return on a script that needs an argument puts the launcher into argument
entry instead of doing nothing. Tab completes the selected item's alias or title into the
search field.

## Files
- Sources/OddFrog/LauncherViewController.swift   (modify)
- Sources/OddFrog/AppDelegate.swift              (read — calls `controller.refresh()` with no arguments in `snapshotPanel`; must keep compiling unchanged)
- Sources/OddFrogCore/SearchEngine.swift         (read — `splits(of:allowArgument:)` shows how `"<head> <tail>"` becomes command + argument)
- Sources/OddFrogCore/Item.swift                 (read — `LauncherItem.aliases`, `acceptsArgument`, `ScriptItem.argument`)

## Context
- SwiftPM package, `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, Swift 6 strict
  concurrency. All UI classes are `@MainActor final class`. AppKit only, no SwiftUI, no nibs.
  Toolchain: Xcode 27 beta, macOS 27.
- `LauncherViewController.refresh()` (line ~173) captures `selectedItem?.id` before running
  `SearchEngine.search`, reloads the table, and then re-selects that id if it is still in
  `results`, else row 0. It is called from: `items` / `weights` / `maxResults` `didSet`,
  `viewDidLoad`, `prepareForShow`, `controlTextDidChange`, and `AppDelegate.snapshotPanel`
  (no arguments).
- `AppDelegate.showPanel` fires `refreshApps()`, `refreshScripts()`, `refreshWeights()` after
  presenting; each may set `controller.items` / `controller.weights` while the user is typing.
  That is the case where preserving the selection is right. Keystrokes are the case where it
  is wrong: arrow to row 3, type one more letter, Return launches row 3's item instead of the
  new top match.
- `submit()` (line ~209) returns early with no feedback when the selected item is a
  `.script` whose `argument` is non-optional and `result.argument == nil`. `ActionExecutor`
  would post "Needs an argument …" but is never reached.
- Keyboard handling lives in `control(_:textView:doCommandBy:)`: `moveDown:`, `moveUp:`,
  `insertNewline:`, `cancelOperation:`, `moveToBeginningOfDocument:`, `moveToEndOfDocument:`.
  Anything else returns `false`. `insertTab:` currently falls through, so Tab tries to move
  focus out of the only field.
- `SearchField` is an `NSTextField`; the field editor is `searchField.currentEditor()`
  (an `NSText`), whose `selectedRange` moves the caret.
- Query parsing: `SearchEngine.search` trims the query; for items with `acceptsArgument`,
  `splits` tries the whole query first, then every `"<head> <tail>"` split from the right.
  So a field containing `"kp "` matches alias `kp` exactly with no argument, and `"kp 3000"`
  matches with argument `"3000"`.
- Tests: `swift test` runs 56 Swift Testing tests in `Tests/OddFrogCoreTests` (Core only;
  the UI target has no tests). `make test` is an alias for `swift test`.

## Plan
1. `LauncherViewController.swift` — change `refresh()` to `refresh(keepSelection: Bool = false)`.
   When `keepSelection` is false, always select row 0 after reload. When true, keep the
   current behaviour (re-select the previous id if present, else row 0). Pass `true` from the
   `items`, `weights` and `maxResults` `didSet`s; leave every other call site on the default.
   `AppDelegate.snapshotPanel` keeps compiling because of the default.
2. Add `private func completion(for item: LauncherItem) -> String` returning the item's first
   alias if it has one, otherwise its title, with a trailing space appended when
   `item.acceptsArgument` is true.
3. Add `private func fill(with item: LauncherItem)`: set `searchField.stringValue` to
   `completion(for:)`, move the field editor's `selectedRange` to the end of the text
   (`NSRange(location: length, length: 0)`), then call `refresh(keepSelection: true)` so the
   filled item stays selected.
4. In `submit()`, replace the early `return` for a script with a missing required argument by
   `fill(with: result.item)` and return. The row then shows the existing "Required" chip and
   the user types the value.
5. In `control(_:textView:doCommandBy:)` add `insertTab:` → `fill(with:)` the selected item
   (no-op when there is no selection) and return `true`; add `insertBacktab:` → return
   `true` without doing anything, so Shift-Tab cannot move focus out of the field.
6. `README.md`, Usage section: after the `↑`/`↓`/`↩`/`⎋` sentence add that `⇥` completes the
   selected item and that Return on a command that needs an argument fills the command in so
   you can type the value.

## Constraints
- Write no code comments of any kind (no doc comments, no inline notes, no TODOs).
- Swift 6 strict concurrency; keep everything in this file `@MainActor`. No new dependencies.
- One component per file; do not add types outside `LauncherViewController.swift`.
- Surgical changes only; do not touch anything outside Files without saying why.
- Do not change `SearchEngine` or `ActionExecutor` behaviour.

## Acceptance
- `swift test` passes (from the repo root; 56 tests today, none may break).
- `swift build -c release` succeeds.
- Manual, after `make run` (builds, bundles to `build/OddFrog.app`, relaunches):
  1. Press ⌥Space, type `s`, press ↓ twice, type another letter. The selection is on row 0.
  2. With a script folder containing a `@raycast.argument1` script (for example the "Kill
     Port" header in `Tests/OddFrogCoreTests/ScriptTests.swift`), type its name and press ↩.
     The field now reads `<alias or title> ` with the caret at the end and the row stays
     selected showing the "Required" chip. Type `3000`, press ↩: the script runs with `3000`.
  3. Type `saf`, press ⇥: the field reads `Safari` and Safari is selected. Press ⇧⇥: nothing
     happens and the field keeps focus.
  4. Open the panel and wait a minute so the background rescan runs while a row other than 0
     is selected: the selection does not jump.

## Out of scope
- ⌘-modified shortcuts (task 06). Escape behaviour stays "hide immediately".
- Any change to ranking or to the "No results" state (task 09).

## Open questions
none
