# Task: Window management switch and Accessibility status in Settings › General, README

Task 13. Requires task 12 (`12-window-management.md`) merged: it assumes `Settings.window`,
`WindowManager.hasAccess`, `WindowManager.requestAccess()`,
`WindowManager.openAccessibilitySettings()` and the `SIGN` Makefile variable exist.

## Goal
Settings › General has a fourth block, "Window management", with a switch that turns the
feature on and off and a helper line that says whether Odd Frog has Accessibility access, with
an "Open System Settings" button when it does not. Turning the switch on asks macOS for
Accessibility access. The README documents the feature, the setting and the signing gotcha.

## Files
- Sources/OddFrog/SettingsWindowController.swift   (modify — new block, present/refresh, actions)
- README.md                                        (modify — Usage, Settings, Build sections)
- Sources/OddFrog/WindowManager.swift              (read — static access helpers to call)

## Context
- Settings › General is built in `SettingsWindowController` around line 240–300: three
  `settingBlock(title:control:helper:)` boxes ("Shortcut", "Launch at login", "Web search") in
  a horizontal `NSStackView` with `distribution = .fillEqually`, `spacing = 12`, heights tied to
  the login block. `settingBlock` lays out a caption, a 24 pt-high control and a wrapping
  helper label (`style(helper:)` gives it the 11 pt secondary style).
- The "Launch at login" block is the pattern for a switch with status: `loginSwitch`
  (`NSSwitch`, target/action `toggleLogin`), `loginButton` (small rounded `NSButton`, hidden
  unless approval is needed, action `openLoginItems`), both inside a horizontal `NSStackView`
  used as the block's control; `refreshLogin()` recomputes the helper text and button
  visibility, and `toggleLogin` calls it again 0.3 s later because the system state updates
  asynchronously.
- `present(settings:items:hotkey:focusing:)` copies every setting into its control
  (`webSearchField.stringValue = settings.search.url`, `watchSwitch.state` in
  `reloadFolders()`), so a new control gets its value there. `commit()` calls
  `onChange?(settings)`, which `AppDelegate.applySettings(_:persist: true)` handles: it saves
  `settings.toml` and rebuilds the item list, so the window items appear or disappear
  immediately.
- The switch state is `.on`/`.off`; `NSSwitch` is `NSControl`, read `state == .on`.
- Accessibility access can change while Settings is open (the user flips it in System
  Settings and comes back). `NSApplication.didBecomeActiveNotification` fires when the user
  returns to Odd Frog's Settings window; observe it on `NotificationCenter.default` in `init`
  and refresh the helper.
- README sections that exist today: "Build and run" (make targets), "Usage" (keys and
  fallbacks), "Config", "Settings" (bulleted list of General blocks, then the TOML example
  that shows `[scripts]`, `[[items]]`, `[search]`), "Links", "Scripts", "Using ⌘Space",
  "Terminals", "Ranking", "Logs", "App icon".

## Plan
1. `SettingsWindowController.swift`
   - Add `private let windowSwitch = NSSwitch()`, `private let windowAccessButton = NSButton(title: "Open System Settings", target: nil, action: nil)`,
     `private let windowHelper = NSTextField(wrappingLabelWithString: "")`.
   - In the General builder, configure them like the login controls (switch action
     `toggleWindowManagement`, button action `openAccessibilitySettings`, small rounded
     11 pt button hidden by default), put switch and button in a horizontal stack, and add
     `settingBlock(title: "Window management", control: stack, helper: windowHelper)` as the
     fourth view in the blocks stack with its height tied to the login block like the others.
   - `refreshWindowManagement()`: `windowSwitch.state` from `settings.window.enabled`. Helper
     text: disabled → "Adds Left ⅔, Top ¾, Tidy Windows and friends to the launcher. Needs
     Accessibility access." (secondary colour, button hidden); enabled and
     `WindowManager.hasAccess` → "Accessibility access granted." (secondary, button hidden);
     enabled without access → "Allow Odd Frog under Privacy & Security › Accessibility."
     (`.systemRed`, button shown).
   - Call `refreshWindowManagement()` from `present(...)` next to the web-search line, and
     from a `didBecomeActive` observer registered in `init` (guard `window?.isVisible == true`).
   - `toggleWindowManagement()`: set `settings.window.enabled`, `commit()`, if turning on and
     no access call `WindowManager.requestAccess()`, then `refreshWindowManagement()` now and
     again after 0.3 s (same `DispatchQueue.main.asyncAfter` + `MainActor.assumeIsolated`
     shape as `toggleLogin`).
   - `openAccessibilitySettings()`: `WindowManager.openAccessibilitySettings()`.
2. `README.md`
   - "Usage": after the ⌘I paragraph add a paragraph: with window management on, the launcher
     has ten "Window" items (list them); placements act on the focused window of the frontmost
     app on that window's screen; Tidy Windows cascades every standard window on that screen
     diagonally, same size, front-to-back order kept; they can be renamed with aliases or
     disabled in Settings › Items like any item.
   - "Settings" bullets: add **Window management**: off by default; turning it on asks for
     Accessibility access; the helper shows the state and offers "Open System Settings".
   - The settings TOML example: add
     ```toml
     [window]
     enabled = true
     cascade_step = 32
     ```
     with a sentence that `cascade_step` is the diagonal offset in points for Tidy Windows
     (16–120, default 32) and has no UI.
   - "Build and run": add a short paragraph on `SIGN`: the default ad-hoc signature changes on
     every build, which makes macOS forget the Accessibility grant; create a self-signed
     code-signing certificate in Keychain Access (Keychain Access › Certificate Assistant ›
     Create a Certificate…, type "Code Signing", name it e.g. `OddFrog Dev`) and build with
     `make run SIGN="OddFrog Dev"` or `make install SIGN="OddFrog Dev"`.

## Constraints
- No code comments of any kind.
- Swift 6 strict concurrency: `SettingsWindowController` is `@MainActor`; notification
  observers use the selector form (`addObserver(self, selector:name:object:)`) as the panel does.
- Mirror the login block exactly for control styling (`NSSwitch`, `bezelStyle = .rounded`,
  `controlSize = .small`, 11 pt font, `spacing = 8`, `alignment = .centerY`).
- No new strings in `Settings` or `OddFrogCore`; this task is UI and docs only.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes from the repo root (no new tests; 79 from task 12).
- `swift build -c release` succeeds.
- Manual, after `make run`:
  1. Menu bar → Settings…: General shows four equal-width blocks; "Window management" is off
     with the explanatory helper and no button.
  2. Flip the switch on with no Accessibility grant: the macOS prompt appears,
     `~/.config/odd-frog/settings.toml` gains `[window]` with `enabled = true`, the helper turns
     red with "Open System Settings" visible, and the launcher now lists "Tidy Windows".
  3. Click "Open System Settings": Privacy & Security › Accessibility opens. Grant access,
     return to the Settings window: the helper reads "Accessibility access granted." without
     reopening the window.
  4. Flip the switch off: the launcher no longer lists any Window item and `settings.toml`
     says `enabled = false`.
  5. The README "Usage", "Settings" and "Build and run" sections contain the new text.

## Out of scope
- Any change to `OddFrogCore`, `WindowManager`, `ActionExecutor`, or the layout math. A UI for
  `cascade_step`. Global hotkeys for window actions.

## Open questions
none
