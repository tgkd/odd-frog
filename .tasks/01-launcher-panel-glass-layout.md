# Task: Launcher panel — Liquid Glass material, geometry, empty state, motion

Task 1 of 4 for the "Odd Frog" design. Run this one first; tasks 2–4 assume it is merged.

## Goal
The launcher panel becomes a single regular-glass surface with an 18 pt corner, a hairline inset
under the search field, an 8 pt list inset, a "No results" line when a query matches nothing,
a capped-and-scrolling list, and a short fade/rise on appearance. Row visuals (icons, selection
colours, chips) are NOT part of this task; the existing `ResultRowView` keeps working unchanged
inside the new geometry.

## Files
- Sources/OddFrog/LauncherPanel.swift            (modify)
- Sources/OddFrog/LauncherViewController.swift   (modify)
- Sources/OddFrog/SearchField.swift              (read — unchanged unless padding needs it)
- Sources/OddFrog/AppDelegate.swift              (read — `showPanel`/`hidePanel`/`onHeightChange` wiring; modify only the two lines named in the Plan)
- Sources/OddFrog/ResultRowView.swift            (read — row heights `singleLineHeight` 36 / `twoLineHeight` 40 are reused, do not edit)

## Context
- SwiftPM package, `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, Swift 6 strict
  concurrency. Toolchain on this machine: Xcode 27.0 beta 6, SDK 27.0, running macOS 27.0.
  All UI classes are `@MainActor final class`. AppKit only, no SwiftUI, no nibs.
- `LauncherPanel` is an `NSPanel` (`.nonactivatingPanel, .borderless, .fullSizeContentView`),
  `level = .floating`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`,
  `animationBehavior = .none`, fixed `width = 560`. `present(height:)` centres it on the screen
  under the mouse at 25 % from the top and calls `makeKeyAndOrderFront`. `resize(height:)` grows
  downward keeping the top edge fixed. `dismiss()` is `orderOut`.
- `LauncherViewController.loadView()` builds: an `NSVisualEffectView` root (`.popover`,
  `.behindWindow`, cornerRadius 12) → 44 pt header with `SearchField` at 14 pt side padding →
  full-width `NSBox` separator → `NSScrollView` hosting an `NSTableView` (`style = .inset`,
  `selectionHighlightStyle = .regular`, `intercellSpacing = 0`, `refusesFirstResponder = true`,
  no vertical scroller). `scrollHeight` is a height constraint updated in `refresh()` to
  `tableView.rect(ofRow: visible - 1).maxY + listPadding / 2` where `visible = min(rows, maxResults)`.
  `preferredHeight` = `fieldHeight + 1 + listPadding / 2 + scrollHeight.constant`, or just
  `fieldHeight` when there are no results. `onHeightChange` is called at the end of `refresh()`;
  `AppDelegate.wirePanel` forwards it to `panel.resize(height:)` only while the panel is visible.
- Results come from `SearchEngine.search(query:items:weights:maxResults:)` which already caps at
  `maxResults` (config `max_results`, 1…50, default 8). So today the list never scrolls.
- Keyboard: `control(_:textView:doCommandBy:)` handles ↑ ↓ ↩ ⎋ Home End. `select(row:)` calls
  `tableView.scrollRowToVisible`. Focus always stays in the search field.
- `NSGlassEffectView` exists in the SDK (`AppKit/NSGlassEffectView.h`): properties `contentView`,
  `cornerRadius`, `tintColor`, `style` (`.regular` / `.clear`). Only `contentView` is guaranteed
  to be rendered inside the glass; add all subviews to `contentView`, never to the glass view
  directly. It is `@available(macOS 26.0, *)`; the package deployment target is macOS 14, so it
  must be behind `if #available(macOS 26.0, *)`.
- Reduce Motion is `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- Metrics from the design (all points):

  | element                     | value |
  |-----------------------------|-------|
  | panel width                 | 560 |
  | panel corner radius         | 18 |
  | header height               | 44 |
  | header side padding         | 16 |
  | query font                  | 18 regular (already) |
  | hairline                    | 0.5 pt separatorColor, inset 12 from both side edges |
  | list inset                  | 6 top, 8 left/right, 8 bottom |
  | row heights                 | 36 one-line, 40 two-line (existing constants) |
  | visible row cap             | 8, then the list scrolls |
  | empty-state line            | 56 tall, 13 pt secondaryLabelColor, centred, text `No results for “<query>”` |
  | appear animation            | 0.14 s fade from 0 → 1 alpha plus a 4 pt rise; no scale |
  | height-change animation     | 0.14 s ease-out |

  Height formula: `44 + 6 + Σ(visible row heights) + 8`; with the empty-state line it is
  `44 + 56`; with no rows and an empty query it is `44`.

## Plan
1. `LauncherPanel.swift`
   - Keep everything as is, but make `present(height:)` animate: place the frame 4 pt lower than
     its final position with `alphaValue = 0`, call `makeKeyAndOrderFront`, then in an
     `NSAnimationContext.runAnimationGroup` with `duration = 0.14` and
     `timingFunction = CAMediaTimingFunction(name: .easeOut)` set `animator().alphaValue = 1` and
     `animator().setFrame(final, display: true)`. When Reduce Motion is on, or when the panel is
     already visible, set the final frame and alpha directly with no animation.
   - `resize(height:)`: same top-fixed maths, but apply through `animator().setFrame` inside a
     0.14 s ease-out group; direct `setFrame` under Reduce Motion or when the panel is not visible.
   - `dismiss()` stays instantaneous (`orderOut`) and must reset `alphaValue = 1` so a
     dismissed-mid-fade panel does not reappear transparent.
2. `LauncherViewController.swift`, `loadView()`
   - Build a `content` NSView that holds header, hairline, scroll view and the empty label.
   - Root: on macOS 26+ an `NSGlassEffectView` with `style = .regular`, `cornerRadius = 18`,
     `contentView = content`. Otherwise the existing `NSVisualEffectView` (`.popover`,
     `.behindWindow`, `.active`) with `layer?.cornerRadius = 18`, `masksToBounds = true`, and
     `content` added as a subview pinned to all edges. `view = root`.
   - Header: 44 pt tall, `searchField` at 16 pt leading/trailing, vertically centred.
   - Hairline: replace the `NSBox` with a plain `NSView` (`wantsLayer`, background
     `NSColor.separatorColor`), height 0.5, leading/trailing 12 pt.
   - Scroll view: leading 8, trailing −8, top = hairline bottom + 6. Set `tableView.style =
     .plain` (the 8 pt inset is now the scroll view's) and `hasVerticalScroller = true` with
     `autohidesScrollers = true`, `scrollerStyle = .overlay`.
   - Empty label: `NSTextField(labelWithString:)`, 13 pt, `secondaryLabelColor`, centred, height
     56, pinned below the hairline, hidden by default.
3. `LauncherViewController.swift`, `refresh()` and `preferredHeight`
   - `visible = min(rows, 8)` (a new `static let visibleRowCap = 8`), independent of `maxResults`.
   - `scrollHeight.constant = rows == 0 ? 0 : tableView.rect(ofRow: visible - 1).maxY`.
   - Empty state: `showEmpty = rows == 0 && !query.trimmed.isEmpty`; set the label text to
     `No results for “\(query)”` (curly quotes U+201C/U+201D), unhide it, hide the scroll view.
     Hairline is hidden only when `rows == 0 && !showEmpty`.
   - `preferredHeight`: `44` when nothing is shown; `44 + 56` for the empty state;
     `44 + 6 + scrollHeight.constant + 8` otherwise.
   - Remove `listPadding`; the 6/8 insets live in the constraints and the formula above.
4. `LauncherViewController.swift`, keyboard
   - No behaviour change, but after every `select(row:)` the selected row must remain visible
     now that the list can scroll (`scrollRowToVisible` already does this; keep it).
5. `AppDelegate.swift`: no logic change. Only adjust the `onHeightChange` closure if the
   signature of `panel.resize` changes (it should not).
6. Manual check with the debug hooks that already exist: `pkill -USR1 -x OddFrog` toggles the
   panel; writing a query to `~/Library/Logs/odd-frog-query.txt` and sending `pkill -USR2 -x
   OddFrog` renders `~/Library/Logs/odd-frog-panel.png`. Take captures for: empty query, a query
   with ≥ 9 matches (set `max_results = 12` in `~/.config/odd-frog/config.toml` temporarily),
   and a query with no matches.

Approach decision: the glass view wraps the content view rather than replacing the root type,
so the fallback path and the macOS 26 path share one layout. Alternative rejected: two separate
view hierarchies selected at runtime, which doubles the constraint code.

## Constraints
- No comments of any kind in Swift source (no `//`, no `///`, no `/* */`, no MARK). If a line
  needs explaining, rename or restructure instead.
- Swift 6 strict concurrency: UI classes stay `@MainActor`; closures that capture `self` use
  `[weak self]` as the neighbouring code does.
- 4-space indentation, no trailing whitespace, `final class`, one type per file, closures over
  delegates for callbacks (see `onSubmit`, `onDismiss`, `onHeightChange`).
- System colours only (`separatorColor`, `secondaryLabelColor`); no hard-coded hex.
- Do not change `ResultRowView`, `SearchField` typography, `SearchEngine`, or any file under
  `Sources/OddFrogCore/`.
- Surgical edits; keep the existing `focusField`, `prepareForShow`, snapshot hooks intact.

## Acceptance
- `swift build -c release` passes from the repo root.
- `swift test` passes (52 tests, 7 suites at time of writing; none touch this task).
- `make run` launches the app; `⌥Space` shows a 560 pt panel with visibly rounded 18 pt corners
  and (on macOS 26+) a glass background that blurs the desktop behind it.
- Typing a query with no matches shows one 56 pt line reading `No results for “<query>”` under a
  hairline that stops 12 pt short of each side edge.
- With `max_results = 12` and a query matching 12 items, the panel shows 8 rows and ↓ past the
  8th scrolls the list keeping the selection visible.
- Panel appearance fades in over ~0.14 s; with System Settings → Accessibility → Display →
  Reduce Motion on, it appears instantly.

## Out of scope
- Row appearance, selection colour, hover, icons, argument chips (task 2).
- Anything in Settings (tasks 3 and 4).
- The `max_results` config semantics.

## Open questions
none
