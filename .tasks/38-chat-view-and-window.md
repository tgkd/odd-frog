# Task: Chat view kind — `PluginView.chat`, streaming `messageDelta` events, and the host chat window

First of two tasks (38–39). This one adds the host side: a plugin can return a chat view from an
`activate` callback, the host shows it in its own chat window (separate from the document window,
so a note and a chat can be open at once), the user sends messages through a `send` callback, and
the provider streams the reply through a new provider event while the callback is running. Task 39
builds the bundled Chat plugin (OpenAI-compatible endpoint) on top; nothing backend-specific is
added here.

## Goal
An `activate` result may carry `view: {kind: "chat", id, title, messages, placeholder?, prompt?, send}`.
The host opens (or refocuses) a chat window showing the transcript, with a multi-line input at the
bottom. Return sends the input through the `send` callback with the text in `text`; while that
callback runs, `messageDelta` events from the provider append text to the reply bubble; the
callback's final effects carry the authoritative `view` whose `messages` replace the transcript.
A failed or cancelled send puts the text back into the input with an error line. A plugin reload
marks the chat invalidated: the transcript stays selectable, the input is disabled. Existing
editor views, the document window, and the launcher panel behave exactly as before. `swift test`
passes.

## Files
- Sources/OddFrogPluginAPI/PluginView.swift                    (modify — `Kind.chat`, chat fields, `PluginMessage`, `PluginMessageDelta`)
- Sources/OddFrogPluginAPI/ProviderServer.swift                 (modify — `ProviderOperation.Emit` carries params; SDK `emit` forwards them)
- Sources/OddFrogCore/LocalProvider.swift                       (modify — forward event params from in-process providers)
- Sources/OddFrogCore/PluginProcess.swift                       (modify — accept the `messageDelta` event)
- Sources/OddFrogCore/PluginCoordinator.swift                   (modify — per-kind view validation, `onMessageDelta`)
- Sources/OddFrogCore/DocumentSession.swift                     (modify — take the save action explicitly)
- Sources/OddFrogCore/ChatSession.swift                         (create — transcript/send state machine)
- Sources/OddFrog/DocumentWindowController.swift                (modify — `present` takes the save action)
- Sources/OddFrog/ChatWindowController.swift                    (create — window, transcript, input, status bar)
- Sources/OddFrog/AppDelegate.swift                             (modify — route by view kind, wire sends and deltas, reload)
- Plugins/Notes/Tests/NoteStoreTests.swift                      (modify — `ProviderOperation` construction)
- Tests/OddFrogCoreTests/LocalProviderTests.swift               (modify — emit with params)
- Tests/OddFrogCoreTests/DocumentSessionTests.swift             (modify — `make()` passes the save action)
- Tests/OddFrogCoreTests/ChatSessionTests.swift                 (create)
- Tests/OddFrogCoreTests/PluginTests.swift                      (modify — chat view validation, delta routing, process allowlist)
- docs/query-plugins.md                                         (modify — events paragraph, views section)
- docs/api2/exchanges.ndjson                                    (modify — one `messageDelta` event, one chat activation pair)
- Plugins/Notes/Sources/NotesPluginCore/NotesProvider.swift     (read — the only production `PluginView` constructor; must keep compiling unchanged)
- Sources/OddFrog/LauncherPanel.swift                           (read — must stay untouched; transient by design)
- Sources/OddFrog/LauncherViewController.swift                  (read — must stay untouched)

## Context
- Swift 6 package, `swift-tools-version: 6.0`, macOS 14 deployment target, strict concurrency.
  Tests use the `Testing` framework (`@Test`, `#expect`, `#require`, `Issue.record`), not XCTest.
  No Xcode project: `swift build`, `swift test`, `make bundle` are the workflow. Today from the
  repo root `swift build` is warning-free apart from two pre-existing warnings
  (`CGWindowListCreateImage` deprecated in `AppDelegate.swift`, `nonisolated(unsafe)` in
  `UnitRegistry.swift`) and `swift test` passes 183 tests (core 100, bundled features 41,
  Reminders 16, Notes 18, Calendar 8).
- Targets (`Package.swift`): `OddFrogPluginAPI` (wire types, Foundation only), `OddFrogCore`
  (host logic, Foundation + TOMLKit, must not import AppKit), `OddFrog` (AppKit app),
  `NotesPluginCore` (depends on `OddFrogPluginAPI` only), test targets `OddFrogCoreTests` and
  `NotesPluginTests`.
- Wire types in `Sources/OddFrogPluginAPI/PluginView.swift` today:
  `public struct PluginView: Codable, Sendable, Hashable` with
  `enum Kind: String, Codable, Sendable { case editor }`, fields `kind`, `id`, `title`,
  `text: String`, `placeholder: String?`, `save: PluginAction`, and the init
  `init(kind: Kind = .editor, id:, title:, text: String = "", placeholder: String? = nil, save: PluginAction)`.
  Call sites of that init: `NotesProvider.view(for:)` (`PluginView(id:title:text:placeholder:save:)`)
  and `DocumentSessionTests.make()`.
- `PluginAction` (`PluginItem.swift`): `init(_ kind: Kind, _ value: String = "", payload: JSONValue? = nil, ...)`;
  kinds include `.callback`. `JSONValue` has `subscript(key)`, `.string`, `.bool`, `.number`,
  `.array`, `static encode(_:)`, `decode(_:)`; `JSONValue.encode` goes through
  `PluginProtocol.encoder()/decoder()` (dates as Unix seconds).
- `PluginEffects` (`PluginProtocol.swift`): `notification: String?`, `refreshCatalog`,
  `refreshQuery`, `view: PluginView?`. `PluginActivation` has `actionID`, `payload`, `item`,
  `argument`, `text: String?`.
- `PluginEnvelope` doc comment already says "Requests have IDs; events do not"; provider events are
  envelopes with `method` + `params` and no `id`. `docs/api2/envelope.schema.json` already permits
  any `params` on an event, so it needs no change.
- Provider events today:
  - `Sources/OddFrogCore/PluginProcess.swift`, `receive(_:token:)`:
    `guard ["catalogChanged", "queryInvalidated"].contains(method) else { fail(RPCError("protocol", "Unknown provider event.")); return }`
    then `await event(method, message.params ?? .null)`. `PluginProcess.Event` is
    `@Sendable (String, JSONValue) async -> Void`, so out-of-process params already reach the host.
  - `Sources/OddFrogCore/LocalProvider.swift` drops params: `forwarder()` returns
    `{ method in await event(method, .object([:])) }` and `ProviderOperation` is built with
    `emit: { method in await emit(method) }`.
  - `Sources/OddFrogPluginAPI/ProviderServer.swift`: `ProviderOperation` has
    `typealias Emit = @Sendable (String) async throws -> Void`, `init(id:service:emit:)`,
    `func emit(_ method: String) async throws`. `ProviderServer.emit(_ method:)` sends
    `PluginEnvelope(method: method, params: .object([:]))`; `consume()` builds the operation with
    `emit: { [weak self] method in try await self?.emit(method) }`.
  - `ProviderHandler.start(emit:)` takes `@Sendable (String) async -> Void`; `CalendarHandler`,
    `RemindersHandler`, `FeatureProvider` and the tests' `ProbeHandler` implement it. It stays as is.
  - `ProviderOperation` is constructed by hand in `Plugins/Notes/Tests/NoteStoreTests.swift:18`
    with `emit: { _ in }`, and `Tests/OddFrogCoreTests/LocalProviderTests.swift` has a
    `ProbeHandler` whose `"emit"` method calls `operation.emit("queryInvalidated")` and an
    `EventLog` actor recording method names; the test `startAndOperationEmitReachTheEventCallback`
    expects `["catalogChanged", "queryInvalidated"]`.
  - `PluginCoordinator.event(_:params:package:generation:)` (private) switches on
    `catalogChanged`, `queryInvalidated`, `failure`; anything else is ignored. It already guards
    `token == generation` and package enablement.
- `PluginCoordinator` (`@MainActor`, `Sources/OddFrogCore/PluginCoordinator.swift`):
  - `activate(_ result:, action:, argument:, text: String? = nil, completion:) -> UUID`; after
    decoding `PluginEffects` it validates `effects.view`:
    `guard view.save.kind == .callback, !view.id.isEmpty, !view.title.isEmpty else { throw RPCError("protocol", "Invalid document view.") }`
    then `try validate(view.save, package: package)`. Completion is called exactly once;
    `PluginError.superseded` when the generation changed; `CancellationError` on cancel.
  - `cancelAction(_ id: UUID)`, `cancelActions()`, `stop()`, `reload(...)` exist.
  - `fail(_ package:, error:)` marks a package failed and stops its process.
  - `validate(_ action:, package:)` is private; a `.callback` with empty `value` or on a
    declarative package throws `RPCError("protocol", "Invalid callback action.")`.
- `DocumentSession` (`Sources/OddFrogCore/DocumentSession.swift`, `@MainActor public final class`):
  `init(view: PluginView, result: PluginResult, pluginName: String)` reads `view.save` into
  `let save: PluginAction`. `DocumentWindowController.present(_ view:, result:, pluginName:)`
  constructs it in `show(...)`. The `flush`/`settle`/quit logic must not change.
- `PluginResult` (`Sources/OddFrogCore/PluginResult.swift`): `pluginID`, `item`, `generation`,
  `catalog`, `directory`; `init(pluginID:item:generation: = UUID(), catalog: = false, directory: = nil)`.
- `AppDelegate` (`Sources/OddFrog/AppDelegate.swift`):
  - `private lazy var documents = DocumentWindowController()` (line 33).
  - `wirePlugins()` sets `documents.performSave = { session, revision, text, completion in _ = self?.plugins.activate(session.result, action: session.save, argument: nil, text: text, completion: completion) }`.
  - `reloadPlugins()` calls `plugins.reload(...)` then `documents.pluginsDidReload()`.
  - `runPluginAction` success path:
    `if let view = effects.view { documents.present(view, result: result, pluginName: package.manifest.name) }`
    after `notifier.post` and `executor.recordPlugin(result)`; failure path returns silently on
    `CancellationError`, else `report(String(describing: error))`.
  - `applicationShouldTerminate` asks `documents.prepareToTerminate`; `applicationWillTerminate`
    calls `plugins.stop()`.
  - `installMainMenu()` has File (Save → `DocumentWindowController.saveDocument(_:)`, Close →
    `NSWindow.performClose(_:)`) and Edit menus. Close already reaches any key window.
  - `status.onCancelAction = { plugins.cancelActions() }` is set on every callback activation and
    the status menu shows "Cancel Plugin Action" while it is non-nil.
- `DocumentWindowController` (`Sources/OddFrog/DocumentWindowController.swift`) is the pattern
  for the new window: `NSWindowController` subclass with a hand-built `NSWindow`
  (`styleMask: [.titled, .closable, .resizable, .miniaturizable]`, `isReleasedWhenClosed = false`,
  `setFrameAutosaveName`, `center()`), `activateWindow()` doing
  `NSApp.activate(ignoringOtherApps: true)`, `showWindow(nil)`, `makeKeyAndOrderFront(nil)`,
  a 28 pt status bar with a 12 pt secondary label and small rounded buttons, `textView(_:doCommandBy:)`
  closing on `cancelOperation(_:)`, `MainActor.assumeIsolated` inside `Timer` callbacks.
- Test helpers in `Tests/OddFrogCoreTests/PluginTests.swift`: `temp()`, `fixture(_:source:)`
  (writes a Python 3 executable), `manifest(id:mode:extra:)`, the `echo` Python provider source,
  `settle(_:)` / `waitUntil(_:)` pollers, and the private `DocumentHandler` actor
  (`respond(_:)`, `stall()`, counts `activations`, records `input`) used by
  `activateAlwaysCompletes`, which shows how to drive `PluginCoordinator.activate` against an
  in-process bundled package: `PluginPackage(manifest:directory:bundled: true)`,
  `coordinator.builtins["fixture"] = { handler }`, `coordinator.reload(discovery:settings:storage:)`,
  `coordinator.catalogItems.first?.result`.
- `publishedEnvelopeFixturesRoundTrip` decodes and re-encodes every line of
  `docs/api2/exchanges.ndjson`; new lines must be valid envelopes.
- Visual direction: the window should read like a native Apple chat (Messages), not like a
  terminal transcript. User messages are trailing-aligned accent-coloured bubbles with white text,
  replies are leading-aligned grey bubbles, there are no role header lines, and the input is a
  rounded capsule. Every colour, radius, inset, font and width ratio for the transcript is declared
  once in a private `Style` enum inside `ChatTranscriptView`, so restyling later is a one-file
  change; the window controller never sets a transcript colour or font itself. The document window
  used by Notes is not restyled in this task (see Out of scope).
- Streaming while the window is not yet open cannot work: effects (and thus the view) arrive only
  when the activation finishes. That is why a chat view may carry `prompt`: the host submits it
  through `send` as soon as the window is on screen, so the first turn streams like any other.

## Plan
1. `Sources/OddFrogPluginAPI/PluginView.swift`:
   - Add `public struct PluginMessage: Codable, Sendable, Hashable` with nested
     `public enum Role: String, Codable, Sendable { case user, assistant }`, fields `id: String`,
     `role: Role`, `text: String`, memberwise `public init(id:role:text:)`.
   - Add `public struct PluginMessageDelta: Codable, Sendable, Hashable` with `viewID: String`,
     `messageID: String`, `delta: String`, memberwise `public init`.
   - `PluginView.Kind` gains `case chat`. Fields become: `kind`, `id`, `title`,
     `text: String` (unchanged, editor), `placeholder: String?` (both kinds),
     `save: PluginAction?` (editor; now optional), `messages: [PluginMessage]?` (chat),
     `prompt: String?` (chat), `send: PluginAction?` (chat). Keep the existing editor init
     signature exactly (its `save` parameter stays non-optional and is stored into the optional),
     and add
     `public init(id: String, title: String, messages: [PluginMessage], placeholder: String? = nil, prompt: String? = nil, send: PluginAction)`
     which sets `kind = .chat` and `text = ""`. Synthesized `Codable` handles the optionals; an
     editor view encoded by the current code still decodes.
2. `Sources/OddFrogPluginAPI/ProviderServer.swift`: `ProviderOperation.Emit` becomes
   `@Sendable (String, JSONValue) async throws -> Void`; `emit(_ method:)` gains
   `params: JSONValue = .object([:])` and forwards both. `ProviderServer.emit` gains the same
   `params` parameter and sends it; `consume()` passes `{ method, params in try await self?.emit(method, params: params) }`.
   `run()` keeps calling `provider.start(emit:)` with a String-only closure that sends empty params.
3. `Sources/OddFrogCore/LocalProvider.swift`: `forwarder()` returns
   `@Sendable (String, JSONValue) async -> Void` forwarding params; the `ProviderOperation` is
   built with `{ method, params in await emit(method, params) }`; `handler.start(emit:)` receives
   `{ method in await emit(method, .object([:])) }`.
4. `Sources/OddFrogCore/PluginProcess.swift`: add `"messageDelta"` to the accepted event list in
   `receive(_:token:)`.
5. `Sources/OddFrogCore/PluginCoordinator.swift`:
   - Add `public var onMessageDelta: ((String, PluginMessageDelta) -> Void)?` (plugin ID, delta).
   - In `event(...)`: `case "messageDelta":` decode `params` as `PluginMessageDelta`; on success
     call `onMessageDelta?(package.manifest.id, delta)`; on failure
     `fail(package, error: RPCError("protocol", "Invalid messageDelta event."))`.
   - Replace the view validation in `activate` with a private
     `validate(_ view: PluginView, package:)`: `id` and `title` non-empty, else
     `RPCError("protocol", "Invalid view.")`. For `.editor`: `save` present with kind `.callback`
     and `validate(save, package:)`, else `RPCError("protocol", "Invalid document view.")`. For
     `.chat`: `send` present with kind `.callback` and validated; `messages` present, every
     message has a non-empty `id` and IDs are unique, else `RPCError("protocol", "Invalid chat view.")`.
6. `Sources/OddFrogCore/DocumentSession.swift`: `init(view: PluginView, save: PluginAction, result:, pluginName:)`;
   nothing else changes. `Sources/OddFrog/DocumentWindowController.swift`: `present(_ view:, save: PluginAction, result:, pluginName:)`
   threads it into `show(...)`; no other edits.
7. `Sources/OddFrogCore/ChatSession.swift` (create): `@MainActor public final class ChatSession`,
   Foundation only. State: `let pluginID`, `let pluginName`, `let viewID`, `let result: PluginResult`,
   `let send: PluginAction`, `let placeholder: String?`, `private(set) var title`,
   `private(set) var messages: [PluginMessage]`, `private(set) var draft = ""`,
   `private(set) var outgoing: Outgoing?` where `public struct Outgoing { let id: Int; let text: String; let userID: String; var replyID: String }`,
   `private(set) var invalidated = false`, `private(set) var error: String?`, `private var serial = 0`.
   API:
   - `init(view: PluginView, send: PluginAction, result:, pluginName:)` seeds `title`, `messages`
     (`view.messages ?? []`), `placeholder`, and `draft = view.prompt ?? ""`.
   - `var isSending: Bool { outgoing != nil }`, `var canSend: Bool { !invalidated && outgoing == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }`.
   - `func edit(_ draft: String)` stores it and clears `error`.
   - `func beginSend() -> Outgoing?`: nil unless `canSend`; else `serial += 1`, append
     `PluginMessage(id: "host-user-\(serial)", role: .user, text: draft)` and
     `PluginMessage(id: "host-reply-\(serial)", role: .assistant, text: "")`, set `outgoing`
     (with `id: serial`, `text: draft`, those two IDs), clear `draft` and `error`, return it.
   - `func receive(_ delta: PluginMessageDelta) -> Bool`: false unless `outgoing != nil` and
     `delta.viewID == viewID`. Otherwise, if the reply message's ID differs from `delta.messageID`,
     rename it (and `outgoing.replyID`) to `delta.messageID`; append `delta.delta` to its text;
     return true.
   - `func complete(id: Int, view: PluginView?)`: ignored unless `outgoing?.id == id`. Clears
     `outgoing`. If `view` is non-nil, replace `messages` with `view.messages ?? []` and `title`
     with `view.title`; if nil, keep the transcript as streamed (the reply bubble stays).
   - `func fail(id: Int, message: String, terminal: Bool)`: ignored unless `outgoing?.id == id`.
     Removes the two messages appended by that send, restores `draft` to the sent text, sets
     `error = message`, `invalidated = terminal`, clears `outgoing`.
   - `func invalidate(message: String)`: `invalidated = true`, `error = message`; an in-flight
     send is failed as above with the same message (so the draft comes back).
8. `Sources/OddFrog/ChatWindowController.swift` (create):
   `@MainActor final class ChatWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate`.
   - Window: `NSWindow(contentRect: 560×640, styleMask: [.titled, .closable, .resizable, .miniaturizable])`,
     `minSize` 380×320, `isReleasedWhenClosed = false`, `setFrameAutosaveName("chat")`, `center()`,
     `delegate = self`. Normal level, not floating.
   - Content, top to bottom: a `ChatTranscriptView` (step 8a) filling the window; a 0.5 pt
     separator (`NSBox`, `boxType = .separator`); an input row with 12 pt side padding holding a
     rounded capsule container (`wantsLayer`, corner radius 16, 1 pt `separatorColor` border,
     `textBackgroundColor` fill) that wraps an `NSScrollView` with an editable plain-text
     `NSTextView` (same automatic-substitution flags off as the document editor, 14 pt system
     font, inset 12×7, `delegate = self`) whose height constraint follows its layout manager's
     used height clamped between one and six lines; a placeholder label overlaid on the input,
     hidden when the input is non-empty or the session has no `placeholder`; a 28 pt status bar
     with a 12 pt secondary label on the left and a small rounded "Stop" button on the right,
     hidden unless a send is in flight.
   - Transcript rendering: the controller calls `transcript.render(session.messages, streaming: session.outgoing?.replyID)`
     after every state change; it never touches bubble views directly.
   - Public API used by `AppDelegate`:
     `var performSend: ((ChatSession, String, @escaping (Result<PluginEffects, any Error>) -> Void) -> UUID?)?`,
     `var cancelSend: ((UUID) -> Void)?`,
     `func present(_ view: PluginView, send: PluginAction, result: PluginResult, pluginName: String)`,
     `func apply(_ delta: PluginMessageDelta, pluginID: String)`,
     `func pluginsDidReload()`.
   - `present`: if a session with the same `pluginID` and `viewID` is open, activate the window
     and return (transcript untouched). Otherwise, if a send is in flight, call `cancelSend` on its
     token first. Then create the session, render, set `window.title`, put the draft into the input,
     activate the window, make the input first responder, and if `session.canSend` and the view
     carried a non-empty `prompt`, call `submit()`.
   - `submit()`: `guard let outgoing = session.beginSend()`; render the transcript; set the input string to "";
     status label "Waiting for \(pluginName)…"; show Stop; call `performSend(session, outgoing.text)`
     and keep the returned token in `inFlight: (id: Int, token: UUID)?`. Completion: ignore if
     `self.session !== session`; on `.success(effects)` call `session.complete(id:, view: effects.view)`,
     set `window.title = session.title`; on `.failure(error)`: `terminal = error is PluginError && case .superseded`;
     message is the reload message for terminal, `"Stopped."` for `CancellationError`, else
     `"Send failed: \(error)"`; call `session.fail(id:message:terminal:)`, restore the input text
     from `session.draft`. In every case clear `inFlight`, render, refresh the status bar, and make
     the input first responder unless invalidated.
   - `apply(delta, pluginID:)`: ignore unless `session?.pluginID == pluginID`; if
     `session.receive(delta)` returns true, render the transcript.
   - Input keys via `textView(_:doCommandBy:)`: `insertNewline(_:)` → `submit()` and return true;
     `insertLineBreak(_:)` (Shift/Option+Return) → return false so a newline is inserted;
     `cancelOperation(_:)` → `window?.performClose(nil)`, return true. `textDidChange` →
     `session.edit(input.string)`, update the input height and placeholder, refresh status.
   - "Stop" calls `cancelSend(token)` for the in-flight send; the completion path above handles the
     resulting `CancellationError`.
   - `pluginsDidReload()`: if a session is open and not invalidated, `session.invalidate(message:)`
     with `"\(pluginName) was reloaded. Close this window and open the chat again."`, set the input
     non-editable, restore the draft text into the input, render, refresh status.
   - `windowShouldClose` returns true always; closing while a send is in flight calls `cancelSend`
     first and drops the session. Nothing is persisted by the host.
   - Status bar `refresh()`: label shows `session.error` if set, else the waiting text while
     sending, else "". Stop is visible only while sending. Input `isEditable = !session.invalidated`.
8a. `Sources/OddFrog/ChatTranscriptView.swift` (create): `@MainActor final class ChatTranscriptView: NSView`.
   - Structure: an `NSScrollView` (vertical scroller, overlay style, `drawsBackground = false`)
     whose document view is a vertical `NSStackView` (`alignment = .width`, `spacing = Style.rowSpacing`,
     `edgeInsets = Style.edgeInsets`) pinned to the clip view's width.
   - One row per message: a private nested `Bubble: NSView` holding a rounded container
     (`wantsLayer`, `cornerRadius = Style.cornerRadius`) with a wrapping, selectable
     `NSTextField(wrappingLabelWithString:)` inside (`isSelectable = true`, `Style.bodyFont`,
     `maximumNumberOfLines = 0`). The container's width is at most `Style.maxWidthRatio` (0.75) of
     the row; `.user` rows pin the container to the trailing edge with
     `Style.userFill` (`NSColor.controlAccentColor`) and `Style.userText` (white); `.assistant`
     rows pin it to the leading edge with `Style.replyFill` (an `NSColor(name: nil)` dynamic colour:
     `#E9E9EB` in light appearances, `#3B3B3D` in dark) and `Style.replyText` (`labelColor`).
     No header or role label; no timestamps.
   - `func render(_ messages: [PluginMessage], streaming replyID: String?)`: reuse existing bubble
     rows by index while their `role` matches, otherwise rebuild from that index; set each label's
     text; a message whose `id == replyID` and whose text is empty shows `Style.typingGlyph` ("…")
     in `secondaryLabelColor`. After layout, scroll to the bottom only if the view was scrolled to
     within `Style.stickyBottom` (24 pt) of the bottom before rendering, so reading older messages
     is not interrupted by streaming.
   - All metrics and colours live in the private nested `enum Style` (`rowSpacing` 6,
     `edgeInsets` 16/12, `cornerRadius` 16, `bubbleInsets` 12×8, `bodyFont` system 14,
     `maxWidthRatio`, the four colours, `typingGlyph`, `stickyBottom`). Nothing else in
     `Sources/OddFrog` declares a transcript colour, font or inset.
9. `Sources/OddFrog/AppDelegate.swift`:
   - Add `private lazy var chats = ChatWindowController()` next to `documents`.
   - `wirePlugins()`: after the `documents.performSave` assignment add
     `chats.performSend = { [weak self] session, text, completion in self?.plugins.activate(session.result, action: session.send, argument: nil, text: text, completion: completion) }`,
     `chats.cancelSend = { [weak self] token in self?.plugins.cancelAction(token) }`, and
     `plugins.onMessageDelta = { [weak self] pluginID, delta in self?.chats.apply(delta, pluginID: pluginID) }`.
     Sends never record frecency and never touch `status.onCancelAction`.
   - `runPluginAction` success path: replace the `documents.present` line with a switch on
     `view.kind`: `.editor` with `view.save` → `documents.present(view, save:, result:, pluginName:)`;
     `.chat` with `view.send` → `chats.present(view, send:, result:, pluginName:)`. The
     coordinator already rejected views missing those actions, so a `nil` here does nothing.
   - `reloadPlugins()`: call `chats.pluginsDidReload()` right after `documents.pluginsDidReload()`.
   - No change to `applicationShouldTerminate`: a chat has nothing to flush.
10. Tests.
   - `Plugins/Notes/Tests/NoteStoreTests.swift:18`: `emit: { _, _ in }`.
   - `Tests/OddFrogCoreTests/LocalProviderTests.swift`: `ProbeHandler`'s `"emit"` case calls
     `operation.emit("queryInvalidated", params: .object(["n": .number(1)]))`; `EventLog` records
     `(String, JSONValue)` pairs; `startAndOperationEmitReachTheEventCallback` asserts the methods
     are `["catalogChanged", "queryInvalidated"]` and the second event's params carry `n == 1`.
   - `Tests/OddFrogCoreTests/DocumentSessionTests.swift`: `make()` passes
     `save: PluginAction(.callback, "save")` explicitly; assertions unchanged.
   - `Tests/OddFrogCoreTests/ChatSessionTests.swift` (create, `@MainActor struct`): a view seeds
     title, messages, placeholder and `draft` from `prompt`; `beginSend` is nil for a blank draft,
     appends the user and empty reply messages and clears the draft; a delta with the wrong
     `viewID` is ignored and one with the right `viewID` renames the reply and appends text;
     `complete` with a view replaces messages and title, `complete` with nil keeps the streamed
     reply; `fail` removes both messages, restores the draft and sets `error`; `fail(terminal: true)`
     and `invalidate` set `invalidated` and make `canSend` false; stale `complete`/`fail` IDs are ignored.
   - `Tests/OddFrogCoreTests/PluginTests.swift`:
     (a) `@Test @MainActor func chatViewsAreValidatedAndDeltasAreRouted()`: reuse the
     `DocumentHandler` pattern with a handler whose `activate` first calls
     `operation.emit("messageDelta", params: .encode(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi")))`
     and then returns the configured reply. Set `coordinator.onMessageDelta` to record
     `(pluginID, delta)`. Assert: a chat view without `send` completes with an `RPCError` of code
     `protocol`; a chat view with duplicate message IDs likewise; a valid chat view
     (`messages: [{id: "m1", role: "user", text: "hello"}]`, `send: {kind: "callback", value: "send"}`)
     completes with `.success` whose `view?.kind == .chat`, and the recorded delta is
     `("fixture", PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi"))`.
     (b) `@Test func processAcceptsMessageDeltaEvents()`: a persistent Python fixture whose
     `activate` prints `{"apiVersion":2,"method":"messageDelta","params":{"viewID":"c1","messageID":"m2","delta":"Hi"}}`
     before its result; build `PluginProcess(executable:persistent: true, event:)` with an event
     closure recording into an `EventLog`-style actor; assert the activation result arrives and the
     recorded event is `messageDelta` with `delta == "Hi"`. Also assert that an unknown event name
     (`"bogus"`) still fails the request with an `RPCError` mentioning "Unknown provider event."
   - `activateAlwaysCompletes` keeps passing unchanged (its editor fixtures are still valid).
11. Docs.
   - `docs/query-plugins.md`: in the events paragraph, after the `catalogChanged`/`queryInvalidated`
     sentence, add: providers may also emit `messageDelta` with `{viewID, messageID, delta}` while
     a chat `send` callback is running; the host appends `delta` to the reply of the open chat with
     that `viewID` and ignores deltas for any other view; the callback's final `view` is
     authoritative. Rename the "## Document views" section to "## Views" with two subsections,
     "### Editor" (existing text, unchanged in substance) and "### Chat" describing the chat
     object (`messages` array of `{id, role: "user" | "assistant", text}`, `placeholder`,
     optional `prompt` that the host sends immediately after opening, `send` callback invoked with
     the input text in `text`), that `messages` returned from `send` replace the transcript and
     `title` updates the window, that the host keeps no transcript of its own, and that a reload
     invalidates the open chat. Update the callbacks paragraph so "from a document window" reads
     "from a document or chat window".
   - `docs/api2/exchanges.ndjson`: append
     `{"apiVersion":2,"method":"messageDelta","params":{"viewID":"c1","messageID":"m2","delta":"Hel"}}`,
     an `activate` request with `"actionID":"send"` and `"text":"hello"`, and its result
     `{"apiVersion":2,"id":"send","result":{"refreshCatalog":false,"refreshQuery":false,"view":{"kind":"chat","id":"c1","title":"hello","messages":[{"id":"m1","role":"user","text":"hello"},{"id":"m2","role":"assistant","text":"Hello!"}],"send":{"kind":"callback","value":"send","payload":{"id":"c1"}}}}}`.

Approach notes. One `PluginView` with a `kind` discriminator and per-kind optional fields was
chosen over a second `PluginEffects.chat` field so the host has one routing point and the wire
stays "one view per activation"; the cost is `save` becoming optional, which is why the session
inits take the action explicitly instead of unwrapping. Deltas are events rather than a streamed
response because the envelope already has events, and the final authoritative `view` means a lost
or reordered delta can never corrupt the transcript. The host does not persist conversations:
the plugin owns them, exactly as Notes owns its files.

## Constraints
- No comments, doc comments, or section banners in new or edited code. Existing comments
  (`PluginEnvelope`, `NDJSONChannel`, `ProviderServer`, `PluginCoordinator`, `PluginProcess`)
  stay as they are.
- Always brace conditionals and returns; never a bare single-expression `if`/`guard` body.
- One type per file in `Sources/OddFrog` and `Sources/OddFrogCore`; private nested helper types
  inside a class (`ChatTranscriptView.Bubble`, `ChatTranscriptView.Style`) are fine.
- The chat window uses only system dynamic colours plus the two hard-coded reply-bubble greys
  named in step 8a, so it follows light and dark appearance without extra code. `Sources/OddFrogPluginAPI` files may hold several related wire types.
- Swift 6 strict concurrency: wire types are `Sendable`; `ChatSession` and the controller are
  `@MainActor`; no `@unchecked Sendable` additions.
- Wire format stays additive: every new JSON field is optional on decode; every existing line in
  `docs/api2/exchanges.ndjson` and every existing editor view keeps decoding.
- `OddFrogCore` must not import AppKit; `ChatSession` is Foundation-only.
- Do not change `LauncherPanel`, `LauncherViewController`, or the launcher's dismissal rules.
  Do not change `DocumentWindowController` beyond threading the save action.
- No message text in `Log.write` or notifications.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds from the repo root with no new warnings.
- `swift test` passes from the repo root; the 183 existing tests still pass plus the new
  `ChatSessionTests`, `chatViewsAreValidatedAndDeltasAreRouted`, and `processAcceptsMessageDeltaEvents`.
- `make bundle` exits 0.
- Manual, after `make run`: with no chat plugin installed the app launches, `note` still opens the
  document window, and quitting is immediate. The full chat flow is checked in task 39 once a
  plugin returns a chat view.

## Out of scope
- The bundled Chat plugin, any HTTP client, API keys, model settings (task 39).
- Markdown or code-block rendering inside bubbles; plain text only.
- Restyling the document window used by Notes. Its current look is a known problem and gets its
  own follow-up task after 39; nothing here should make that harder (the chat window shares no
  views with it).
- Multiple simultaneous chat windows or chat history stored by the host.
- Persisting the input draft across window close or app quit.
- Changing `ProviderHandler.start(emit:)` or any existing provider's event calls.
- Deltas for views other than the open chat, or deltas outside a running `send`.

## Open questions
none
