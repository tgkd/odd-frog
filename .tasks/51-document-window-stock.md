# Task: Document window on stock AppKit — no bottom bar, sheets and subtitle for save problems, find bar

## Goal
The plugin document window (Notes) is a stock plain-text editor that fills the window. It uses
`NSTextView.scrollablePlainDocumentContentTextView()` with the `.body` font, default insets, the
system text-substitution preferences, and the find bar (⌘F) with incremental search. The hand-built
bottom bar and the "Start writing…" overlay are gone. A failed autosave or ⌘S shows its error as
the window subtitle. A save that fails while closing, replacing the document or quitting, a quit
whose save does not finish in time, and a plugin reload that strands unsaved text all present an
`NSAlert` sheet. The sheet offers Save and Close, Keep Editing, or Discard and Close, as the case
allows. Esc no longer closes the window.

## Files
- Sources/OddFrog/DocumentWindowController.swift            (modify)
- docs/query-plugins.md                                     (modify — Editor section)
- Sources/OddFrogCore/DocumentSession.swift                 (read — save state machine; stays unchanged)
- Sources/OddFrog/AppDelegate.swift                         (read — `applicationShouldTerminate`, `reloadPlugins`, `runPluginAction`, File › Save; stays unchanged)
- Plugins/Notes/Sources/NotesPluginCore/NotesProvider.swift (read — the only editor-view producer; sends `placeholder: "Start writing…"`; stays unchanged)
- Plugins/Notes/Sources/NotesPluginCore/NoteStore.swift     (read — atomic writes into the plugin storage directory, used in Manual review)
- Tests/OddFrogCoreTests/DocumentSessionTests.swift         (read — covers `DocumentSession`; stays unchanged)

## Context
- Preconditions:
  - Specs 43–50 have landed. The package targets macOS 26, and `swift build` has one warning,
    `nonisolated(unsafe)` in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`.
  - Spec 45 built the standard main menu:
    - File keeps Save ⌘S (`saveDocument:`) and Close ⌘W.
    - Edit has a Find submenu whose items send `performTextFinderAction(_:)` (Find… ⌘F and
      friends), plus Spelling and Grammar and Substitutions submenus. `NSTextView` implements and
      validates those actions itself.
  - No earlier spec touches `DocumentWindowController.swift`.
- The app runs with activation policy `.accessory` (`main.swift`; `LSUIElement` in `Info.plist`),
  so the main menu is not shown in the menu bar. Its key equivalents still work in the app's
  windows.
- `DocumentWindowController` today:
  - It is an `NSWindowController, NSWindowDelegate, NSTextViewDelegate`, with a titled, closable,
    resizable, miniaturizable window: content 720×520, `minSize` 420×300, autosave name
    "document".
  - It builds its own `NSScrollView` and `NSTextView`: 720×492 frame, hand-set sizing, 14 pt
    system font, 12×12 `textContainerInset`, and quote, dash, replacement, link and
    spelling-correction substitution all forced off.
  - Over the text it lays a `placeholderLabel` showing `PluginView.placeholder` while the buffer is
    empty.
  - Below the text is a 28 pt `bar` with `statusLabel` (12 pt), and small `.rounded` Retry and
    "Discard and Close" buttons.
  - `textView(_:doCommandBy:)` turns Esc (`cancelOperation`) into `performClose`.
  - Public API used by `AppDelegate`: `performSave`, `present(_:save:result:pluginName:)`,
    `pluginsDidReload()`, `prepareToTerminate(_:)` and `@objc func saveDocument(_:)`.
- Save machinery, which stays:
  - `Reason` is one of `.autosave`, `.manual`, `.close`, `.quit` or `.replace`, and `blocking` is
    true for close, quit and replace.
  - `flush(reason:completion:)` starts a save through `performSave`. While a blocking flush runs,
    it makes the text view non-editable. A blocking reason that meets an in-flight save is queued
    in `pending`.
  - `settle(...)` acknowledges or fails the revision. The failure message is the reload message
    for `PluginError.superseded` and "Save failed: \(error)" otherwise.
  - `DocumentSession.edit` clears `error` unless the session is invalidated.
  - `acknowledge` clears `error`.
  - `invalidate(message:)` sets `invalidated`, sets `error` and clears `inFlight`.
  - `isDirty` is `revision != savedRevision`.
- Today's bottom bar shows `notice ?? session.error`. Retry is hidden when there is no message or
  the session is invalidated, and Discard and Close is hidden when there is no message. Every state
  it shows:
  1. Autosave failure (1 s after typing stops) or ⌘S failure: "Save failed: …" with Retry and
     Discard and Close. Retry runs `flush(reason: .close)` and closes the window on success.
     Typing hides the bar, because `edit` clears the error and `textDidChange` clears `notice`.
  2. Close failure (the close button or ⌘W reaches `windowShouldClose`, and the `.close` flush
     fails): the same bar, and the window stays open.
  3. Replacement failure: another document is opened while this one is dirty, and the `.replace`
     flush fails. The same bar is shown, the old document is re-activated, and the new request is
     dropped.
  4. Quit failure: `prepareToTerminate` starts a `.quit` flush, the flush fails, and termination
     is cancelled with `reply(false)`. The same bar is shown.
  5. Quit timeout: after 2 s, `notice` becomes "Save did not finish. Retry or Discard and Close,
     then quit again." with both buttons, and termination is cancelled.
  6. Plugin reload: `pluginsDidReload` invalidates the session. Its error becomes "\(pluginName)
     was reloaded. Your text is kept here; copy it or choose Discard and Close.", with Discard and
     Close only. It stays while typing. The same message results when a save fails with
     `PluginError.superseded`.
  7. Closing an invalidated, dirty document: `windowShouldClose` refreshes the bar with message 6
     and refuses to close.
  8. Quitting with an invalidated, dirty document: the `.quit` flush completes false at once, and
     termination is cancelled with no new message.
  9. No save handler: "Save failed: This document has no way to save.", handled like 1–4 for the
     reason at hand.

  No "Saving…" progress state exists.
- The quit timer does not fire, which is verified:
  - While `applicationShouldTerminate` has returned `.terminateLater`, AppKit runs the main run
    loop in `NSModalPanelRunLoopMode`.
  - Timers made with `Timer.scheduledTimer` are in the default mode only and do not fire there.
    Timers added to `RunLoop.main` for `.common` modes do fire, and main-actor tasks (which carry
    the save completion) run.
  - So today's two-second quit timer never fires while a quit is pending.
- Other verified facts:
  - `NSTextView.scrollablePlainDocumentContentTextView()` returns a borderless `NSScrollView` with
    a vertical scroller, `autohidesScrollers = false`, `findBarPosition` above the content, and
    `drawsBackground = false`. Its document view is an `NSTextView` that is resizable in width and
    tracks it.
  - That text view starts with `isRichText = false`, `importsGraphics = false`,
    `usesFontPanel = false`, `usesFindBar = true`, `isIncrementalSearchingEnabled = false`,
    `allowsUndo = false`, font Helvetica 12, and a `textContainerInset` of (0, 0). Its
    substitution flags follow the user's System Settings.
  - `NSFont.preferredFont(forTextStyle: .body)` is 13 pt.
  - `NSWindow.subtitle` shows in the titlebar as "Title – Subtitle" when the window has no toolbar,
    and an empty string removes it.
  - NSAlert:
    - The first added button gets Return, and only a button titled "Cancel" gets Esc
      automatically.
    - `keyEquivalent` and `hasDestructiveAction` are supported on alert buttons.
    - `beginSheetModal(for:completionHandler:)` returns `.alertFirstButtonReturn`,
      `.alertSecondButtonReturn` or `.alertThirdButtonReturn` by the order the buttons were added.
  - Inside the `beginSheetModal` completion handler, `window.attachedSheet` is still the ending
    alert. A sheet begun from inside the handler is queued by AppKit and appears once the first
    one has gone.
  - Calling `window.close()` from inside the handler closes the window, and showing the window
    again later brings back no leftover sheet.
  - Calling `NSApp.reply(toApplicationShouldTerminate: false)` before `applicationShouldTerminate`
    has returned `.terminateLater` puts the app back in the default run-loop mode. A sheet begun
    right after that reply appears and works. State 8 takes this path, because its `.quit` flush
    completes synchronously.
- The Notes plugin stores notes as `<id>.txt` files, written atomically into
  `~/Library/Application Support/odd-frog/v2/plugins/notes/`. A read-only directory makes every
  save fail.
- Remaining literal numbers after this task: the window's initial content size 720×520 and
  `minSize` 420×300. The 1 s autosave delay and the 2 s quit timeout are timing, not styling.

## Plan
1. Editor:
   - Replace the two stored views with `private let scroll = NSTextView.scrollablePlainDocumentContentTextView()`
     and `private let textView: NSTextView`. Assign the text view in `init()` from
     `scroll.documentView as! NSTextView` before `super.init(window:)`.
   - In `buildContent()`, keep only these settings on the text view: `allowsUndo = true`,
     `font = NSFont.preferredFont(forTextStyle: .body)`, `usesFindBar = true`,
     `isIncrementalSearchingEnabled = true` and `delegate = self`.
   - Then set `window?.contentView = scroll`.
   - Delete:
     - the plain-text flags that the factory already sets,
     - `textContainerInset`,
     - the five `isAutomatic…Enabled = false` lines, so the system substitution preferences apply
       and the Edit › Substitutions menu can toggle them,
     - the manual sizing lines and every scroll-view setting,
     - the placeholder label,
     - the status bar and its buttons, with all their constraints.
   - Rejected: keeping the hand-assembled scroll view and text view, which the factory configures
     identically.
2. Delete the `placeholder` property and every use of it. The document window no longer shows
   `PluginView.placeholder`: `NSTextView` has no placeholder API, and a stock document editor shows
   none.
   - The Notes plugin keeps sending the field. It stays part of the view contract, and chat still
     uses it.
   - Rejected: removing it from `NotesProvider`, which would change a plugin and its test for no
     visible gain.
3. Delete `notice`, `statusLabel`, `retryButton`, `discardButton` and `textView(_:doCommandBy:)`.
   With the last one gone, Esc gets `NSTextView`'s stock behaviour (completion), and ⌘W closes.
   `refresh()` becomes `window?.subtitle = session?.error ?? ""`.
4. Add `private var choosing = false` and `private func presentChoices(_ detail: String?)`:
   - Do nothing unless `window` and `session` exist and `choosing` is false. When a sheet is
     already up, the subtitle still carries the latest error.
   - Set `choosing = true` just before `beginSheetModal`. The completion handler's first statement
     sets `choosing = false`, before it acts on the chosen button.
   - Rejected: guarding on `window.attachedSheet == nil`. Inside the completion handler the ending
     alert is still attached (Context). A Save and Close that fails synchronously would then show
     nothing. That happens when there is no save handler, or when the session was invalidated
     while the sheet was up. With the flag, AppKit queues the second sheet and shows it once the
     first has gone.
   - Invalidated session:
     - `messageText = "\(session.pluginName) was reloaded"`.
     - `informativeText = "Changes to “\(session.title)” can no longer be saved. Copy any text you want to keep, then choose Discard and Close."`
     - Buttons: "Keep Editing" (first, so Return), then "Discard and Close" with
       `hasDestructiveAction = true`.
   - Otherwise:
     - `messageText = "“\(session.title)” was not saved"`.
     - `informativeText = detail ?? session.error ?? ""`.
     - Buttons: "Save and Close" (first, so Return), then "Keep Editing" with
       `keyEquivalent = "\u{1b}"` so Esc picks it, then "Discard and Close" with
       `hasDestructiveAction = true`.
   - `beginSheetModal(for: window)`:
     - Save and Close calls `saveAndClose()`.
     - Discard and Close calls `discardAndClose()`.
     - Keep Editing does nothing, so the window and subtitle stay as they are.
   - Decide the button meaning from the session state captured when the sheet was built, not from
     the state when it is dismissed.
5. Rename `retry()` to `private func saveAndClose()` (no longer `@objc`). It runs
   `flush(reason: .close)`, then calls `window?.close()` on success, or `presentChoices(nil)` on
   failure. `discardAndClose()` loses its `@objc`, `notice` and `placeholder` lines, and keeps the
   rest.
6. Map each state from Context to the new UI:
   - State 1, autosave or ⌘S failure: subtitle only. `settle` already stores the error and calls
     `refresh()`. The next edit clears it, and the next autosave or ⌘S retries.
     - Rejected: a sheet for ⌘S failures. Nothing needs deciding, and a sheet would interrupt
       typing.
   - State 2, and state 7 through the same method: `windowShouldClose` returns true for no session
     or a clean one. For an invalidated, dirty session it calls `presentChoices(nil)`. Otherwise it
     calls `saveAndClose()`. Both paths return false.
   - State 3: in `present`, the `.replace` failure branch calls `activateWindow()` and then
     `presentChoices(nil)`. The requested document is still dropped, as today.
   - States 4, 5 and 8:
     - `answerQuit(_:message:)` becomes `answerQuit(_ ok: Bool, detail: String?)`. It calls
       `reply(ok)` first, and then, when `ok` is false, `activateWindow()` and
       `presentChoices(detail)`.
     - The flush completion passes `detail: nil`. The timer passes "Saving did not finish in time,
       so Odd Frog did not quit." The user then saves or discards, and quits again.
     - Create the quit timer with `Timer(timeInterval: 2, repeats: false)` and add it with
       `RunLoop.main.add(_:forMode: .common)`, keeping the `MainActor.assumeIsolated` body. As
       Context shows, a `scheduledTimer` never fires while a quit is pending.
     - Rejected: keeping the termination pending while the sheet is up. `quitReply` would stay
       open until the user chose a button. Until then the app would sit in a pending quit, where
       default-mode timers such as the autosave never fire.
   - State 6:
     - Change `reloadMessage` to "\(session.pluginName) was reloaded. Changes are no longer saved.",
       which is short enough for a subtitle.
     - In `pluginsDidReload`, after `refresh()`, call `presentChoices(nil)` when `session.isDirty`
       and `window?.isVisible == true`. A clean or hidden document only gets the subtitle. Closing
       or quitting later still asks, through state 7 or 8.
     - Rejected: a sheet on every reload. Reloads also come from the package file watcher and
       Settings toggles, and a clean document loses nothing.
     - Rejected: the subtitle only. Unsaved text would silently stop being saved.
   - State 9: covered by the paths above.
7. Leave `window.isDocumentEdited` unset. Autosave runs one second after each pause, so the dot in
   the close button would flicker while typing.
8. `docs/query-plugins.md`, Editor section:
   - Replace "`title` is the window title, `text` is the initial buffer, and `placeholder` is shown
     while the buffer is empty." with "`title` is the window title and `text` is the initial
     buffer; the document window does not display `placeholder`."
   - Replace "A failed save keeps the text on screen with Retry and Discard and Close." with "A
     failed autosave or Cmd+S shows the error as the window subtitle. When a save fails on close,
     on replacement or on quit, or a quit's save takes longer than two seconds, the quit is
     cancelled if one was pending, the text stays on screen, and a sheet offers Save and Close,
     Keep Editing, and Discard and Close."
   - After the sentence about reloads keeping the text editable and copyable, add "The subtitle
     says so, and a sheet offering Keep Editing or Discard and Close appears whenever unsaved text
     is at stake."

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners,
  no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and
  `if … { return … }` bodies where neighbouring code uses them, one type per file for new types,
  and no new package dependencies (Apple system frameworks such as SwiftUI and Observation are
  fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no
  `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font,
  `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or
  hex colours and no custom fills (semantic system colours only), no corner radii, no
  `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced
  `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins,
  system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding.
  Literal numbers are allowed only where AppKit has no system value (initial window content sizes,
  the launcher panel width and its glass corner radius) — the spec must list which literals
  remain.
- The only numeric literals left in `DocumentWindowController.swift` are the sizes and delays
  listed at the end of Context.
- Keep the save state machine: `Reason`, `flush`, `settle`, `pending`, the 1 s autosave and the
  2 s quit deadline. Change only what Plan names. `DocumentSession.swift`, `AppDelegate.swift`,
  the Notes plugin and `PluginView` stay unchanged. Keep the signatures of every member
  `AppDelegate` calls.
- Leave `NSApp.activate(ignoringOtherApps: true)` in `activateWindow()` as it is. Do not adopt
  `NSDocument`, and do not set `isDocumentEdited`.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed)
- `grep -n "placeholder\|notice\|statusLabel\|retryButton\|discardButton\|cancelOperation\|scheduledTimer(withTimeInterval: 2\|systemFont(ofSize\|isAutomatic\|textContainerInset\|controlSize\|bezelStyle\|isDocumentEdited" Sources/OddFrog/DocumentWindowController.swift` prints nothing
- `grep -n "scrollablePlainDocumentContentTextView\|isIncrementalSearchingEnabled = true\|forMode: .common\|subtitle" Sources/OddFrog/DocumentWindowController.swift` prints at least four lines

## Manual review
1. `make run`, type `note`, and press Return on "New note". The window is a plain editor filling
   the window, with no bottom bar and no "Start writing…" hint. The text is 13 pt system text.
2. Type a few lines, then press ⌘F. The find bar appears above the text, matches highlight as you
   type, and ⌘G steps through them. Esc in the text no longer closes the window, and ⌘W closes it.
3. With "Use smart quotes and dashes" turned on in System Settings › Keyboard › Text Input,
   typing `"hi"` produces curly quotes. The text view's context menu › Substitutions shows Smart
   Quotes checked and can turn them off for this window.
4. Open a note, then run `chmod a-w ~/Library/Application\ Support/odd-frog/v2/plugins/notes`.
   Type a character and wait a second. The title bar reads "<title> – Save failed: …", and no
   sheet appears. Typing another character clears it until the next autosave fails again.
5. With the directory still read-only, press ⌘W. A sheet titled "“<title>” was not saved" offers
   Save and Close, Keep Editing, and Discard and Close.
   - Esc chooses Keep Editing: the sheet closes, the text is intact, and the subtitle shows the
     error.
   - Press ⌘W again and choose Save and Close. The save fails and the sheet comes back.
   - Run `chmod u+w` on the directory and choose Save and Close. The window closes, and reopening
     the note shows the text.
6. Make the directory read-only again, type in a note, and choose Quit Odd Frog from the status
   menu (or press ⌘Q with the note window key). The app keeps running, the note window comes forward, and the same sheet appears.
   Discard and Close closes the window. Quitting again then quits at once. Restore write access
   afterwards.
7. Type in a note, and within a second choose Reload Plugins from the status menu. The subtitle
   reads "Notes was reloaded. Changes are no longer saved.", and a sheet offers Keep Editing
   (Return) and Discard and Close. Keep Editing leaves the text editable and copyable. ⌘W then
   shows that sheet again.
8. Open a note, leave it unchanged, and reload plugins. Only the subtitle changes, and ⌘W closes
   the window at once.

## Out of scope
- `DocumentSession`, the Notes plugin, and the `PluginView` editor contract, including dropping
  `placeholder` from it.
- Refocusing the same note after a reload, which still shows the invalidated document. That is a
  follow-up.
- `NSDocument` adoption, versions, and the close-button dirty dot.
- The Edit menu itself (spec 45), and the chat and month windows.

## Open questions
none
