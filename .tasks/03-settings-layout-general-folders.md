# Task: Settings window — grouped layout, General group, Script Folders group

Task 3 of 4 for the "Odd Frog" design. Independent of tasks 1–2 except for the
`icons.icon(for:size:)` signature introduced in task 2 (if task 2 is not merged yet, keep calling
`icons.icon(for:)`). Task 4 (Items table) builds on this one.

## Goal
The Settings window becomes one scrolling-free window of three grouped boxes on the standard
window background: **General** (Shortcut recorder with recording/conflict states, Launch at login
switch with four states), **Script Folders** (list with per-folder script counts, bottom bar with
+ / − and a "Watch for changes" switch, empty placeholder, Delete-key removal, three-row cap), and
the **Items** group container (header line, helper sentence, filter field, table frame) which
takes all remaining height. Default size 680 × 640, minimum 560 × 420, with the label column and
paddings tightening at the minimum. The Items table's cells keep today's behaviour; task 4
restyles them.

## Files
- Sources/OddFrog/SettingsWindowController.swift  (modify — most of the file)
- Sources/OddFrog/HotkeyRecorder.swift             (modify)
- Sources/OddFrog/GroupBox.swift                   (create — rounded grouped container view)
- Sources/OddFrog/LoginItem.swift                  (read — `status`, `toggle()`; unchanged)
- Sources/OddFrog/AppDelegate.swift                (read — `showSettings`, `settingsWindow.onChange/onHotkey`, `setHotkey`; unchanged)
- Sources/OddFrogCore/Settings.swift               (read — `Settings.scripts.folders: [String]` with `~` paths, `scriptFolders: [URL]`, `override(for:)`, `setOverride`)
- Sources/OddFrogCore/Item.swift                   (read — `LauncherItem.script(ScriptItem)` with `url`)

## Context
- Package: SwiftPM, Swift 6 strict concurrency, macOS 14 deployment target, AppKit only,
  `@MainActor final class`. Build `swift build -c release`; tests `swift test` (Swift Testing);
  `make run` bundles and relaunches `build/OddFrog.app`.
- `SettingsWindowController` today: an `NSWindow` 680 × 560 (min 560 × 420), one vertical
  `NSStackView` with: "Hotkey" bold label → `HotkeyRecorder` (160 × 24) + note → login checkbox
  + note → "Script folders" label + hint → `folderTable` in a bezel scroll (60 tall) → Add… /
  Remove / "Watch folders for changes" checkbox → "Items" label + `NSSearchField` filter →
  `itemTable` in a bezel scroll. It exposes `present(settings:items:hotkey:)`,
  `update(items:)`, `refreshLogin()`, `showHotkey(_:note:)`, and callbacks
  `onChange: (Settings) -> Void`, `onHotkey: (Hotkey) -> Void`.
- `AppDelegate.setHotkey` applies the recorded hotkey; on failure it calls
  `settingsWindow.showHotkey(current, note: "\(error)")` where the error text is
  `"<⌘Q> is taken by another app"` or `"could not register <⌘Q> (code N)"`. On success it calls
  `showHotkey(hotkey)` with no note. There is no "no hotkey" state; a hotkey is always set.
- `HotkeyRecorder: NSControl` draws itself: rounded 6 pt rect, `controlBackgroundColor` (or accent
  15 % while recording), `separatorColor` stroke, centred text `hotkey.description`
  (e.g. `⌥Space`) or `Press keys… (Esc cancels)`; Esc cancels; a chord without modifiers beeps;
  `onRecord(Hotkey)` fires on a valid chord. It has a custom focus ring mask.
- `LoginItem.status` is `SMAppService.Status`: `.enabled`, `.requiresApproval`, `.notFound`
  (app not in an Applications folder), `.notRegistered`. `LoginItem.toggle()` unregisters when
  enabled, opens System Settings › Login Items when `.requiresApproval`, registers otherwise.
- Script counts per folder can be derived from the `items` passed to `present`/`update`: for
  each `LauncherItem.script(s)`, `s.url.path` has the prefix of the folder's expanded path
  (`Settings.scriptFolders` gives expanded `URL`s in the same order as `scripts.folders`).
- Design values (points):

  | element | 680 × 640 | 560 × 420 |
  |---|---|---|
  | window content padding | 20 (top 4 below the title bar) | 16 |
  | gap between groups | 18 | 14 |
  | group title | 13 semibold, 2 pt leading inset, 7 below it | same |
  | group box | `controlBackgroundColor`, radius 10, 0.5 pt `separatorColor` border | same |
  | form row | min height 32, label column 120 right-aligned 13 pt ending in `:`, 12 gap, 14 side padding, hairline between rows inset 14 | label column 110, rows 34 |
  | shortcut control | 22 tall, radius 8 (system control radius), `controlColor` fill, control shadow; text 13; min text width 64 | same |
  | login row | `NSSwitch` + 11 pt secondary status; `Open Login Items…` small push button when awaiting approval | same |
  | folder list rows | 28 tall, radius 6, 4 pt list padding, `folder.fill` symbol in `systemTeal` 16 pt, path 13 pt middle-truncated, count `N scripts` 11 pt tertiary at trailing; selected → accent fill, white text, white symbol | 26 tall |
  | folder list height | `4 + 28 × clamp(count, 1, 3) + 4`; scrolls beyond 3 | same with 26 |
  | folder bottom bar | 32 tall, `NSColor.quaternaryLabelColor`-ish fill (design `--mac-fill` ≈ 5 % label → use `NSColor.labelColor.withAlphaComponent(0.05)`), 0.5 pt top hairline, `+` and `−` small push buttons 26 wide at 4 pt leading, `Watch for changes` label + `NSSwitch` at trailing 6 | 30 tall |
  | folder helper | 11 pt secondary, 2 pt leading inset: `Executable scripts in these folders appear in the launcher. Raycast script metadata is optional.` | wraps |
  | folder empty | `No script folders yet. Click + to add one.` 13 pt secondary centred in the list body | same |
  | items header | `Items` 13 semibold + helper `Grey aliases are built in. Click a cell to add your own; Return saves.` 11 pt secondary, tail-truncated; `NSSearchField` small, 200 wide, placeholder `Filter` at trailing | helper hidden, search 160 wide |
  | items table frame | grouped box as above, header row + body; the box takes all remaining height, never less than 150 | ≥ 130 |

  State copy (exact strings):
  - Shortcut normal: helper `Click, then press a new combination.` (11 pt secondary)
  - Shortcut recording: field text `Type shortcut…` in tertiary; helper `Press the keys you want to use.`; accent focus ring
  - Shortcut conflict: field shows the rejected chord; ring `systemRed`; helper = error description + ` Try another combination.` in `systemRed`; the previous hotkey stays active (AppDelegate already guarantees this)
  - Login enabled: switch on; status `Odd Frog opens when you log in.`
  - Login disabled (`.notRegistered`): switch off; no status
  - Login unavailable (`.notFound`): switch off and disabled; status `Move Odd Frog to your Applications folder to enable this.`
  - Login awaiting approval (`.requiresApproval`): switch on; status `Waiting for approval in System Settings › Login Items.` in `systemOrange`; small push button `Open Login Items…` that calls `SMAppService.openSystemSettingsLoginItems()`

## Plan
1. `Sources/OddFrog/GroupBox.swift` (new): `final class GroupBox: NSView` with `wantsLayer`,
   `layer.cornerRadius = 10`, `backgroundColor = controlBackgroundColor`, `borderWidth = 0.5`,
   `borderColor = separatorColor`; override `viewDidChangeEffectiveAppearance` to reapply the
   colours (layer colours do not track appearance changes automatically). Expose a `content`
   stack or let callers add subviews with Auto Layout.
2. `Sources/OddFrog/HotkeyRecorder.swift`
   - Height 22, width 120 (intrinsic), radius 8. Fill `controlColor`; stroke `separatorColor`;
     when recording, draw the standard focus ring (keep `drawFocusRingMask`, and ensure
     `focusRingType = .exterior`) and show `Type shortcut…` in `tertiaryLabelColor`.
   - Add `var conflict = false { didSet { needsDisplay = true } }`; when true, stroke
     `systemRed` at 1 pt instead of `separatorColor`. `conflict` resets to false when recording
     starts.
   - Delete/Backspace while recording cancels (same as Escape). Do not add a clear button.
   - Text is left-aligned with 10 pt padding (the design's field), not centred.
3. `Sources/OddFrog/SettingsWindowController.swift` — rebuild `buildContent()` and the folder
   table; keep the public API and the items-table cell code as it is.
   - Window: default `680 × 640`, `minSize 560 × 420`, `title` unchanged, `contentView`
     background `windowBackgroundColor`. Make the controller the window's `NSWindowDelegate` and
     implement `windowDidResize` to switch compact metrics (label column 110, padding 16, gaps
     14, folder rows 26, helper hidden, search 160) when `window.frame.width < 600`.
   - Root: vertical `NSStackView` pinned to the content view with the padding above; three
     children: General group, Folders group, Items group; the Items group has
     `setContentHuggingPriority(.defaultLow, for: .vertical)` and a `≥ 150` height constraint so
     it absorbs the remaining height.
   - **General group**: title label `General`; a `GroupBox` with two form rows separated by a
     0.5 pt hairline inset 14. Row 1 label `Shortcut:`, control = `HotkeyRecorder` + helper
     label. Row 2 label `Launch at login:`, control = `NSSwitch` + status label + optional push
     button (hidden unless `.requiresApproval`). Each label column is a fixed-width constraint
     that `windowDidResize` updates.
   - `showHotkey(_:note:)`: `note == nil` → normal state (helper text, `conflict = false`);
     `note != nil` → `conflict = true`, helper = `note + " Try another combination."` in
     `systemRed`. The recorder calls a new `onRecordingChanged: (Bool) -> Void` so the controller
     can swap the helper to `Press the keys you want to use.` during recording.
   - `refreshLogin()`: map the four `SMAppService.Status` cases to the switch state, enabled
     flag, status text/colour and button visibility as listed in Context. The switch action calls
     `LoginItem.toggle()` then `refreshLogin()` (keep the existing 0.3 s re-check).
   - **Script Folders group**: title `Script Folders`; `GroupBox` containing a `NSScrollView`
     (no bezel, transparent) with `folderTable` (rows 28, `intercellSpacing 0`,
     `selectionHighlightStyle = .none`, a custom `NSTableRowView` drawing an accent rounded 6 pt
     selection) and a bottom bar view. Cell: `folder.fill` symbol image view 16 pt tinted
     `systemTeal` (white when selected via `backgroundStyle`), path label 13 pt
     `byTruncatingMiddle`, count label 11 pt tertiary right-aligned. Empty placeholder label
     centred, shown when `settings.scripts.folders.isEmpty`.
     List height constraint = `8 + rowHeight × max(1, min(count, 3))`, updated in
     `reloadFolders()`.
     Bottom bar: `+` (`NSButton(title: "+")`, `bezelStyle = .rounded`, `controlSize = .small`,
     width 26) → `addFolder()`; `−` same style → `removeFolder()`, enabled only with a selection;
     spacer; `Watch for changes` label 13 pt + `NSSwitch` → `toggleWatch()`.
     Helper label under the box with the exact sentence from Context.
     Delete key: subclass `NSTableView` as `FolderTable` overriding `keyDown` for key codes 51
     and 117 to call a `onDelete` closure → `removeFolder()`; other keys go to `super`.
     Script counts: compute `[Int]` parallel to `settings.scripts.folders` from `allItems`
     (`.script` whose `url.path` has the prefix `settings.scriptFolders[i].path + "/"`); recompute
     in `present`, `update(items:)` and `reloadFolders()`.
   - **Items group**: header row = `Items` 13 semibold, helper label (11 pt secondary, tail
     truncation, hidden in compact mode), spacer, `filterField` (`NSSearchField`, `controlSize =
     .small`, width 200 / 160). Below: a `GroupBox` wrapping the existing `itemTable` scroll view
     (drop `borderType = .bezelBorder`, transparent background, `rowHeight 28`,
     `usesAlternatingRowBackgroundColors = false`). Keep the current column identifiers and the
     current cell code; set column widths: enabled 30 (fixed), kind 68 (fixed), and split the
     rest between name and aliases as 2 : 1.6 in a `layoutColumns()` called from
     `windowDidResize` and after `present`. Add the `No items match “<filter>”.` placeholder
     (13 pt secondary, centred in the table body) shown when the filter yields nothing.
4. `AppDelegate.swift`: no change required. Verify `showSettings` still passes
   `hotkeys.current ?? config.general.hotkey`.
5. Manual check: `make run`, menu bar → Settings…; resize to the minimum and confirm nothing is
   clipped; add a folder via `+`, select it, press Delete; click the recorder, press `⌘Q`
   (expected: red ring and a red sentence, the old hotkey still works), press `⌃⌥Space`
   (expected: applied, written to `~/.config/odd-frog/config.toml`). The snapshot hook renders
   the window: write `@settings` to `~/Library/Logs/odd-frog-query.txt` and run
   `pkill -USR2 -x OddFrog` → `~/Library/Logs/odd-frog-settings.png`.

Approach decision: keep one `NSStackView` root with fixed-height General/Folders groups and a
low-hugging Items group rather than an `NSSplitView`; the design explicitly rejects navigation
and resizable dividers. Alternative rejected: `NSGridView` for the forms, which fights the
per-row hairline and the switch+button trailing cluster.

## Constraints
- No comments in source.
- Swift 6 strict concurrency; `@MainActor`; `[weak self]` in stored closures; Sendable-safe
  `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` pattern as in the existing file
  for delayed work.
- Semantic AppKit colours only (`windowBackgroundColor`, `controlBackgroundColor`,
  `controlColor`, `separatorColor`, `labelColor` and its secondary/tertiary/quaternary
  variants, `controlAccentColor`, `systemRed`, `systemOrange`, `systemTeal`, `white`).
- System controls where the design says native: `NSSwitch`, `NSButton` push/checkbox,
  `NSSearchField`, `NSTableView`. Custom drawing only in `HotkeyRecorder`, `GroupBox`, the
  folder row selection, and the bottom bar fill.
- Copy strings exactly as given in Context.
- Do not touch `Sources/OddFrogCore/`, `LoginItem.swift`, `AppDelegate.swift`, or the
  launcher files.

## Acceptance
- `swift build -c release` passes.
- `swift test` passes (no Core changes).
- `make run` → Settings… opens at 680 × 640 with three titled grouped boxes and no visible
  sidebar or tabs; the Items box reaches the bottom padding.
- Resizing to 560 × 420: all three groups stay visible, the folder list shows at most three
  rows and scrolls, the Items box is at least 130 pt tall, nothing overlaps.
- Shortcut: clicking shows `Type shortcut…` and `Press the keys you want to use.`; `⌘Q` shows a
  red ring and red text ending in `Try another combination.`; `⌥Space` still toggles the panel
  afterwards; Escape and Delete cancel recording.
- Launch at login shows the correct one of the four states for the current install location
  (from `build/OddFrog.app` it is the unavailable state with the "Move Odd Frog…" sentence).
- Folders: empty list shows the placeholder; `+` adds; selecting shows an accent row with a
  white folder symbol and enables `−`; Delete removes; each row shows `N scripts` in tertiary.
- Filter with a nonsense string shows `No items match “<string>”.` centred in the table body.

## Out of scope
- Items table cell restyling: alias cell states, disabled-row tint, 16 pt icon tiles, kind
  colour (task 4).
- A "no hotkey" state or a ✕ clear button in the recorder (decided against).
- Launcher panel and rows (tasks 1–2).

## Open questions
none
