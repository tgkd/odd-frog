# Task: Window management — place the current window, cascade all windows, opt-in via settings

Task 12. Run before task 13 (`13-window-management-settings-ui.md`), which adds the Settings
window switch, the Accessibility helper and the README text on top of this.

## Goal
With `[window] enabled = true` in `~/.config/odd-frog/settings.toml`, the launcher lists ten
built-in "Window" items: Left ½, Right ½, Left ⅔, Right ⅔, Top ½, Bottom ½, Top ¾, Bottom ¾,
Maximize, Tidy Windows. The first nine move and resize the focused window of the frontmost app
on that window's screen. Tidy Windows lays every standard window on the current window's screen
out as a diagonal cascade (Rectangle's "Cascade All" / Windows' "Cascade"): same size for all,
front-to-back order kept, every title bar visible. When the setting is off (the default) no
window item exists and no Accessibility API is called. Missing Accessibility permission is
reported through the existing failure path with the system prompt shown once.

## Files
- Sources/OddFrogCore/WindowAction.swift          (create — action model + pure layout math)
- Sources/OddFrogCore/Item.swift                  (modify — `LauncherItem.window` case)
- Sources/OddFrogCore/Settings.swift              (modify — `[window]` section)
- Sources/OddFrog/WindowManager.swift             (create — Accessibility glue)
- Sources/OddFrog/ActionExecutor.swift            (modify — dispatch arm)
- Sources/OddFrog/IconCache.swift                 (modify — icon arm)
- Sources/OddFrog/AppDelegate.swift               (modify — contribute items when enabled)
- Makefile                                        (modify — `SIGN` variable)
- Tests/OddFrogCoreTests/WindowLayoutTests.swift  (create)
- Tests/OddFrogCoreTests/ScriptTests.swift        (modify — settings round trip covers `[window]`)
- Sources/OddFrogCore/QuickAction.swift           (read — a self-contained item kind with `id`/`title`/`kindLabel`, the pattern to mirror)
- Sources/OddFrog/TerminalLauncher.swift          (read — an outcome enum returned to `ActionExecutor`, the pattern to mirror)

## Context
- Swift 6 strict concurrency, SwiftPM only, macOS 14 deployment target, Swift Testing for
  tests. Two targets: `OddFrogCore` (Foundation + TOMLKit only, no AppKit) and the `OddFrog`
  app. `swift test` runs 73 tests and passes today; `swift build -c release` is clean.
- `LauncherItem` (Item.swift) is an enum with cases `app`, `command`, `script`, `quick`. Every
  computed property switches exhaustively: `id`, `title`, `subtitle`, `aliases`,
  `acceptsArgument`, `kindLabel`, `withAliases(_:)`. Adding a case means adding an arm to each.
  `Settings.apply(to:)` keys overrides by `id`, so any item with a stable id can be disabled or
  given extra aliases in Settings › Items with no further work. `withAliases` must merge for
  the new case (as `app`/`command`/`script` do), otherwise Items-table aliases are ignored.
- `SearchEngine` matches on `title` and `aliases`; nothing else needs to know about a new kind.
  `LauncherViewController` treats only `.quick` specially (`isQuick`); everything else gets
  ⌘I, frecency and the kind label from `kindLabel`. `ActionExecutor.record(_:)` skips ids
  starting with `quick:` and records everything else.
- `IconCache.icon(for:size:)` switches over the item; `tile(name:color:symbol:symbolSize:size:)`
  draws an SF Symbol on a rounded colour tile and caches by `name`. Existing tiles: shell
  (dark), path (systemBlue, `folder.fill`), url (systemTeal, `link`), search (systemIndigo).
- `ActionExecutor.run(_:argument:secondary:)` switches over the item; `runSecondary` too (the
  `.quick` arm there just calls `run`). Failures go through `fail(_:)`, which logs, sets the
  menu-bar "Last failure" and posts a notification. `record(id)` bumps frecency.
- `AppDelegate.rebuildItems()` builds `allItems = apps + config.commands + scripts`, applies
  settings and assigns to the controller only on change. `applySettings(_:persist:)` is the
  single entry point for a changed `Settings` (from the Settings window or the file watcher)
  and already calls `rebuildItems()`.
- `Settings` (Settings.swift) is `Codable`; each section is a nested struct with a hand-written
  `init(from:)` that defaults every key (`Search` is the smallest example). `Settings.parse`
  wraps TOML errors in `ConfigError.toml`. `serialized()` is `TOMLEncoder().encode(self)`.
  Adding a section: struct + property + `CodingKeys` case + `init(from:)` line + `init(...)`
  parameter with a default.
- The launcher panel is a `.nonactivatingPanel` (LauncherPanel.swift), so Odd Frog never
  becomes the active app: while the panel is up, `NSWorkspace.shared.frontmostApplication` is
  still the user's app, and `AppDelegate.onSubmit` hides the panel before calling the
  executor. "Current window" is therefore the Accessibility focused window
  (`kAXFocusedWindowAttribute`) of `NSWorkspace.shared.frontmostApplication`, falling back to
  the first of `kAXWindowsAttribute`. Rectangle does exactly this
  (`AccessibilityElement.getFrontWindowElement`).
- Accessibility coordinates: `kAXPositionAttribute` is in a top-left-origin space anchored at
  the top-left of the primary display (`NSScreen.screens[0]`, whose `frame.origin` is 0,0).
  `NSScreen.frame`/`visibleFrame` are bottom-left-origin. Flip with
  `y' = primaryHeight − rect.maxY` (same formula both directions, `x` unchanged).
  `CGWindowListCopyWindowInfo` bounds (`kCGWindowBounds`) are already in the top-left space,
  so they compare directly with AX position/size.
- Setting a frame through AX needs `AXUIElementSetAttributeValue` twice (position and size are
  separate attributes) and macOS clamps a size to the display the window is currently on, so
  the robust order is size, then position, then size again (Rectangle
  `AccessibilityElement.setFrame`). Values are built with `AXValueCreate(.cgPoint, &point)` /
  `AXValueCreate(.cgSize, &size)`. A window that refuses a size (minimum size) simply ends up
  smaller; nothing to handle.
- Window enumeration for Tidy (Rectangle `WindowUtil.getWindowList` +
  `MultiWindowManager.allWindowsOnScreen`): `CGWindowListCopyWindowInfo([.optionOnScreenOnly,
  .excludeDesktopElements], kCGNullWindowID)` returns on-screen windows of the current Space,
  front to back. Keep entries with `kCGWindowLayer == 0`, `kCGWindowOwnerPID` not our own pid,
  bounds at least 100×100, and whose owning `NSRunningApplication.activationPolicy` is
  `.regular`. For each distinct pid ask AX for `kAXWindowsAttribute` once, and match a CG entry
  to the AX window whose position+size equal the CG bounds within 2 pt; keep only AX windows
  whose `kAXSubroleAttribute` is `kAXStandardWindowSubrole` (drops dialogs, sheets, floating
  panels). Minimised windows are not on screen, so they are excluded automatically. Which
  screen a window belongs to: the `NSScreen` whose `frame` has the largest intersection with
  the window's frame (flipped to Cocoa space), falling back to `NSScreen.main`.
- Rectangle's cascade (`MultiWindowManager.cascadeWindow`) offsets each window by a fixed
  `cascadeAllDeltaSize` (30 pt) diagonally; its Tile All is a ceil(√n) grid, which is the
  "unreadably small" outcome to avoid. Rectangle re-raises windows in pid order; here the
  z-order is preserved by not raising anything: AX position/size changes never reorder.
- Permission: `AXIsProcessTrusted()` reports the state without UI;
  `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
  as CFDictionary)` additionally shows the system prompt (once per app identity; later calls
  are silent). Both are in `ApplicationServices`. No Info.plist key is required.
- Signing gotcha: `Makefile` `bundle` signs with `codesign --force --sign - --deep`. Ad-hoc
  signatures have a cdhash-based designated requirement, so the TCC Accessibility grant is
  bound to the exact binary and is silently invalid after every rebuild (System Settings still
  shows the switch on; `AXIsProcessTrusted()` returns false until the entry is removed and
  re-added). A self-signed code-signing certificate in the login keychain gives a stable
  identity; `SIGN` in the Makefile lets the user pass it (`make run SIGN="OddFrog Dev"`).
- Log: `Log.write(_ message: String)`; existing lines look like
  `Log.write("scripts scanned: \(scripts.count) in \(folders.count) folders")`.
- `TerminalLauncher.launch(...)` returns `enum Outcome { case launched; case failed(String) }`
  and `ActionExecutor.runInTerminal` switches on it — mirror that shape for window outcomes.

## Plan
1. `Sources/OddFrogCore/WindowAction.swift` (new, `import Foundation` only)
   - `public enum WindowEdge: String, Sendable, Hashable, CaseIterable { case left, right, top, bottom }`.
   - `public struct WindowFraction: Sendable, Hashable { public let numerator: Int; public let denominator: Int; public var value: Double }`
     with `public var label: String` returning `"½"` for 1/2, `"⅔"` for 2/3, `"¾"` for 3/4
     and `"\(numerator)/\(denominator)"` otherwise, and `public var slug: String` returning
     `"\(numerator)-\(denominator)"`.
   - `public enum WindowAction: Sendable, Hashable { case place(WindowEdge, WindowFraction); case maximize; case tidy }`
     - `id`: `"window:place:\(edge.rawValue):\(fraction.slug)"`, `"window:maximize"`, `"window:tidy"`.
     - `title`: `"Left ⅔"` style (edge capitalised + space + label), `"Maximize"`, `"Tidy Windows"`.
     - `subtitle: String?`: `nil` for placements and maximize, `"Cascade every window on this screen"` for tidy.
     - `kindLabel`: `"Window"` for all.
     - `public static let all: [WindowAction]` in this order: left ½, right ½, left ⅔, right ⅔,
       top ½, bottom ½, top ¾, bottom ¾, maximize, tidy.
   - `public enum WindowLayout` with pure functions on `CGRect` in Cocoa (bottom-left) space:
     - `static func frame(for action: WindowAction, in visible: CGRect) -> CGRect?` — `.tidy`
       returns nil. Placements: left/right take `round(visible.width × f)` wide and full
       height, anchored to `minX` / `maxX`; top/bottom take `round(visible.height × f)` high and
       full width, anchored to `maxY` / `minY`. Maximize returns `visible`.
     - `static func cascade(count: Int, in visible: CGRect, step: CGFloat) -> [CGRect]` —
       returns `count` frames in back-to-front order. Effective step = `min(step,
       visible.width / 2 / (count − 1), visible.height / 2 / (count − 1))` when `count > 1`
       (so windows never shrink below half the screen), size = `visible.size` minus
       `(count − 1) × step` on both axes, rounded. Frame `i` has origin
       `(visible.minX + i × step, visible.maxY − i × step − height)`. `count == 1` returns
       `[visible]`; `count == 0` returns `[]`.
     - `static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect` — the y-flip
       described in Context.
2. `Sources/OddFrogCore/Settings.swift`: add `public struct Window: Codable, Sendable, Equatable`
   with `public var enabled: Bool` (default `false`) and `public var cascadeStep: Double`
   (default `32`, TOML key `cascade_step`, values outside 16…120 fall back to 32 in
   `init(from:)`), plus `public var window: Window` on `Settings`, wired exactly like `search`.
3. `Sources/OddFrogCore/Item.swift`: add
   `public struct WindowItem: Sendable, Hashable { public let action: WindowAction; public var aliases: [String] }`
   with `public init(action: WindowAction, aliases: [String] = [])` and `id` forwarding to the
   action (mirrors `ScriptItem`), then `case window(WindowItem)` on `LauncherItem` with an arm
   in every switch: `id`/`title`/`subtitle`/`kindLabel` delegate to the action; `aliases`
   returns the stored extra aliases; `acceptsArgument` is false; `withAliases` merges like the
   other cases.
4. `Sources/OddFrog/WindowManager.swift` (new, `@MainActor final class WindowManager`,
   imports AppKit + ApplicationServices + OddFrogCore)
   - `enum Outcome { case done; case failed(String); case needsAccessibility }`.
   - `static var hasAccess: Bool` (`AXIsProcessTrusted()`), `static func requestAccess()`
     (the prompting variant), `static func openAccessibilitySettings()` (opens
     `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` through
     `NSWorkspace`). Task 13 uses these from the Settings window.
   - `func perform(_ action: WindowAction, cascadeStep: CGFloat) -> Outcome`:
     1. If `!Self.hasAccess`, call `Self.requestAccess()` once per process (keep a
        `promptedForAccess` flag) and return `.needsAccessibility`.
     2. Resolve the current window as described in Context; return
        `.failed("No window to move")` when none.
     3. Compute the window's Cocoa frame (read `kAXPositionAttribute` and `kAXSizeAttribute`,
        flip) and its screen (largest intersection). `visible = screen.visibleFrame`.
     4. Placement/maximize: `WindowLayout.frame(for:in:)`, flip back, set size → position →
        size. Log `window: <title> → <rounded frame>`.
     5. Tidy: enumerate as in Context, filter to windows on this screen, reverse to
        back-to-front, `WindowLayout.cascade(count:in:step:)`, apply frame `i` to window `i`.
        Return `.failed("No windows to tidy")` when the list is empty. Log
        `window: tidy <n> windows on <screen.localizedName>`.
   - Keep the AX helpers private in this file: `attribute<T>(_:of:)`, `set(_:point:)`,
     `set(_:size:)`, `windows(of pid:)`, `focusedWindow(of pid:)`, `subrole(of:)`.
     `AXUIElement` is not `Sendable`; keep everything synchronous on the main actor and never
     capture an element in a `Task`.
5. `Sources/OddFrog/ActionExecutor.swift`: add `let windows = WindowManager()` and
   `var cascadeStep: CGFloat = 32`; in `run` add `case .window(let item)`: switch on
   `windows.perform(item.action, cascadeStep: cascadeStep)` — `.done` → `record(item.id)`;
   `.failed(let message)` → `fail("\(item.title): \(message)")`; `.needsAccessibility` →
   `fail("Window management needs Accessibility access. Allow Odd Frog under System Settings › Privacy & Security › Accessibility.")`.
   In `runSecondary`, `.window` behaves like `.quick`: call `run`.
6. `Sources/OddFrog/IconCache.swift`: `case .window(let item)` → a `.systemPurple` tile,
   symbol by action: left `rectangle.lefthalf.filled`, right `rectangle.righthalf.filled`, top
   `rectangle.tophalf.filled`, bottom `rectangle.bottomhalf.filled`, maximize
   `rectangle.fill`, tidy `rectangle.stack.fill`; `symbolSize: 13`; tile `name` =
   `"window-" + symbol` so each caches separately.
7. `Sources/OddFrog/AppDelegate.swift`: in `rebuildItems()` append
   `settings.window.enabled ? WindowAction.all.map { LauncherItem.window(WindowItem(action: $0)) } : []`
   after scripts. In `applySettings(_:persist:)` set `executor.cascadeStep =
   CGFloat(settings.window.cascadeStep)`; also set it once in `wirePanel()` from the initial
   settings.
8. `Makefile`: add `SIGN ?= -` next to the other variables and change the codesign line to
   `codesign --force --sign "$(SIGN)" --deep $(BUNDLE)`.
9. Tests
   - `Tests/OddFrogCoreTests/WindowLayoutTests.swift` (Swift Testing, `@testable import OddFrogCore`):
     - `placementsAnchorToEdges`: `visible = CGRect(x: 0, y: 25, width: 1000, height: 600)`;
       left ⅔ → `(0, 25, 667, 600)`; right ⅔ → `(333, 25, 667, 600)`; top ¾ → `(0, 175, 1000, 450)`;
       bottom ¾ → `(0, 25, 1000, 450)`; maximize → `visible`; tidy → nil.
     - `cascadeKeepsEveryTitleBarVisible`: `cascade(count: 4, in: visible, step: 32)` → four
       frames, all `904×504`, origins `(0, 121)`, `(32, 89)`, `(64, 57)`, `(96, 25)`.
     - `cascadeNeverShrinksBelowHalfScreen`: `cascade(count: 40, in: visible, step: 32)` → every
       frame at least `499×299`, the last frame's `maxX` ≤ 1001 and `minY` ≥ 24 (the effective
       step is fractional, so allow 1 pt of rounding).
     - `cascadeEdgeCounts`: count 1 → `[visible]`; count 0 → `[]`.
     - `flipRoundTrips`: `flipped(flipped(r, primaryHeight: 900), primaryHeight: 900) == r` and
       `flipped(CGRect(x: 10, y: 800, width: 100, height: 50), primaryHeight: 900)` ==
       `CGRect(x: 10, y: 50, width: 100, height: 50)`.
     - `actionIdsAndTitles`: `WindowAction.all.map(\.id)` are unique and count 10;
       `.place(.left, WindowFraction(numerator: 2, denominator: 3)).title == "Left ⅔"`;
       `.tidy.title == "Tidy Windows"`.
   - `ScriptTests.settingsRoundTripAndApply`: set `settings.window.enabled = true` and
     `settings.window.cascadeStep = 40` before serializing and assert both survive the round
     trip; extend `emptySettingsParse` with `#expect(s.window.enabled == false)` and
     `#expect(s.window.cascadeStep == 32)`.

## Constraints
- No code comments of any kind, in any file.
- Swift 6 strict concurrency: new types in `OddFrogCore` are `Sendable`; `WindowManager` is
  `@MainActor` and synchronous; `AXUIElement` values never cross an isolation boundary.
- `OddFrogCore` must not import AppKit or ApplicationServices; all AX calls live in
  `Sources/OddFrog/WindowManager.swift`.
- Swift Testing only (`@Test`, `#expect`). No new package dependencies.
- Four-space indentation, `switch` arms in the single-expression style used in Item.swift.
- The window items must not appear when `settings.window.enabled` is false, and nothing in the
  app may call an `AX*` function unless a window item runs.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes from the repo root with the six new tests (79 total).
- `swift build -c release` succeeds.
- Manual, after `make run`:
  1. With no `[window]` section in `~/.config/odd-frog/settings.toml`, typing `left` in the
     launcher shows no Window rows.
  2. Add `[window]\nenabled = true` to `settings.toml` and save: typing `left` lists "Left ½"
     and "Left ⅔" with a purple tile and the kind label "Window"; Settings › Items lists all
     ten with kind "Window" and lets you disable one.
  3. First run of "Left ⅔" before granting access: a notification says window management
     needs Accessibility access, the macOS Accessibility prompt appears, and the menu bar
     shows the same text under "Last failure".
  4. Grant access (System Settings › Privacy & Security › Accessibility). Focus Safari, open
     the launcher, run "Left ⅔": Safari's window fills the left two thirds of its screen,
     below the menu bar and above the Dock. "Top ¾", "Bottom ¾", "Right ½", "Maximize" behave
     accordingly. The launcher hides before the window moves and Odd Frog never becomes the
     active app.
  5. Open four windows of different apps, run "Tidy Windows": all four are the same size,
     staggered 32 pt diagonally, the previously frontmost window stays frontmost and
     bottom-right, every title bar is visible, and none is smaller than half the screen.
     Minimised windows and windows on another display are left alone.
  6. `~/Library/Logs/odd-frog.log` has a `window:` line per action.
  7. `make run SIGN="<name of a self-signed code-signing certificate>"` builds and the
     Accessibility grant survives a second `make run` with the same `SIGN`.

## Out of scope
- Settings-window UI for the switch and the Accessibility status (task 13), README text
  (task 13). Global hotkeys for window actions outside the launcher. Undo / restore of the
  previous frame. Gaps between windows. Cascade of a single app's windows. Disabling
  `AXEnhancedUserInterface` for Electron apps (add later if a Chrome/Electron window resizes
  wrongly). Per-item fraction arguments (`left 2/3`).

## Open questions
none
