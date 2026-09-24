# Task: Remember where the user drags the launcher and reopen it there

## Goal
When the user drags the launcher panel somewhere, the hotkey opens it at that spot from then on,
across hides and relaunches. Until the user drags it, or after they reset it, it keeps today's
placement: centred on the screen under the pointer, a quarter of the way down. Settings › General
gets a "Launcher position" row with a Reset button, which is enabled only when a dragged position
is stored. If the stored spot is no longer on any connected screen, the panel uses today's
placement for that opening.

## Files
- Sources/OddFrog/LauncherPlacement.swift     (create)
- Sources/OddFrog/LauncherPanel.swift         (modify)
- Sources/OddFrog/GeneralPaneModel.swift      (modify)
- Sources/OddFrog/GeneralPaneView.swift       (modify)
- Sources/OddFrog/SettingsWindowController.swift (modify)
- Sources/OddFrog/AppDelegate.swift           (read — `showPanel()`, `hidePanel()`, `onHeightChange` → `panel.resize(height:)`)
- Sources/OddFrog/DocumentWindowController.swift (read — `window.setFrameAutosaveName("document")`, the precedent for keeping window placement in user defaults)

## Context
- Swift 6.2 tools, macOS 26 deployment target, SwiftPM only. The app target is `Sources/OddFrog`.
  No test target covers the app target.
- `LauncherPanel` is an `NSPanel`:
  - style `[.nonactivatingPanel, .borderless, .fullSizeContentView]`, `level = .floating`
  - `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .transient]`
  - `isMovableByWindowBackground = true`, set since the initial commit

  So it already floats over every Space and full-screen app, and the user can already drag it by
  its background: the strip around the query field, the separator, the empty-state band. What is
  missing is that `present(height:)` recomputes the frame on every show. It picks the screen whose
  `frame` contains `NSEvent.mouseLocation` (falling back to `NSScreen.main`, then
  `NSScreen.screens[0]`), sets `x = visible.midX - width / 2` and
  `y = visible.maxY - visible.height * 0.25 - height`, then calls `setFrame(_:display: true)` and
  `makeKeyAndOrderFront`. Any drag is therefore forgotten on the next show.
- `resize(height:)` runs on every keystroke that changes the result count. It keeps the top edge
  fixed (`origin.y -= newHeight - oldHeight`), so the panel's **top-centre point** (`frame.midX`,
  `frame.maxY`) is the one thing that stays put while the panel is open. That point is what gets
  stored.
- `dismiss()` calls `orderOut`. `AppDelegate.hidePanel()` calls it, and so does resigning key.
- `NSWindow.didMoveNotification` is posted for programmatic `setFrame` origin changes as well as
  for user drags, so a notification alone cannot tell them apart. The panel knows the top-centre
  it set itself. A move that ends somewhere else is a user drag. The expected point must be
  recorded **before** `setFrame` runs, in case the notification arrives synchronously inside
  `setFrame`.
- `NSRect.contains(_:)` excludes the max edge. A panel dragged flush to a screen's top has
  `maxY == screen.frame.maxY`, so the on-screen test checks the point one point below the top
  edge.
- **Storage decision:** `UserDefaults.standard`, not `settings.toml`. This is window placement
  state, like the frame autosave the Notes and Chat windows already use. Writing `settings.toml`
  on every drag would go through the settings file watcher and `applySettings` for no reason.
- `GeneralPaneModel` is `@Observable @MainActor` with `private(set)` state, and exposes
  `refreshLogin()`. `SettingsWindowController.present(...)` calls it before showing the window.
  `GeneralPaneView` is a grouped `Form` with one `Section`. Its rows use a two-line label: a title
  `Text` over a helper `Text`. `PluginsPaneView` has `LabeledContent { Button(...) } label: { Text; Text }`
  rows to mirror.

## Plan
1. **`LauncherPlacement.swift`.** A `@MainActor enum LauncherPlacement` with:
   - `static var saved: NSPoint?`, which reads a `[Double]` of exactly two elements from
     `UserDefaults.standard` under the key `"LauncherTopCenter"` and returns `nil` otherwise
   - `static func save(_ point: NSPoint)`, which writes `[Double(point.x), Double(point.y)]`
   - `static func clear()`, which removes the key
2. **`LauncherPanel`.**
   - Add `private var expectedTop: NSPoint?`.
   - In `present(height:)`, when `LauncherPlacement.saved` returns a point `top` and some
     `NSScreen.screens` element's `frame` contains `NSPoint(x: top.x, y: top.y - 1)`, the target
     frame is `x = top.x - Self.width / 2`, `y = top.y - height`. Otherwise keep today's
     computation unchanged.
   - In both `present` and `resize`, set `expectedTop` to the target frame's top-centre before
     calling `setFrame`.
   - In `init`, also observe `NSWindow.didMoveNotification` for `self`. In the handler, return
     early unless `isVisible`. Compute the current top-centre. If `expectedTop` is `nil`, or
     either coordinate differs from it by more than 0.5, call `LauncherPlacement.save` with it and
     set `expectedTop` to it.
   - Add `func resetPlacement()`, which calls `LauncherPlacement.clear()` and sets `expectedTop = nil`.
     Only `LauncherPlacement` touches user defaults.
3. **`GeneralPaneModel`.**
   - Add `private(set) var hasCustomPlacement = LauncherPlacement.saved != nil`.
   - Add `func refreshPlacement()`, which re-reads `LauncherPlacement.saved != nil`.
   - Add `func resetPlacement()`, which calls `LauncherPlacement.clear()` then `refreshPlacement()`.

   The panel reads the stored point on every `present`, so clearing it here is enough. There is no
   wiring through `AppDelegate`, and `LauncherPanel.resetPlacement()` stays for symmetry. The
   Settings window activating the app hides the panel, so it is never visible during a reset.
4. **`GeneralPaneView`.** Append a row to the existing `Section`, after the login toggle and its
   optional "Open Login Items…" button:

   `LabeledContent { Button("Reset") { model.resetPlacement() }.disabled(!model.hasCustomPlacement) } label: { Text("Launcher position"); helper }`

   The helper reads "Opens where you last dragged it." when `hasCustomPlacement` is true.
   Otherwise it reads "Opens on the screen with the pointer. Drag the launcher by its edge to
   keep it in one place."
5. **`SettingsWindowController.present(...)`:** call `general.refreshPlacement()` next to the
   existing `general.refreshLogin()`.

## Constraints
- Write no code comments of any kind: no `//`, no `///` doc comments, no `/* */`, no MARK lines.
  If a line needs explaining, rename or restructure it.
- Single-statement bodies are still braced on their own: `if x { return }`, never `if x return`.
  Do not squeeze bodies onto one line with `;`.
- Match the surrounding code: `@MainActor` on app-target types, `private(set)` model state,
  `Binding(get:set:)` or plain closures rather than `$` bindings into models, no new dependencies.
- `resize(height:)` must stay a plain, non-animated `setFrame(_:display:)`. It runs on keystrokes,
  and an animated `setFrame` blocks the main thread for the length of the animation.
- Do not change the panel's style mask, level, collection behaviour, shadow, width or animation
  behaviour.
- Independent of `.tasks/53-appearance-pane.md`. The two specs touch
  `SettingsWindowController.present(...)` in adjacent lines only, and they can land in either
  order.
- Surgical changes only; do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the existing
  `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift` `nonisolated(unsafe)` one
- `swift test` passes

## Manual review
Build and launch with `make run`. Start from a clean state with
`defaults delete com.paveltrofimov.odd-frog LauncherTopCenter`.
1. Press the hotkey. The panel opens where it does today. Settings › General › Launcher position
   shows the pointer helper, and Reset is disabled.
2. Drag the panel by the strip above the query text to the lower left of the screen. Type a
   query: the panel grows downward and its top edge stays where you dropped it. Press Esc, then
   the hotkey: it reopens at the dropped spot. Quit, relaunch, press the hotkey: same spot.
3. Type and delete queries without dragging, then reopen. The position has not drifted, which
   checks that resizes are not saved as drags.
4. With two displays, drop it on display B. Move the pointer to display A and press the hotkey:
   it opens on B. Disconnect B and press the hotkey: it opens on A in the default spot.
5. Settings › General: the helper now reads "Opens where you last dragged it." Click Reset. The
   button disables, and the next hotkey press opens in the default spot under the pointer.
6. Full-screen app and a second Space: the panel still appears over them at the saved spot.

## Out of scope
- Keeping the panel from growing past the bottom of the screen when it is placed low. The user
  chose the spot, and the panel only grows by up to eight rows.
- Panel width, the number of visible rows, and per-screen positions.
- Making more of the panel draggable, such as the query field or the rows.
- Fonts and Light/Dark. Those are spec 53.

## Open questions
none
