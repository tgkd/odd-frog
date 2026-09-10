# Task: Plugin document window — `PluginView` effects, editor window, and honest activation outcomes

First of two tasks (36–37). This one adds the reusable host piece: a plugin can return a
document view from an `activate` callback, the host shows it in its own resizable window that
stays open until the user closes it, and edits flow back to the plugin through a `save`
callback. Task 37 builds the bundled Notes plugin on top. An LLM chat view will later reuse the
same window and lifecycle with a different view kind; nothing chat-specific is added here.

## Goal
A provider's `activate` result may carry `view: {kind: "editor", id, title, text, placeholder?, save}`.
The host opens (or refocuses) one document window with a plain-text editor showing `text`,
autosaves through the `save` callback one second after typing pauses, on Cmd+S, on close, on
replacement by another document, and on quit. A save never loses the buffer: failures keep the
text on screen with Retry and Discard and Close; a plugin reload marks the document invalidated
and stops further saves while keeping the text editable and copyable. `PluginCoordinator.activate`
always completes exactly once. `swift test` passes.

## Files
- Sources/OddFrogPluginAPI/PluginView.swift                 (create — wire model)
- Sources/OddFrogPluginAPI/PluginProtocol.swift             (modify — `PluginActivation.text`, `PluginEffects.view`)
- Sources/OddFrogCore/PluginPackage.swift                   (modify — `PluginError.superseded`)
- Sources/OddFrogCore/PluginCoordinator.swift               (modify — view validation, `text`, single completion)
- Sources/OddFrogCore/DocumentSession.swift                 (create — revision/dirty state machine)
- Sources/OddFrog/DocumentWindowController.swift            (create — window, editor, status bar)
- Sources/OddFrog/AppDelegate.swift                         (modify — menu, wiring, quit flush)
- Tests/OddFrogCoreTests/DocumentSessionTests.swift         (create)
- Tests/OddFrogCoreTests/PluginTests.swift                  (modify — coordinator completion tests)
- Tests/OddFrogCoreTests/LocalProviderTests.swift           (read — `ProbeHandler` pattern for an in-process fixture)
- docs/query-plugins.md                                     (modify — `activate` row, callbacks paragraph, view section)
- docs/api2/exchanges.ndjson                                (modify — one activation with `text`, one result with `view`)
- Sources/OddFrog/SettingsWindowController.swift            (read — the `NSWindowController` construction to mirror)
- Sources/OddFrog/LauncherPanel.swift                       (read — must stay untouched; transient by design)

## Context
- Swift 6 package, `swift-tools-version: 6.0`, macOS 14 deployment target, strict concurrency.
  Tests use the `Testing` framework (`@Test`, `#expect`, `#require`), not XCTest. There is no
  Xcode project; `swift build`, `swift test`, and `make bundle` are the workflow.
- Wire types live in `Sources/OddFrogPluginAPI/PluginProtocol.swift`. `PluginActivation` has
  `actionID`, `payload: JSONValue`, `item: PluginItem`, `argument: String?` with a memberwise
  `public init` without defaults. `PluginEffects` has `notification: String?`, `refreshCatalog`,
  `refreshQuery` with defaults in its init. `JSONValue.encode(_:)` / `decode(_:)` round-trip any
  `Codable` through `PluginProtocol.encoder()/decoder()` (dates as Unix seconds).
- `PluginAction.Kind` is `copy, openURL, openPath, openApplication, reveal, execute, terminal, service, callback`
  (`PluginItem.swift`). A `callback` action reaches the provider's `activate` method.
- `PluginCoordinator` (`Sources/OddFrogCore/PluginCoordinator.swift`, `@MainActor`):
  - `authorize(_ result: PluginResult, action:)` throws
    `PluginError.message("This result belongs to a disabled or superseded plugin. Search again.")`
    when `result.generation != generation` or the package is not enabled, then runs
    `validate(action, package:)`.
  - `activate(_ result:, action:, argument:, completion:) -> UUID` runs a task: `authorize`, then
    either `perform("activate", …, timeout: nil, activated: true)` for `.callback` (input is a
    `PluginActivation`) or `services.invoke` for `.service`; decodes `PluginEffects`; applies
    `refreshCatalog`/`refreshQuery`; calls `completion(.success)`. Today it **drops the outcome**
    in two places: `guard token == generation else { return }` after the operation returns, and
    `catch { if !(error is CancellationError), token == generation { completion(.failure(error)) } }`.
    `stop()` rotates `generation` and cancels every task in `actionTasks`; `reload` calls `stop()`;
    `cancelActions()` cancels them without rotating the generation.
  - `validate(_ action:, package:)` is private and throws `RPCError("protocol", …)` for a
    `.callback` on a declarative package or with an empty `value`.
  - `LocalProvider.request` (`Sources/OddFrogCore/LocalProvider.swift`) awaits the handler directly
    and ignores its `timeout` parameter; cancellation is cooperative. This task keeps that
    narrower guarantee: `activate` completes once the operation returns or throws, not earlier.
- `PluginError` (`PluginPackage.swift`) is `enum PluginError: Error, CustomStringConvertible { case message(String) }`.
- `AppDelegate` (`Sources/OddFrog/AppDelegate.swift`):
  - `installMainMenu()` builds an Edit menu only; `NSApp.mainMenu` has an empty first item and Edit.
  - `runPluginAction(_:argument:secondary:)` authorizes, and for `.callback`/`.service` calls
    `plugins.activate` with a completion that posts `effects.notification` through
    `notifier.post(title:body:log:)`, then `executor.recordPlugin(result)` (frecency), and on
    failure `report(String(describing: error))`. `report` sets `status.lastFailure` and posts a
    failure notification. It also assigns `status.onCancelAction = { plugins.cancelActions() }`.
  - `applicationWillTerminate` calls `plugins.stop()`; there is no `applicationShouldTerminate`.
  - `reloadPlugins()` is the only caller of `plugins.reload`; `wirePlugins()` sets
    `executor.onPluginAction` to `runPluginAction`.
- `SettingsWindowController` constructs an `NSWindow` with
  `styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]`,
  `isReleasedWhenClosed = false`, `center()`, then `super.init(window:)`, and presents with
  `NSApp.activate(ignoringOtherApps: true)` + `showWindow(nil)` + `makeKeyAndOrderFront(nil)`.
- The launcher panel (`LauncherPanel`) is a non-activating floating panel that hides when it
  resigns key, and `AppDelegate.wirePanel` hides it before every `executor.run`. So an activation's
  effects arrive after the launcher is already hidden. The document window is a separate normal
  window precisely so the launcher keeps that behaviour.
- `Notifier.post(title:body:log:)` and `Log.write(_:)` exist for reporting.
- Tests in `Tests/OddFrogCoreTests/PluginTests.swift` build coordinators from Python fixtures
  (`fixture(_:source:)`, `manifest(id:mode:extra:)`, `echo`, `waitUntil`). A bundled in-process
  provider can be tested without Python: set `coordinator.builtins["fixture"] = { handler }` and
  give `PluginDiscovery` a `PluginPackage(manifest:directory:bundled: true)`; `LocalProviderTests.swift`
  has the `ProbeHandler` actor shape to copy. `BundledPackageTests.swift:94` and `AppDelegate` are the
  only current `activate` callers; neither depends on swallowed outcomes.
- `publishedEnvelopeFixturesRoundTrip` decodes every line of `docs/api2/exchanges.ndjson` as a
  `PluginEnvelope` and re-encodes it, so new fixture lines must be valid envelopes.
- Verified today from the repo root: `swift test` passes with 156 tests (core 91, Calendar 8,
  Reminders 16, bundled features 41) and `swift build` is warning-free apart from a pre-existing
  unused `range` in `CalendarProvider`.

## Plan
1. `Sources/OddFrogPluginAPI/PluginView.swift` (create):
   `public struct PluginView: Codable, Sendable, Hashable` with nested
   `public enum Kind: String, Codable, Sendable { case editor }`, and fields `kind: Kind`,
   `id: String`, `title: String`, `text: String`, `placeholder: String?`, `save: PluginAction`.
   Memberwise `public init(kind: Kind = .editor, id:, title:, text: String = "", placeholder: String? = nil, save:)`.
2. `PluginProtocol.swift`: add `public var text: String?` to `PluginActivation` as the last init
   parameter with default `nil`; add `public var view: PluginView?` to `PluginEffects` as the last
   init parameter with default `nil`. Existing JSON without these keys must still decode (they are
   optionals, so synthesized `Codable` already does this).
3. `PluginPackage.swift`: add `case superseded` to `PluginError`; its description is the existing
   sentence "This result belongs to a disabled or superseded plugin. Search again.".
4. `PluginCoordinator.swift`:
   - `authorize` throws `PluginError.superseded` instead of `.message(…)` for the stale/disabled case.
   - `activate` gains `text: String? = nil` before `completion` and passes it into
     `PluginActivation`. Update the two existing call sites (`AppDelegate.runPluginAction`,
     `BundledPackageTests`) only if the default does not cover them (it does; no edit expected).
   - After decoding `PluginEffects`, if `effects.view` is non-nil: require
     `view.save.kind == .callback`, non-empty `view.id` and `view.title`, and run
     `validate(view.save, package:)`; otherwise throw `RPCError("protocol", "Invalid document view.")`.
   - Exactly one completion per call. Success path: `guard token == generation else { completion(.failure(PluginError.superseded)); return }`.
     Catch path: `if token != generation { completion(.failure(PluginError.superseded)) } else { completion(.failure(error)) }`
     — generation change wins over `CancellationError` because reload cancels the task itself.
     The `defer { actionTasks[id] = nil }` stays.
5. `Sources/OddFrogCore/DocumentSession.swift` (create): a pure, `@MainActor public final class DocumentSession`
   that the window drives and tests cover. State: `let pluginID: String`, `let pluginName: String`,
   `let viewID: String`, `let result: PluginResult`, `let save: PluginAction`,
   `private(set) var title: String`, `private(set) var text: String`,
   `private(set) var revision = 0`, `private(set) var savedRevision = 0`,
   `private(set) var inFlight: Int?`, `private(set) var invalidated = false`,
   `private(set) var error: String?`. API:
   - `init(view: PluginView, result: PluginResult, pluginName: String)` seeds `title`/`text` from the view.
   - `var isDirty: Bool { revision != savedRevision }`, `var canSave: Bool { isDirty && inFlight == nil && !invalidated }`.
   - `func edit(_ text: String)`: if `text != self.text`, store it, `revision += 1`, and clear a
     non-terminal `error`.
   - `func beginSave() -> (revision: Int, text: String)?`: returns nil unless `canSave`; otherwise
     sets `inFlight = revision` and returns the snapshot.
   - `func acknowledge(revision: Int, title: String?)`: ignores a revision that is not `inFlight`;
     otherwise clears `inFlight`, sets `savedRevision = revision` (so later edits keep it dirty),
     updates `title` when non-nil, clears `error`.
   - `func fail(revision: Int, message: String, terminal: Bool)`: ignores a revision that is not
     `inFlight`; otherwise clears `inFlight`, sets `error = message`, and `invalidated = terminal`.
   - `func invalidate(message: String)`: sets `invalidated = true`, `error = message`, clears `inFlight`.
6. `Sources/OddFrog/DocumentWindowController.swift` (create): `@MainActor final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate`.
   - Window: `NSWindow(contentRect: 720×520, styleMask: [.titled, .closable, .resizable, .miniaturizable])`,
     `minSize` 420×300, `isReleasedWhenClosed = false`, `setFrameAutosaveName("document")`,
     `delegate = self`. Not floating, no custom level, standard title bar showing `session.title`.
   - Content: an `NSScrollView` with an `NSTextView` filling the window above a 28 pt status bar.
     Text view settings: `isRichText = false`, `usesFontPanel = false`, `importsGraphics = false`,
     `allowsUndo = true`, `font = NSFont.systemFont(ofSize: 14)`, `textContainerInset = 12×12`,
     `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`,
     `isAutomaticTextReplacementEnabled`, `isAutomaticLinkDetectionEnabled`,
     `isAutomaticSpellingCorrectionEnabled` all `false`, `delegate = self`. Placeholder: an
     `NSTextField(labelWithString:)` in secondary label colour and the same font, overlaid at the
     text container inset and hidden whenever the buffer is non-empty or the view has no `placeholder`.
   - Status bar: a 12 pt secondary-colour label on the left, and two `NSButton`s on the right
     titled "Retry" and "Discard and Close", both hidden unless `session.error != nil`; "Retry" is
     hidden as well when `session.invalidated`. The label shows `session.error ?? ""`.
   - Public API used by `AppDelegate`:
     `var performSave: ((DocumentSession, Int, String, @escaping (Result<PluginEffects, any Error>) -> Void) -> Void)?`,
     `func present(_ view: PluginView, result: PluginResult, pluginName: String)`,
     `func pluginsDidReload()`, `func prepareToTerminate(_ reply: @escaping (Bool) -> Void) -> Bool`.
   - `present`: if a session with the same `pluginID` and `viewID` is open, just activate the app
     and `makeKeyAndOrderFront` (never touch the buffer). Else if a dirty session is open, flush it
     first (see below): on success swap to the new session; on failure keep the current one,
     focus it, and drop the new view. Else swap directly. Swapping sets the text view's string,
     resets undo (`undoManager?.removeAllActions()`), sets `window.title`, refreshes the status bar,
     then activates and orders front.
   - Editing: `textDidChange` calls `session.edit(textView.string)`, refreshes the status bar, and
     restarts a one-second `Timer` that calls `flush(reason: .autosave)`.
   - `flush(reason:completion:)`: cancel the timer. If `session.beginSave()` returns nil, complete
     `true` when the session is clean and `false` otherwise (a save already in flight, or an
     invalidated session); when a save is in flight for a close/quit/replace reason, remember the
     reason and re-run the flush when that save settles. Otherwise call
     `performSave(session, revision, text)`; on `.success(effects)` call
     `session.acknowledge(revision:title: effects.view?.title)`, set `window.title`, and never
     replace the text view's contents or selection; if the session became dirty meanwhile and the
     reason was close/quit/replace, flush again; else complete with `!session.isDirty`.
     On `.failure(error)`: `terminal = (error is PluginError superseded)`; message is
     `"\(pluginName) was reloaded. Your text is kept here; copy it or choose Discard and Close."`
     for terminal, otherwise `"Save failed: \(error)"`; call `session.fail(revision:message:terminal:)`,
     refresh the status bar, complete `false`. A `CancellationError` is reported like any other
     failure (the user cancelled from the status menu; the text stays).
   - Close/quit freeze: while a flush with reason close, quit, or replace is running, set
     `textView.isEditable = false`; restore it when the flush settles either way.
   - `windowShouldClose`: return true when there is no session, the session is clean, or
     "Discard and Close" requested this close. When the session is invalidated and dirty, return
     false and show the status bar (only "Discard and Close" is offered). Otherwise start
     `flush(reason: .close)` and return false; on success call `window.close()`. After a failure
     the window stays open with the status bar showing the buttons.
   - "Retry" runs `flush(reason: .close)` again. "Discard and Close" drops the session and closes
     without saving.
   - Keys: `textView(_:doCommandBy:)` handles `cancelOperation(_:)` by `window?.performClose(nil)`
     and returns true. `@objc func saveDocument(_ sender: Any?)` runs `flush(reason: .manual)`;
     it is reached through the responder chain from the File menu (step 7).
   - `pluginsDidReload()`: if a session is open and not yet clean and invalidated, call
     `session.invalidate(message:)` with the reload message above, cancel the autosave timer, and
     refresh the status bar. A clean session is left alone but also invalidated (the next edit
     must not autosave into a superseded provider).
   - `prepareToTerminate(reply)`: returns false when no session is dirty and nothing is in flight
     (caller terminates immediately). Otherwise starts `flush(reason: .quit)`, arms a two-second
     timer, and returns true; the first of {flush success → `reply(true)`, flush failure → `reply(false)`,
     timer → `reply(false)` with the status bar showing "Save did not finish. Retry or Discard and
     Close, then quit again."} wins and disarms the others. A timeout never starts a second write;
     the in-flight save is left to settle and `acknowledge` still applies when it does.
7. `AppDelegate.swift`:
   - `installMainMenu()`: add a "File" menu before Edit with "Save" (`saveDocument:`, key `s`) and
     "Close" (`performClose:`, key `w`).
   - Add `private lazy var documents = DocumentWindowController()`. In `wirePlugins()` set
     `documents.performSave = { [weak self] session, revision, text, completion in
       _ = self?.plugins.activate(session.result, action: session.save, argument: nil, text: text, completion: completion) }`.
     This path never records frecency and never touches `status.onCancelAction`.
   - `runPluginAction` success path: after the notification, if `effects.view` is non-nil call
     `documents.present(view, result: result, pluginName: package.manifest.name)` where `package`
     is the value returned by `plugins.authorize` (already called at the top; keep its result).
     Failure path: `if error is CancellationError { return }` before `report(...)` so status-menu
     cancellation stays silent; `PluginError.superseded` is reported like other failures.
   - `reloadPlugins()`: call `documents.pluginsDidReload()` right after `plugins.reload(...)`.
   - Add `func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply`:
     `documents.prepareToTerminate { ok in NSApp.reply(toApplicationShouldTerminate: ok) } ? .terminateLater : .terminateNow`.
8. Tests.
   - `Tests/OddFrogCoreTests/DocumentSessionTests.swift` (create, `@MainActor struct`): a view
     seeds title/text and is clean; `edit` makes it dirty and `beginSave` returns the snapshot and
     blocks a second `beginSave`; an edit during an in-flight save keeps the session dirty after
     `acknowledge` and `beginSave` then returns the newer text; acknowledging a revision that is
     not in flight is ignored; `fail(terminal: false)` allows `beginSave` again; `fail(terminal: true)`
     and `invalidate` make `canSave` false while `text` and `isDirty` are preserved; `acknowledge`
     with a title updates `title`.
   - `PluginTests.swift` (modify): add `@Test @MainActor func activateAlwaysCompletes()` using an
     in-process `ProviderHandler` fixture registered through `coordinator.builtins` on a bundled
     `PluginPackage` whose manifest is `mode = "persistent"`, `activation = "live"`. The handler's
     `activate` awaits a `Task.sleep(for: .seconds(5))` guarded by cancellation. Assert:
     (a) `cancelActions()` completes with `CancellationError`; (b) `reload` with the package
     disabled completes with `PluginError.superseded`; (c) an `activate` returning
     `{"view": {"kind": "editor", "id": "n1", "title": "T", "text": "x", "save": {"kind": "openURL", "value": "https://x"}}}`
     completes with an `RPCError` whose code is `protocol`, and the same with a `callback` save
     completes with `.success` whose `view?.id == "n1"`; (d) the activation input the handler
     received carries `text` when `activate(..., text: "body", ...)` was called.
9. `docs/query-plugins.md`: in the methods table change the `activate` row to
   "actionID, payload, item, optional argument, optional text | Effects object, optionally with a view".
   Extend the callbacks paragraph: effects are
   `{notification?, refreshCatalog, refreshQuery, view?}`; add a short "## Document views"
   section after it describing `view` (`kind` is `editor`; `id` is plugin-scoped and stable;
   `save` must be a `callback` and is invoked with the editor text in `text`; the host autosaves
   after a one-second pause, on Cmd+S, close, replacement, and quit; a `view` returned from a
   save updates the window title only; the host never re-sends drafts after a reload).
   `docs/api2/exchanges.ndjson`: append an `activate` request line with `"text":"hello"` in
   `input` and a result line `{"apiVersion":2,"id":"open","result":{"refreshCatalog":false,"refreshQuery":true,"view":{"kind":"editor","id":"n1","title":"Note","text":"hello","save":{"kind":"callback","value":"save","payload":{"id":"n1"}}}}}`.

Approach notes: effects carry the view (one extra round trip on Enter) rather than an inline
`view` action kind, because inline views would put full document bodies into every query row
under the 50-row and 4 MiB limits. The save callback is deliberately not a generic "submit": a
future chat view gets its own kind and its own send action, so autosave can never post a draft to
a model. The completion fix lives in the coordinator so every caller gets an honest outcome
instead of the window guessing with timers.

## Constraints
- No comments, doc comments, or section banners in new or edited code. Existing comments in
  `PluginCoordinator.swift` (`// Retain visible rows…`, `/// Cached catalog ranking…`) stay.
- Always brace conditionals and returns; no bare single-expression `if` without braces.
- One type per file in `Sources/OddFrog` and `Sources/OddFrogCore` (private helper views nested
  inside a class, as `LauncherViewController.HairlineView` does, are fine).
- Swift 6 strict concurrency: wire types are `Sendable`; `DocumentSession` and the controller are
  `@MainActor`; no `@unchecked Sendable` additions.
- Wire format stays additive: every new JSON field is optional; existing fixture lines in
  `docs/api2/exchanges.ndjson` must decode unchanged.
- `OddFrogCore` must not import AppKit; `DocumentSession` is Foundation-only.
- Do not change `LauncherPanel`, `LauncherViewController`, or the launcher's dismissal rules.
- No note or document text in `Log.write` or notifications.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds from the repo root.
- `swift test` passes from the repo root; the existing 156 tests still pass and the new
  `DocumentSessionTests` and `activateAlwaysCompletes` tests are included.
- `make bundle` exits 0.
- Manual, after `scripts/release.sh` (or `make run`): the app launches, the File menu shows Save
  and Close, and quitting with no document open is immediate. The full editor flow is checked in
  task 37 once a plugin returns a view.

## Out of scope
- The Notes plugin itself (task 37).
- Chat/conversation view kinds, streaming, or any field reserved for them.
- Multiple simultaneous document windows.
- Enforcing `timeout` in `LocalProvider` or making `activate` complete before a handler returns.
- Changing how `runPluginAction` records frecency for ordinary actions.

## Open questions
none
