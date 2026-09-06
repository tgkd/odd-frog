# Task: Result rows — tinted selection, hover, icon tiles, argument chips, subtitle rules

Task 2 of 4 for the "Odd Frog" design. Requires task 1 (`01-launcher-panel-glass-layout.md`)
to be merged first: it changes `LauncherViewController.loadView()` and the list insets this task
builds on.

## Goal
Result rows match the design: 10 pt rounded rows inside the 8 pt list inset, accent-tinted
selection with white text, a faint hover fill, 14 pt regular titles, icon tiles for
commands/scripts without their own image, `Required` / `Optional` outline chips for script
arguments, and subtitles only where they add information (folder and URL targets, script package,
duplicate-name location as parent directory). Pressing Return on a script whose required
argument is missing does nothing and keeps the panel open.

## Files
- Sources/OddFrog/ResultRowView.swift              (modify)
- Sources/OddFrog/ResultRow.swift                  (create — `NSTableRowView` subclass drawing selection/hover)
- Sources/OddFrog/IconCache.swift                  (modify)
- Sources/OddFrog/LauncherViewController.swift     (modify — row view delegate, `detail(for:)`, `submit()`)
- Sources/OddFrogCore/Item.swift                   (modify — `subtitle`, `subtitles(for:)`)
- Tests/OddFrogCoreTests/ScriptTests.swift         (modify — the `subtitlesOnlyForCollisionsAndInformativeMetadata` test)

## Context
- Package facts: SwiftPM, Swift 6 strict concurrency, macOS 14 deployment target, AppKit only,
  `@MainActor final class` UI types. Tests use Swift Testing (`import Testing`, `@Test`,
  `#expect`), run with `swift test`.
- `ResultRowView: NSTableCellView` lays out `iconView` (24×24 at leading 12), `textBlock`
  (title 14 medium; subtitle 11 secondary + value 11 label on one line, middle-truncated), and
  `kindLabel` (11 tertiary, trailing 14). `configure(title:detail:value:tooltip:kind:icon:)`
  switches between one-line and two-line constraint sets. Row heights: `singleLineHeight = 36`,
  `twoLineHeight = 40`.
- `LauncherViewController.detail(for:)` produces a `DetailLine(detail:value:tooltip:)`:
  - script with argument and a typed value → `detail` = `"<placeholder>:"` (or `"Argument:"`
    when the placeholder is the generic word `argument` or longer than 24 chars, with the full
    placeholder as tooltip), `value` = the typed value;
  - script with argument and no value → `detail` = `"<placeholder>: required"` or `"… optional"`;
  - otherwise the precomputed subtitle from `LauncherItem.subtitles(for:)`.
- `LauncherItem.subtitle` today: apps `nil`; commands `"$ <text>"` for shell, abbreviated path
  for `.path`, `absoluteString` for `.url`; scripts the package name when it differs from the
  title. `subtitles(for:)` adds, for apps whose lower-cased title collides with another item,
  `abbreviate(parentDir) + "/" + bundleName` (e.g. `/Applications/Xcode.app`). The test at
  `Tests/OddFrogCoreTests/ScriptTests.swift:97` pins these values.
- `IconCache.icon(for:)`: apps → `NSWorkspace.shared.icon(forFile:)` loaded off-main and cached
  (24×24); commands → SF Symbols `terminal` / `chevron.left.forwardslash.chevron.right` /
  `folder` / `globe` at 16 pt; scripts → emoji rendered at 18 pt into 24×24, else SF `scroll`.
  `SettingsWindowController` calls `icons.icon(for: item)` and displays it at 20×20.
- `ActionExecutor.runScript` already refuses to run a script whose required argument is `nil`
  and posts a notification. `LauncherViewController.submit()` calls `onSubmit`, and
  `AppDelegate` hides the panel before calling the executor, so today Return on such a row closes
  the panel and shows a notification.
- `NSTableView` in the controller: `selectionHighlightStyle = .regular`, `style = .plain` after
  task 1, `refusesFirstResponder = true`, `intercellSpacing = 0`, backgrounds clear. The table
  never becomes first responder; keyboard focus lives in the search field.
- Design values (points; colours are AppKit semantic colours):

  | element | value |
  |---|---|
  | row corner radius | 10 |
  | row horizontal padding | 8 (icon starts 8 in from the row edge) |
  | icon | 24×24, tile corner 6, icon-to-text gap 10 |
  | title | 14 regular, `labelColor`; selected → white |
  | secondary text | 11 regular, `secondaryLabelColor`; selected → white at 80 % |
  | argument value | 11 **medium**, `labelColor`; selected → white; middle truncation |
  | kind label | 11, `tertiaryLabelColor`; selected → white at 72 %; trailing 8 from row edge |
  | chips `Required` / `Optional` | 10 pt medium (Required) / regular (Optional), 5 pt side padding, 12 pt line, radius 4, 0.5 pt border solid (Required) or dashed (Optional); colour = tertiaryLabel normally, white at 75 % when selected |
  | selection fill | `controlAccentColor`, radius 10, no ring |
  | hover fill | `quaternaryLabelColor` at rest opacity (design token `--mac-row-alt`, ≈ 3–4 % label); never on the selected row; no text colour change |
  | emoji icons | glyph at 20 pt centred in a 24 tile, no background |
  | script without emoji | grey tile (`systemGray`) with `>_` in 10 pt bold monospaced white |
  | shell / terminal command | dark tile (`NSColor(white: 0.16, alpha: 1)`) with `$` in 13 pt bold monospaced white |
  | URL command | `systemTeal` tile with SF Symbol `link` 14 pt white |
  | folder (path) command | `systemBlue` tile with SF Symbol `folder.fill` 12 pt white |

  Subtitle rules: apps none, except when two visible items share a title (case-insensitive),
  then the parent directory only (`/Applications`, `~/Applications`). Shell and terminal commands
  none. Folder commands: abbreviated path. URL commands: host + path without scheme and without a
  trailing slash (`developer.apple.com/documentation`). Scripts: package name when it differs from
  the title. Script argument rows: descriptor + value, or descriptor + chip when no value.
- Selection style decision: **tinted** (accent). The neutral/Return-badge variant is not built.

## Plan
1. `Sources/OddFrogCore/Item.swift`
   - `subtitle`: return `nil` for `.shell`; for `.url` return `host + path` with the scheme
     dropped, a trailing `/` removed, and `www.` left as is; keep `.path` and script behaviour.
   - `subtitles(for:)`: for colliding app titles use `abbreviate(app.url.deletingLastPathComponent().path)`
     only (no bundle name).
   - Update `Tests/OddFrogCoreTests/ScriptTests.swift` expectations: xcode → `/Applications`,
     xcodeHome → `~/Applications`, and if the fixture's `ssh` is a shell command its subtitle is
     still `nil`. Add one expectation for a `.url` command that
     `https://developer.apple.com/documentation/` yields `developer.apple.com/documentation`.
2. `Sources/OddFrog/IconCache.swift`
   - Change the API to `icon(for item: LauncherItem, size: CGFloat = 24) -> NSImage?` with cache
     keys including the size. The default argument keeps every existing call site compiling.
     Keep the async app-icon path (`onLoaded`) and `prewarm`.
   - Add a private tile renderer: `NSImage(size:flipped:)` drawing a rounded rect (radius
     `size / 4`, i.e. 6 at 24 and 4 at 16) in the tile colour, then either an attributed string
     (monospaced bold, white) or an SF Symbol (`withSymbolConfiguration(pointSize:weight:)`,
     tinted white via `NSImage.SymbolConfiguration(paletteColors:)`) centred. Glyph and symbol
     point sizes scale with `size / 24`.
   - Map: `.command` shell (terminal or not) → `$` tile; `.path` → `folder.fill` tile; `.url` →
     `link` tile; `.script` with emoji → emoji glyph at `size * 20 / 24` with no tile; `.script`
     without emoji → `>_` tile.
3. Call sites: `LauncherViewController` passes `size: 24`. Do not edit
   `SettingsWindowController.swift`; the default argument keeps its existing call compiling, and
   task 4 switches it to `size: 16`.
4. `Sources/OddFrog/ResultRow.swift` (new): `final class ResultRow: NSTableRowView`.
   - `isHovered` property that calls `needsDisplay = true` on change; an `NSTrackingArea`
     (`.mouseEnteredAndExited, .activeAlways, .inVisibleRect`) installed in
     `updateTrackingAreas()`; `mouseEntered`/`mouseExited` toggle `isHovered`.
   - Override `drawSelection(in:)`: when `isSelected`, fill `bounds` with `controlAccentColor`
     using a 10 pt rounded path. Override `drawBackground(in:)`: when hovered and not selected,
     fill the same path with `quaternaryLabelColor`. `isEmphasized` must be treated as true
     (override `isEmphasized` to return `true`) because the table never has key focus.
   - Return `interiorBackgroundStyle == .emphasized` when selected so the cell can recolour.
5. `Sources/OddFrog/ResultRowView.swift`
   - Title font → 14 regular. Leading of `iconView` → 8; `kindLabel` trailing → −8.
   - Add a `chipLabel` (`NSTextField` label, 10 pt, layer border 0.5 pt, radius 4, padding 5,
     `wantsLayer`) placed after `subtitleLabel` on the second line, hidden by default. Dashed
     border for Optional: use a `CAShapeLayer` with `lineDashPattern = [2, 2]` as the border
     layer instead of `layer.borderWidth`; solid for Required uses `borderWidth = 0.5`.
   - `configure(...)` grows a `chip: Chip?` parameter (`enum Chip { case required, optional }`)
     and applies text `Required` / `Optional`, weight medium / regular, and border style.
   - Override `backgroundStyle` `didSet`: `.emphasized` → title white, subtitle white 80 %,
     value white, kind white 72 %, chip white 75 %; otherwise the rest colours above.
   - `valueLabel.font` → 11 **medium**.
6. `Sources/OddFrog/LauncherViewController.swift`
   - Implement `tableView(_:rowViewForRow:)` returning a reused/created `ResultRow`.
   - Set `tableView.selectionHighlightStyle = .none` (the row view draws selection) and keep
     `.regular` semantics via `ResultRow` as above.
   - `detail(for:)`: for a script argument with no value return `detail = placeholder` (or
     `Argument` for the generic/long case, tooltip = full placeholder) and `chip = .required` or
     `.optional`; drop the `": required"` / `": optional"` text.
   - `submit()`: if the selected result is a `.script` whose `argument` is non-nil and
     non-optional and `result.argument == nil`, return without calling `onSubmit`.
   - Selection change on mouse-down: `rowClicked` already selects then submits; keep.
7. Manual check via the snapshot hook (`~/Library/Logs/odd-frog-query.txt` + `pkill -USR2 -x
   OddFrog` → `~/Library/Logs/odd-frog-panel.png`): queries `de` (mixed kinds), `dev` (required
   chip on a script with `@raycast.argument1`), `dev 3000` (value), `vis` (duplicate names), and
   an empty query.

## Constraints
- No comments in source, ever.
- Swift 6 strict concurrency; `@MainActor` UI; `[weak self]` in stored closures.
- Semantic AppKit colours only: `controlAccentColor`, `labelColor`, `secondaryLabelColor`,
  `tertiaryLabelColor`, `quaternaryLabelColor`, `systemGray`, `systemTeal`, `systemBlue`,
  `white`. The single non-semantic colour allowed is the dark shell tile
  `NSColor(white: 0.16, alpha: 1)`.
- No new dependencies. No SwiftUI. Tests only in `Tests/OddFrogCoreTests` for Core changes; do
  not add UI tests.
- Keep `RankedItem`, `SearchEngine`, `ActionExecutor` untouched (the executor's own
  required-argument guard stays as a second line of defence).

## Acceptance
- `swift build -c release` passes.
- `swift test` passes, including the updated `subtitlesOnlyForCollisionsAndInformativeMetadata`
  test and the new URL-subtitle expectation.
- `make run`; `⌥Space`; type a query that hits an app, a shell command, a folder command, a URL
  command and a script: the selected row is a solid accent rounded rectangle with white text;
  non-app rows show a tertiary kind label at the trailing edge; the shell row has no subtitle;
  the URL row's subtitle has no `https://`; the script without an emoji shows a grey `>_` tile.
- Hovering an unselected row shows a faint fill that disappears on exit; hovering the selected
  row changes nothing.
- For a script declaring a required argument, typing only its name shows a `Required` solid
  outline chip and pressing Return leaves the panel open and runs nothing; typing `name value`
  shows `<placeholder>:` followed by the value in medium weight and Return runs it.
- Two apps with the same name show `/Applications` and `~/Applications` (parent directory only).

## Out of scope
- Panel material, insets, animation (task 1). The Settings window entirely (tasks 3 and 4),
  including its icon call site.
- Neutral selection style and the Return badge.
- Match-character highlighting, footers, section headers.

## Open questions
none
