# Task: Raise the deployment target to macOS 26 and remove the pre-26 code paths

## Goal
Odd Frog builds for macOS 26 and later only: the package, the bundle's `Info.plist` and the
README all say macOS 26. The launcher always uses its Liquid Glass background, with no
`#available` branch and no pre-26 fallback. The SIGUSR2 debug hook no longer captures pixels in
the app. It writes the target window's number to a text file, so a reviewer can capture the window
with `screencapture`. The build no longer uses any API that is obsolete or deprecated on macOS 26.

## Files
- Package.swift                                        (modify)
- Resources/Info.plist                                 (modify)
- README.md                                            (modify)
- Sources/OddFrog/AppDelegate.swift                    (modify)
- Sources/OddFrog/LauncherViewController.swift         (modify)
- Sources/OddFrog/SettingsWindowController.swift       (modify)
- Sources/OddFrogCore/PluginProcess.swift              (modify)
- Sources/OddFrog/Log.swift                            (read — `Log.url` is `~/Library/Logs/odd-frog.log`; the snapshot files go in the same directory)
- Sources/OddFrog/main.swift                           (read — declares the global `delegate` that the snapshot closures call)
- Sources/OddFrog/SettingsSidebar.swift                (read — `SettingsPane` titles, matched by the `@settings <pane>` snapshot command)
- Makefile                                             (read — `make bundle` copies `Resources/Info.plist` into the bundle unchanged)
- Tests/OddFrogCoreTests/PluginTests.swift             (read — spawns fixture providers through `PluginProcess`, so `swift test` exercises the changed spawn call)

## Context
- Swift package, AppKit app, no Xcode project. `Package.swift` starts with
  `// swift-tools-version: 6.0` and declares `platforms: [.macOS(.v14)]`. `Resources/Info.plist` has
  `LSMinimumSystemVersion` = `14.0`. Tests use Swift Testing.
- The installed toolchain is Swift 6.4. In PackageDescription, `MacOSVersion.v26` requires
  tools version 6.2 and `.v27` requires 6.4. A trial build of this tree with tools version 6.2 and
  `.macOS(.v26)` compiled every target and test target. Its only warnings were:
  - `'nonisolated(unsafe)' is unnecessary …` in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`.
    This one is already there today and stays.
  - `'showsBaselineSeparator' was deprecated in macOS 15.0` in `SettingsWindowController.init`.
  - `'posix_spawn_file_actions_addchdir_np' was deprecated in macOS 26.0: posix_spawn_file_actions_addchdir(3) has replaced …`
    in `Sources/OddFrogCore/PluginProcess.swift`.
- `CGWindowListCreateImage` is marked `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)` in `CGWindow.h`. At
  any deployment target of 15 or later it is unavailable, which is a compile error, not a warning. It
  is called only in `AppDelegate.render(_:to:)`.
- Baseline today: `swift build` succeeds with two warnings, the `CGWindowListCreateImage`
  deprecation and the UnitRegistry one. `swift test` passes 259 tests in six test bundles.
- The snapshot hook in `AppDelegate`:
  - `wireSignals()` installs a SIGUSR2 `DispatchSource` that calls `snapshotPanel()`, and a SIGUSR1
    source that toggles the launcher (`togglePanel()`). Both stay as they are.
  - The launcher hides itself when it stops being the key window (`LauncherPanel.onResignKey`).
  - `snapshotPanel()` reads a command from `~/Library/Logs/odd-frog-query.txt`, in the directory
    `Log.url.deletingLastPathComponent()`.
  - `@settings [pane]` shows Settings and selects the pane whose lowercased title matches: general,
    items or plugins. After 0.5 s it renders `settingsWindow.window?.contentView` to
    `odd-frog-settings.png`.
  - `@run <query>` runs the first result of the query and captures nothing.
  - Any other text is typed into the launcher query. The panel must already be visible. After 0.4 s
    it renders `panel.contentView` to `odd-frog-panel.png`.
  - `render(_ view: NSView?, to url: URL)` looks up `view.window`, calls
    `window.displayIfNeeded()`, captures `CGWindowID(window.windowNumber)` with
    `CGWindowListCreateImage`, and writes a PNG. Every path ends in a `Log.write(...)`.
  - The delayed closures run inside `MainActor.assumeIsolated` and call through the global
    `delegate`, which is why `render` is not `private`.
- `NSWindow.windowNumber` is the window server's window number, the same value that `screencapture -l`
  takes. `screencapture -x -o -l <id> out.png` captures one window: `-x` means no sound and `-o`
  means no shadow. It composites Liquid Glass faithfully and needs the Screen Recording permission
  only for the terminal that runs it. Capturing in the app itself was rejected for two reasons.
  ScreenCaptureKit would need Screen Recording permission for Odd Frog, and every ad-hoc re-signed
  rebuild loses that permission. `NSView.cacheDisplay(in:to:)` renders glass flat.
- `LauncherViewController.loadView()` builds a plain `content` view. It then picks the root:
  - Under `if #available(macOS 26.0, *)` it builds an `NSGlassEffectView` and sets
    `glass.style = .regular`, `glass.cornerRadius = Self.cornerRadius` (18) and
    `glass.contentView = content`.
  - The `else` branch builds an `NSVisualEffectView` (`.popover`, `.behindWindow`, `.active`), rounds
    it with `wantsLayer`, `layer.cornerRadius` and `masksToBounds`, and adds `content` as a subview.

  After the branch, the code sets `content.translatesAutoresizingMaskIntoConstraints = false`, pins
  the four edges of `content` to the root, sets `root.translatesAutoresizingMaskIntoConstraints = false`,
  and assigns `view = root`. This is the only `#available` in the repository.
- Measured on macOS 26 SDK builds:
  - `NSGlassEffectView.style` defaults to `.regular`.
  - Assigning `glass.contentView = content` makes the glass set
    `content.translatesAutoresizingMaskIntoConstraints = false` and add four constraints of its own
    that keep `content` at the glass bounds.

  So the style line, the `translatesAutoresizingMaskIntoConstraints` line on `content` and the four
  edge constraints are redundant once the fallback is gone.
- `SettingsWindowController.init` sets `toolbar.showsBaselineSeparator = false` on an empty
  toolbar. The window already sets `titlebarSeparatorStyle = .none`, and spec 46 later rebuilds this
  window.
- `ProviderChild.init` in `PluginProcess.swift` calls
  `posix_spawn_file_actions_addchdir_np(&actions, executable.deletingLastPathComponent().path)`.
  The SDK declares the replacement `int posix_spawn_file_actions_addchdir(posix_spawn_file_actions_t *, const char * __restrict)`,
  `API_AVAILABLE(macos(26.0))`. It has the same arguments. The Swift call
  `posix_spawn_file_actions_addchdir(&actions, <String>)` typechecks for
  `arm64-apple-macos26.0`, and its `Int32` result may be ignored like the old call's.
- `README.md` under "Build and run" says: "Requires Xcode command line tools with Swift 6. No Xcode
  project; SwiftPM plus a Makefile."

## Plan
1. `Package.swift`:
   - Change the first line to `// swift-tools-version: 6.2`.
   - Change `platforms` to `[.macOS(.v26)]`.

   Decision: 6.2 is the lowest tools version that knows `.v26`. Tools version 6.4 with `.v27` was
   rejected: nothing in the app needs a macOS 27 API, and 27 would drop macOS 26 users.
2. `Resources/Info.plist`: set the `LSMinimumSystemVersion` string to `26.0`.
3. `README.md`: replace the requirement sentence with "Requires macOS 26 or later and the Xcode
   command line tools with Swift 6.2 or later." Keep "No Xcode project; SwiftPM plus a Makefile." as
   the next sentence on the same line.
4. `Sources/OddFrog/AppDelegate.swift`, the snapshot hook:
   - Replace `render(_:to:)` with `func recordWindowNumber(of window: NSWindow?, to url: URL)`. It is
     not `private`, for the same reason as today.
     - When `window` is nil or not visible, log `snapshot skipped: nothing to capture` and return.
     - Otherwise call `window.displayIfNeeded()`, so the window has drawn before the file appears.
     - Write `String(window.windowNumber)` to `url` with
       `write(to:atomically: true, encoding: .utf8)`. Write only the number, with no newline.
     - Log `snapshot window <number> written to <url.path>`. If the write throws, log
       `snapshot failed: <error>`.
   - In `snapshotPanel()`, keep the whole command handling and both delays exactly as they are.
     Change only the two delayed calls:
     - `delegate.recordWindowNumber(of: delegate.settingsWindow.window, to: logs.appendingPathComponent("odd-frog-settings.window"))`
     - `delegate.recordWindowNumber(of: delegate.panel, to: logs.appendingPathComponent("odd-frog-panel.window"))`

   Decision: the app hands over the window number and a person or script captures it. In-app
   capture options are rejected in Context.
5. `Sources/OddFrog/LauncherViewController.swift`, in `loadView()`:
   - Delete the `if #available` / `else` construct and the `root` variable.
   - Build the glass unconditionally, then set its corner radius and content view:
     `let glass = NSGlassEffectView()`, `glass.cornerRadius = Self.cornerRadius`,
     `glass.contentView = content`.
   - Delete `glass.style = .regular`, the `content.translatesAutoresizingMaskIntoConstraints = false`
     line and the `NSLayoutConstraint.activate` block that pins `content` to the root.
   - Keep `translatesAutoresizingMaskIntoConstraints = false` on the glass itself, then
     `view = glass`.

   Everything above the root selection in `loadView()` is unchanged.
6. `Sources/OddFrog/SettingsWindowController.swift`: delete the line
   `toolbar.showsBaselineSeparator = false`. Nothing else changes.
7. `Sources/OddFrogCore/PluginProcess.swift`: replace `posix_spawn_file_actions_addchdir_np` with
   `posix_spawn_file_actions_addchdir`. The arguments stay the same.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners,
  no TODOs. Leave existing comments untouched.
- The first line of `Package.swift` (`// swift-tools-version: …`) is a manifest directive, not a
  comment. Change it as step 1 says.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and
  `if … { return … }` bodies where neighbouring code uses them, one type per file for new types, and
  no new package dependencies (Apple system frameworks such as SwiftUI and Observation are fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no
  `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font,
  `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or hex
  colours and no custom fills (semantic system colours only), no corner radii, no
  `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced
  `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins,
  system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding.
  Literal numbers are allowed only where AppKit has no system value (initial window content sizes,
  the launcher panel width and its glass corner radius) — the spec must list which literals
  remain.
- The literals this spec keeps:
  - the launcher glass corner radius, `LauncherViewController.cornerRadius` = 18. `NSGlassEffectView`
    defaults to 8, and no API returns a window-sized radius.
  - the snapshot settle delays of 0.5 s and 0.4 s, which are unchanged.
- Leave `NSGlassEffectView.effectIsInteractive` unset. It needs macOS 27.
- Do not touch any other launcher layout, the Settings window layout, `CGWindowListCopyWindowInfo`
  in `WindowManager.swift` (it is not obsolete) or `NSApp.activate(ignoringOtherApps:)`. Later specs
  own those areas.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes 259 tests
- `grep -rn "CGWindowListCreateImage\|#available\|showsBaselineSeparator\|addchdir_np" Sources Plugins Tests` prints nothing
- `grep -n "NSVisualEffectView\|glass.style\|masksToBounds" Sources/OddFrog/LauncherViewController.swift` prints nothing
- `head -1 Package.swift` prints `// swift-tools-version: 6.2`
- `grep -c "macOS(.v26)" Package.swift` prints `1`
- `plutil -extract LSMinimumSystemVersion raw Resources/Info.plist` prints `26.0`
- `grep -c "Requires macOS 26 or later" README.md` prints `1`

## Manual review
1. `make run` on macOS 26 or later. The launcher opens with the hotkey and looks exactly as
   before: a rounded glass panel, the query line and the result list.
2. Run these as one command line in a terminal. The open launcher takes the keyboard, and it
   closes as soon as another window becomes key, so the commands cannot be typed one at a time.
   `pkill -USR1` opens the launcher, and `pkill -USR2` records its window number:

   ```
   rm -f ~/Library/Logs/odd-frog-query.txt; pkill -USR1 -x OddFrog; sleep 1; pkill -USR2 -x OddFrog; sleep 1; screencapture -x -o -l "$(cat ~/Library/Logs/odd-frog-panel.window)" /tmp/odd-frog-panel.png; open /tmp/odd-frog-panel.png
   ```

   - `cat ~/Library/Logs/odd-frog-panel.window` prints a number with no newline.
   - `grep snapshot ~/Library/Logs/odd-frog.log | tail -1` reads
     `snapshot window <that number> written to …/odd-frog-panel.window`.
3. The image from step 2 shows only the launcher panel, with its glass rendered, not flat. The first
   run may ask you to grant Screen Recording to the terminal. If it does, grant it and repeat step 2.
4. Run `printf '@settings plugins' > ~/Library/Logs/odd-frog-query.txt && pkill -USR2 -x OddFrog`.
   Settings opens on Plugins. Switch back to the terminal and run
   `screencapture -x -o -l "$(cat ~/Library/Logs/odd-frog-settings.window)" /tmp/odd-frog-settings.png && open /tmp/odd-frog-settings.png`.
   The image shows the Settings window.
5. Close the launcher and run `printf 'hello' > ~/Library/Logs/odd-frog-query.txt && pkill -USR2 -x OddFrog`.
   The log shows `snapshot skipped: panel not visible`, and no `.window` file is rewritten.
6. A user plugin with an executable still works, which shows that the provider still starts in its
   own directory. Copy `examples/plugins/counter` to `~/.config/odd-frog/v2/plugins/counter`, enable
   Counter in Settings › Plugins and type `Count` in the launcher. The Counter row appears, and
   Settings › Plugins shows no error for it.

## Out of scope
- The app icon, the Makefile and any `actool` step.
- `NSGlassEffectView.effectIsInteractive` and every other macOS 27 API.
- The launcher's layout, fonts, row styling, shadow and animation (spec 44), and its key handling
  (spec 45).
- The Settings window structure beyond deleting the one deprecated line (spec 46).
- The UnitRegistry `nonisolated(unsafe)` warning.
- Deleting the old `odd-frog-*.png` files that earlier runs may have left in `~/Library/Logs`.

## Open questions
none
