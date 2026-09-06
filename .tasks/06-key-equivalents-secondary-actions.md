# Task: ⌘↩ secondary action per item kind and ⌘1–⌘9 to run the Nth row

Task 06 of the "user flow" series. Run after 05 (uses `refresh(keepSelection:)` only
incidentally; the important dependency is that 10 builds on the key-equivalent hook added here).

## Goal
⌘↩ runs the selected item's secondary action: apps reveal in Finder, folder commands open in
the configured terminal, URL commands copy the URL, background shell commands run in the
terminal, scripts run in the terminal with full output. ⌘1 … ⌘9 run the first … ninth
visible row with the primary action.

## Files
- Sources/OddFrog/LauncherPanel.swift             (modify — key event hook)
- Sources/OddFrog/LauncherViewController.swift    (modify — handle the events, extend `onSubmit`)
- Sources/OddFrog/AppDelegate.swift               (modify — wire hook, pass the mode to the executor)
- Sources/OddFrog/ActionExecutor.swift            (modify — secondary actions)
- Sources/OddFrog/TerminalLauncher.swift          (read — `launch(command:cwd:name:kind:shell:)`)
- Sources/OddFrogCore/ShellCommand.swift          (read — `quote`)
- README.md                                       (modify — Usage)

## Context
- Swift 6 strict concurrency, AppKit only, `@MainActor final class` for UI. Toolchain Xcode 27
  beta on macOS 27; deployment target macOS 14.
- `LauncherPanel` is an `NSPanel` with `.nonactivatingPanel`; it is the key window while shown,
  so key events reach it through `sendEvent(_:)`. The app has `.accessory` activation policy
  and no main menu, so there are no menu key equivalents to conflict with ⌘-digit or ⌘↩.
  `HotkeyRecorder.swift` line 48 shows the project already overrides `performKeyEquivalent`
  elsewhere; for a window the reliable interception point is `sendEvent(_:)`.
- Return key codes are 36 (Return) and 76 (keypad Enter); `SettingsWindowController.swift`
  line 850 uses the same pair. Digits: `event.charactersIgnoringModifiers` is `"1"`…`"9"`.
  Use `event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command` so ⌘⇧1
  and ⌥⌘↩ are not treated as the shortcut.
- `LauncherViewController.onSubmit` is `((LauncherItem, String?) -> Void)?`; `AppDelegate.
  wirePanel` sets it to hide the panel and call `executor.run(item, argument:)`. `submit()`
  reads `tableView.selectedRow`; `select(row:)` clamps and scrolls. `rowClicked` selects then
  submits.
- `ActionExecutor.run(_:argument:)` switches on `LauncherItem`: `.app` → `openApplication`,
  `.command` with `.path`/`.url` → `NSWorkspace.shared.open`, `.shell` → `runInTerminal` when
  `command.terminal` else `spawn` in the background; `.script` → `runScript`, which uses
  `runInTerminal` for `.fullOutput` and `spawn` for `.silent`/`.inline`, and refuses a missing
  required argument with a notification. `runInTerminal(id:name:command:cwd:)` calls
  `TerminalLauncher.launch` with `config.general.terminal` / `config.general.shell` and records
  frecency on success. `record(_:)` updates `FrecencyStore` and fires `onRecorded`.
- `TerminalLauncher.launch` runs `<shell> -lc '<command>'` in a new terminal session with
  `cwd` (defaults to home). To open an interactive shell in a folder, the command
  `exec <quoted shell> -l` works with every supported terminal kind.
- Revealing in Finder: `NSWorkspace.shared.activateFileViewerSelecting([url])`.
- Clipboard: `NSPasteboard.general.clearContents()` then `setString(_:forType: .string)`.
- Tests: `swift test` (56 Core tests). No UI tests.

## Plan
1. `LauncherPanel.swift` — add `var onKeyEquivalent: ((NSEvent) -> Bool)?` and override
   `sendEvent(_:)`: for `.keyDown` events whose device-independent modifiers are exactly
   `.command`, call the hook first and return if it handled the event; otherwise call `super`.
2. `LauncherViewController.swift`
   - Change `onSubmit` to `((LauncherItem, String?, Bool) -> Void)?`; the Bool is
     `secondary`. `submit()` becomes `submit(secondary: Bool = false)` and passes it through.
     `rowClicked` and the `insertNewline:` case keep calling the primary form.
   - Add `func handleKeyEquivalent(_ event: NSEvent) -> Bool`: key code 36 or 76 →
     `submit(secondary: true)`, return true; a single digit 1–9 in
     `charactersIgnoringModifiers` → if `results.count >= n`, `select(row: n - 1)` then
     `submit()`, return true (return true even when the row does not exist, so the keystroke
     is swallowed); anything else → false.
3. `AppDelegate.swift`, `wirePanel` — set `panel.onKeyEquivalent` to forward to
   `controller.handleKeyEquivalent`; update the `onSubmit` closure to the three-argument form
   and call `executor.run(item, argument: argument, secondary: secondary)`.
4. `ActionExecutor.swift`
   - `run(_:argument:secondary: Bool = false)`. When `secondary` is false, behaviour is
     unchanged.
   - Secondary mapping, each recording frecency the same way the primary does:
     - `.app` → `activateFileViewerSelecting([app.url])`, then `record(app.id)`.
     - `.command` `.path(url)` → if `url` is a directory (`FileManager.default.fileExists(atPath:isDirectory:)`)
       `runInTerminal(id:name:command: "exec \(ShellCommand.quote(config.general.shell)) -l", cwd: url)`;
       if it is a file, reveal it in Finder and record.
     - `.command` `.url(url)` → copy `url.absoluteString` to the general pasteboard, record.
       No notification; `Log.write` one line.
     - `.command` `.shell(text)` → `runInTerminal` regardless of `command.terminal`.
     - `.script` → same argument check as `runScript`; then always the `.fullOutput` path
       (terminal), regardless of `script.mode`.
5. `README.md`, Usage: add `⌘↩` with the per-kind list above and `⌘1`–`⌘9`.

## Constraints
- No code comments of any kind.
- Swift 6 strict concurrency; UI code stays `@MainActor`. No new dependencies, no SwiftUI.
- Keep `.nonactivatingPanel` and the existing panel behaviour; only add the hook.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes; `swift build -c release` succeeds.
- Manual after `make run`:
  1. Type `saf`, press ⌘↩: a Finder window opens with Safari.app selected; the panel hides.
  2. With the example config's "Open Projects" (`path = "~/Projects"`), type `projects`,
     ⌘↩: a terminal session opens with `~/Projects` as its working directory.
  3. Type `gh`, ⌘↩, then paste somewhere: `https://github.com`.
  4. Type `up` (example "Uptime", `terminal = true`), ⌘↩: same as ↩ (terminal).
  5. A background `command = "…"` entry without `terminal`: ⌘↩ opens it in the terminal.
  6. Open the panel with an empty query showing several rows, press ⌘3: the third row's item
     runs. ⌘9 with fewer than nine rows does nothing and types nothing into the field.
  7. ⌘⇧1 and plain digits still type into the field.

## Out of scope
- Showing digit badges on rows. ⌥↩ variants. Settings jump (task 10).
- Fallback rows (task 09) — if `LauncherItem.quick` exists when this runs, its secondary
  action is the same as its primary.

## Open questions
none
