# Task: Surface every error in the menu bar, make the last failure actionable, request notification permission at launch

Task 07 of the "user flow" series. Independent; can run any time.

## Goal
Config, settings, hotkey and save errors show up under "Last failure" in the menu bar the same
way command failures do. The "Last failure" item copies the full message to the clipboard, and
an "Open Log" item opens `~/Library/Logs/odd-frog.log`. Notification permission is requested
once at launch instead of at the first failure.

## Files
- Sources/OddFrog/AppDelegate.swift   (modify)
- Sources/OddFrog/StatusMenu.swift    (modify)
- Sources/OddFrog/Notifier.swift      (modify)
- Sources/OddFrog/Log.swift           (read — `Log.url`)
- README.md                           (modify — menu bar sentence in Usage)

## Context
- Swift 6 strict concurrency, AppKit only, `@MainActor final class` for UI.
- `StatusMenu` rebuilds its menu in `menuNeedsUpdate`. `lastFailure: String?` renders as a
  disabled item "Last failure: <text>" (lines 33–36). Items are created through
  `action(_:_:)`, which sets `target = self`. Callbacks exposed: `onShow`, `onSettings`,
  `onReloadConfig`, `onOpenConfig`, `onRescan`, `onToggleLogin`.
- `AppDelegate` sets `status.lastFailure` only from `executor.onFailure` (first line of the
  message). All other errors go to `notifier.failure(...)` alone: `loadInitialConfig`,
  `loadInitialSettings`, `reloadConfig` (two sites), `reloadSettings`, `applySettings` (save
  failure), `wireHotkey`, `setHotkey` (config write failure), `status.onToggleLogin`.
  `wirePanel` also sets `settingsWindow.onApplyLink`, whose errors are shown in the Link
  Manager sheet and need no menu entry.
- `Notifier.post` requests `UNUserNotificationCenter` authorization lazily on the first call
  (`requested` flag) and is a no-op when `Bundle.main.bundleIdentifier == nil` (running the
  bare binary). The first thing most users see is therefore a permission prompt at the exact
  moment a command fails or prints output.
- `Log.url` is `~/Library/Logs/odd-frog.log`; `NSWorkspace.shared.open(url)` opens it in the
  default app for `.log` (Console).
- Clipboard: `NSPasteboard.general.clearContents()` then `setString(_:forType: .string)`.
- Tests: `swift test` (Core only, 56 tests). Nothing here is unit-testable; verification is manual.

## Plan
1. `Notifier.swift` — add `func requestAuthorizationIfNeeded()`: no-op unless `enabled`; if
   `requested` is false, set it and call `requestAuthorization(options: [.alert])`, logging a
   failure if the completion reports an error. Leave the lazy path in `post` as a fallback.
2. `AppDelegate.applicationDidFinishLaunching` — call `notifier.requestAuthorizationIfNeeded()`
   right after `TerminalLauncher.cleanupStaleFiles()`.
3. `AppDelegate` — add `private func report(_ message: String)` that writes
   `status.lastFailure = message` and calls `notifier.failure(message)`. Replace every
   `notifier.failure(...)` call listed in Context with `report(...)`, and make
   `executor.onFailure` call `report`'s status half only (the executor already notifies through
   its own `fail`; do not double-notify). Keep the existing message texts.
4. `StatusMenu.swift`
   - Keep `lastFailure` as the full message. In `menuNeedsUpdate`, render the item title as
     "Last failure: " + first line, truncated to 60 characters with an ellipsis, enabled, with
     `toolTip` set to the full message and action `copyFailure`, which copies the full message
     to the general pasteboard.
   - Add `var onOpenLog: (() -> Void)?` and an "Open Log" item directly after "Open Config".
5. `AppDelegate.wireStatusMenu` — `status.onOpenLog = { NSWorkspace.shared.open(Log.url) }`.
6. `README.md`, Usage: the menu bar sentence lists "Show, Settings…, Reload Config, Open
   Config, Open Log, Rescan Apps, the last failure (click to copy), and Launch at Login".

## Constraints
- No code comments of any kind.
- Swift 6 strict concurrency; `Notifier` and `StatusMenu` stay `@MainActor`.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes; `swift build -c release` succeeds.
- Manual after `make run`:
  1. First launch after `tccutil reset UserNotifications com.paveltrofimov.odd-frog`: the
     notification permission prompt appears right after the app starts, not on first failure.
  2. Break `~/.config/odd-frog/config.toml` (for example `max_results = 99`) and save. The
     menu bar shows "Last failure: max_results must be between 1 and 50, got 99". Clicking it
     puts the full message on the clipboard. Fix the file; the entry stays until the next
     failure replaces it.
  3. Menu bar → Open Log opens `~/Library/Logs/odd-frog.log`.
  4. A failing background command (for example `command = "false"`) still notifies exactly
     once and updates the menu entry.

## Out of scope
- Clearing the failure entry on success. Showing more than the last failure.
- Any change to what `ActionExecutor` reports.

## Open questions
none
