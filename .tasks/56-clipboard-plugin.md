# Task: Add a bundled Clipboard plugin that keeps the last N copied texts and images

## Goal
A new bundled plugin `clipboard` (keyword `clip`, off by default) records what the user copies in
any app, whether or not the launcher is open. It keeps the newest N text and image entries on disk,
lists them newest first under `clip <filter>`, copies an entry back to the clipboard on Return,
deletes one entry on the secondary action, and clears the stored history from a dedicated row.
Automatic capture runs only while macOS allows Odd Frog to read the general pasteboard without
asking (`NSPasteboard.AccessBehavior.alwaysAllow`). Otherwise the plugin shows a setup row.

## Files
- Plugins/Clipboard/plugin.toml                                             (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardEntry.swift        (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardLimits.swift       (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardCapture.swift      (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardImages.swift       (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardPasteboard.swift   (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardArchive.swift      (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardProvider.swift     (create)
- Plugins/Clipboard/Sources/ClipboardPluginCore/ClipboardHandler.swift      (create)
- Plugins/Clipboard/Tests/ClipboardArchiveTests.swift                       (create)
- Plugins/Clipboard/Tests/ClipboardProviderTests.swift                      (create)
- Plugins/Clipboard/Tests/ClipboardHandlerTests.swift                       (create)
- Plugins/Clipboard/Tests/ClipboardImagesTests.swift                        (create)
- Package.swift                                                             (modify)
- Sources/OddFrogBuiltins/BuiltinProviders.swift                            (modify)
- Tests/OddFrogCoreTests/BundledPackageTests.swift                          (modify)
- Tests/OddFrogCoreTests/MigrationTests.swift                               (modify)
- Plugins/Notes/Sources/NotesPluginCore/NotesHandler.swift                  (read — handler shape, context decoding)
- Plugins/Notes/Sources/NotesPluginCore/NotesProvider.swift                 (read — row building, reserved last row, date label)
- Plugins/Notes/Sources/NotesPluginCore/NoteStore.swift                     (read — file storage under `storagePath`)
- Plugins/Notes/Tests/NoteStoreTests.swift                                  (read — test style, params/operation helpers)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersHandler.swift      (read — `start(emit:)`, background task, `shutdown`)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift     (read — access-state rows)
- Plugins/Calculator/plugin.toml                                            (read — `background = true`)
- Plugins/Windows/plugin.toml                                               (read — `enabled_by_default = false`, number setting with bounds)
- Sources/OddFrogCore/PluginCoordinator.swift                               (read — lifecycle; do not modify)
- Sources/OddFrogCore/LocalProvider.swift                                   (read — lifecycle; do not modify)

## Context
- Swift tools 6.2 (Swift 6 language mode, strict concurrency), macOS 26 deployment target, Swift
  Testing (`import Testing`, `@Test`, `#expect`, `#require`). No XCTest.
- **Bundled plugins run in-process.** `BuiltinProviders.factories` (`Sources/OddFrogBuiltins/BuiltinProviders.swift`)
  maps a plugin ID to a `@Sendable () -> any ProviderHandler`. `PluginCoordinator` wraps the handler in
  a `LocalProvider` when the package is bundled and a factory exists. The plugin's metadata is
  `Plugins/<Name>/plugin.toml`. Packaging (`OddFrogPackage`, `make plugins`) discovers every
  `Plugins/*/plugin.toml` automatically; no packaging change is needed.
- `ProviderHandler` (`Sources/OddFrogPluginAPI/ProviderHandler.swift`): `start(emit:)`, `handle(_:params:operation:)`,
  `shutdown()`. The first request calls `start(emit:)` before `handle`. `emit("queryInvalidated")` makes
  the coordinator re-run the visible query.
- Every `handle` call gets `params["context"]` (a `PluginContext`: `settings`, `storagePath`,
  `configPath`) and `params["input"]`. That includes `"initialize"` and `"settings"`. `start(emit:)` gets no
  context. `storagePath` is `<support>/v2/plugins/clipboard`. Setting values arrive already validated
  against `plugin.toml`, with defaults filled in. Numbers arrive as `JSONValue.number(Double)`.
- Methods a handler receives: `initialize` (must return `{"apiVersion": 2}`), `settings` (after a
  setting value changes while enabled; `PluginCoordinator.updateSettings`), `query` (`input` is a
  `PluginQuery`), and `activate` (`input` is a `PluginActivation`; `actionID` and `payload` come from the
  row's `PluginAction(.callback, …)`). Unknown methods throw `RPCError("method", …)`.
- **Lifecycle.** `background = true` makes `PluginCoordinator.reload` call `initialize` at reload for
  every enabled package, so the handler starts at app launch. Enabling or disabling a plugin, or
  changing its trigger, goes through `reload`, which calls `stop()`. `stop()` schedules each transport's
  stop in an unstructured `Task`, and `LocalProvider.stop()` runs `handler.shutdown()` in a detached
  task. Neither is awaited, and a fresh handler for the next generation can start first.
  `LocalProvider.request` checks its `stopped` flag only *before* `await handler.start(…)`. A
  `handle("initialize")` can therefore reach a handler **after** that handler's `shutdown()` has
  run. The handler must defend against both orders itself (Plan steps 7–8). Changing only a setting
  value (not enabled/trigger) keeps the handler and sends `settings`.
- **Pasteboard privacy.** Since macOS 15.4, programmatic reads of the **general** pasteboard raise
  a system alert unless `NSPasteboard.general.accessBehavior == .alwaysAllow`. Per `NSPasteboard.h`,
  `.default` means the app has never triggered the alert. The first alert moves it to `.ask`, and the app
  then appears in System Settings, where the user can pick Ask / Always Allow / Always Deny. With
  `.alwaysDeny`, reads are denied silently. Reading `changeCount` and `accessBehavior` does not
  read contents. Pasteboards other than general "default to always allow access". Tests use a
  uniquely named pasteboard and never touch `.general`. The alert's exact button labels are not
  documented, so row and notification wording must not name a button that may not exist.
- `changeCount` counts ownership changes. Polling sees only the current contents, so copies made
  between two ticks are lost. Capture is best effort by design.
- Row icons: `PluginItem.icon` set to an absolute file path is loaded with `NSImage(contentsOfFile:)`
  by `Sources/OddFrog/IconCache.swift`. Rows draw icons at 24 pt (`ResultRowView.iconSide`), so a 64 px
  thumbnail is enough. `symbol` is an SF Symbol name used when there is no icon.
- The launcher caps rows at `maxResults` (default 8) *after* the plugin answers
  (`PluginCoordinator.search` → `prefix(maxResults)`). A row appended after a full list is cut. Notes
  handles this by returning `prefix(cap - 1)` rows plus its "New note" row, where
  `cap = max(1, min(request.maxResults, 50))`.
- `PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security")` opens System
  Settings › Privacy & Security. Reminders and Calendar use the same scheme with their own anchors.
  The Paste pane's anchor is not known, so use the bare URL.
- No existing plugin core imports AppKit; this one will (`NSPasteboard`). That is deliberate: the
  handler owns capture so that no host service or capability is needed. User plugins are unsandboxed
  executables running as the same user, so a capability gate would not protect the history anyway.
- Two tests hard-code the bundled plugin count (`#expect(packages.count == 11)` in
  `BundledPackageTests.shippedFeaturesRunInProcessAndEachCanBeDisabled` and in `MigrationTests`).
  `BundledPackageTests` also force-unwraps `queries[package.manifest.id]!` for every bundled package, so
  a new bundled plugin without an entry there crashes the test. That test sets
  `coordinator.builtins = BuiltinProviders.factories` and enables every package. Left alone, the real
  factory would run `ClipboardHandler` against `.general` in the test process, and the result would
  depend on that machine's pasteboard permission. Plan 10 overrides the clipboard factory there.
- Writing several representations at once means building one `NSPasteboardItem` (its `setString`/`setData`
  return `Bool`), then `clearContents()` and `writeObjects([item])` (also `Bool`). `NSPasteboard.setData`
  on its own documents that the type must already have been declared, so it is not used to add a second type.
- Baseline on the current tree: `swift build` succeeds with one pre-existing warning
  (`Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift:5`, unnecessary `nonisolated(unsafe)`).
  `swift test` passes all suites (279 tests).

## Plan

1. **`plugin.toml`.** Create `Plugins/Clipboard/plugin.toml`:
   `id = "clipboard"`, `name = "Clipboard"`, `version = "0.1.0"`, `api_version = 2`, `keyword = "clip"`,
   `mode = "persistent"`, `activation = "exclusive"`, `background = true`, `enabled_by_default = false`,
   `capabilities = []`. Two settings:
   - `limit`: title `History size`, type `number`, default `50`, minimum `1`, maximum `200`.
   - `capture_images`: title `Save copied images`, type `boolean`, default `true`.

2. **`Package.swift`.** Add `.target(name: "ClipboardPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Clipboard/Sources/ClipboardPluginCore")`,
   add `"ClipboardPluginCore"` to the `OddFrogBuiltins` dependencies, and add
   `.testTarget(name: "ClipboardPluginTests", dependencies: ["ClipboardPluginCore", "OddFrogPluginAPI"], path: "Plugins/Clipboard/Tests")`.
   Place each next to the Notes/Chat entries.

3. **Model: `ClipboardEntry.swift`, `ClipboardLimits.swift`, `ClipboardCapture.swift`.**
   - `ClipboardEntry` (public, `Codable, Sendable, Hashable`): `id: String` (lowercased UUID),
     `kind: Kind` (`text` | `image`), `text: String?`, `width: Int?`, `height: Int?`, `byteSize: Int`
     (UTF-8 bytes for text; full PNG plus thumbnail bytes for images), `hash: String` (hex SHA-256 of the UTF-8
     text or of the full PNG bytes), `copied: Date`. Add a static `title(for:)`. For text it returns the first
     non-empty trimmed line, prefixed to 80 characters. For images it returns `"Image \(width)×\(height)"`.
   - `ClipboardLimits` (public, `Sendable, Equatable`): stored `count: Int`, `captureImages: Bool` and
     `maxTotalImageBytes: Int`, with a memberwise public init where `maxTotalImageBytes` defaults to
     `209_715_200`. That way tests can inject a small total. Add `init(settings: [String: JSONValue])`,
     which reads `limit` (rounded, clamped to 1…200, default 50) and `capture_images` (default true). Also
     add static constants `maxTextBytes = 65_536`, `maxImageSourceBytes = 10_485_760`,
     `maxImagePixels = 40_000_000`, `maxImageBytes = 20_971_520` (the processed PNG) and
     `thumbnailPixels = 64`.
   - `ClipboardCapture` (public enum, `Sendable, Equatable`): `.text(String)` and
     `.image(data: Data, type: ImageType)`, with `ImageType` being `png` or `tiff`. It is the plain value
     extracted from a pasteboard. `ProcessedImage` (public struct, `Sendable`): `png: Data`,
     `thumbnail: Data`, `width: Int`, `height: Int`.

4. **Image processing: `ClipboardImages.swift`.** A public enum with a nonisolated static
   `process(_ data: Data, type: ClipboardCapture.ImageType, maxOutputBytes: Int = ClipboardLimits.maxImageBytes) -> ProcessedImage?`,
   built on ImageIO (`CGImageSourceCreateWithData`).
   - Return nil when `data.count > maxImageSourceBytes`.
   - Read pixel width/height from `CGImageSourceCopyPropertiesAtIndex` **without decoding**. Return nil when
     either is ≤ 0 or when `width > maxImagePixels / height`, which avoids overflowing `width * height`.
   - The full PNG is the original bytes when `type` is `png`. For `tiff` it is re-encoded to PNG with
     `CGImageDestination` (`UTType.png`).
   - Return nil when the full PNG is larger than `maxOutputBytes`, because a compressed TIFF can grow when
     re-encoded.
   - The thumbnail comes from `CGImageSourceCreateThumbnailAtIndex` with
     `kCGImageSourceCreateThumbnailFromImageAlways` and `kCGImageSourceThumbnailMaxPixelSize = thumbnailPixels`,
     encoded as PNG.
   - Any failure returns nil. Callers run this in a detached task, outside the main actor and outside
     `ClipboardArchive`.

5. **Pasteboard access: `ClipboardPasteboard.swift`.** A public struct (`Sendable`) holding an
   `NSPasteboard.Name`. `.general` in production, a unique name in tests. Every method is
   `@MainActor` and resolves `NSPasteboard(name: name)` on each call. No `NSPasteboard` or
   `NSPasteboardItem` value ever leaves the main actor. It defines one private marker type,
   `com.paveltrofimov.odd-frog.restored` (the app's bundle ID plus `.restored`), which Odd Frog puts on
   its own writes.
   - `state() -> (changeCount: Int, behavior: NSPasteboard.AccessBehavior)`. Reads no contents.
   - `capture() -> ClipboardCapture?`. Reads `pasteboardItems?.first` and applies these rules in order:
     1. Its `types` contain the marker type, `org.nspasteboard.ConcealedType`,
        `org.nspasteboard.TransientType` or `org.nspasteboard.AutoGeneratedType` → nil. The marker case is
        Odd Frog's own re-copy, so it is never recorded twice and no change-count bookkeeping is needed.
     2. Contains `.fileURL` → nil. Finder puts the file's icon image on the pasteboard, which must not
        be recorded as an image.
     3. `string(forType: .string)` is present and non-empty after trimming whitespace → `.text`. If its
        UTF-8 byte count exceeds `maxTextBytes`, return nil. This makes a spreadsheet cell, which carries
        both a string and a rendered image, record as text.
     4. Else `data(forType: .png)` → `.image(type: .png)`, else `data(forType: .tiff)` →
        `.image(type: .tiff)`.
     5. Otherwise nil. Rich text keeps only its plain string. Only the first pasteboard item is read.
   - `write(text: String) -> Bool` and `write(png: Data) -> Bool`. Each builds one `NSPasteboardItem`
     carrying the payload (`setString(_, forType: .string)` or `setData(_, forType: .png)`) and the marker
     (`setData(Data(), forType: marker)`). If either returns false, it returns false **before touching the
     pasteboard**. Otherwise it calls `clearContents()` and returns the result of `writeObjects([item])`.
   - `requestAccess() -> AccessRequest`, where `AccessRequest` is a public enum `noText` or `read`. Look at
     `pasteboardItems?.first`. If there is none, if its types carry any of the skip markers from rule 1,
     or if it has no `.string` type, return `noText` **without reading contents**. Otherwise read
     `string(forType: .string)`, discard the value, and return `read`. That read is what makes macOS
     raise the access alert. It never touches a concealed item and never reads anything but plain text.

6. **Store: `ClipboardArchive.swift`.** A public `actor`. **No method contains an `await`**, so every
   check and the mutation it guards run as one step. All file IO is synchronous `FileManager`/`Data` calls
   inside the actor.
   - **Generations.** A `nonisolated let` `Atomic<Int>` (`import Synchronization`) and a
     `nonisolated func nextGeneration() -> Int` that increments it. `ClipboardHandler.init` takes its
     generation from this, so a handler created later always has a higher number, whatever order its
     requests arrive in. The actor keeps `owner: Int?` and `newest: Int` (the highest generation that ever
     claimed). Every method below except `claim` does nothing (returns empty/nil/false) unless its
     `generation` equals `owner`.
   - Layout under the claimed directory: `index.json` (a JSON array of `ClipboardEntry`, newest first,
     written with `.atomic`, dates encoded with `PluginProtocol.encoder()`), and `images/<id>.png` plus
     `images/<id>-thumb.png`.
   - `claim(generation: Int, directory: URL, limits: ClipboardLimits) throws -> Bool`:
     1. If `generation < newest`, return false without changing anything. That is a stale handler whose
        initialize arrived late.
     2. Create the directory. Load `index.json`. If it is missing, the list is empty. If it exists but cannot
        be read or decoded, throw
        `RPCError("clipboard", "Clipboard history in <directory> could not be read. Nothing was changed.")`
        without touching any file and without taking ownership.
     3. Set `newest` and `owner` to `generation`. Drop image entries whose full PNG or thumbnail is missing,
        apply the limits, and commit (below).
     4. Then delete every file in `images/` that belongs to no entry. Return true.
   - `release(generation:)`. Clears `owner` only if it equals `generation`.
   - `configure(generation:, limits:) throws`. Stores the limits, applies them, and commits.
   - `entries(generation:) -> [ClipboardEntry]` and `imageData(generation:, id:) -> Data?` (the full PNG).
     Add a `nonisolated static func thumbnailPath(in directory: URL, id: String) -> String` returning
     `<directory>/images/<id>-thumb.png`, so row building needs no actor hop.
   - `record(_ capture: ClipboardCapture, image: ProcessedImage?, generation: Int, now: Date) throws -> Bool`.
     Returns false without writing when the generation is stale, when an image arrives while
     `captureImages` is off, or when an image arrives without its `ProcessedImage`. Otherwise it computes
     the hash; for images the hash covers the processed PNG. If an entry with the same hash exists, that
     entry moves to the top with `copied = now`. Otherwise a new entry is inserted at the top. It applies
     the limits, commits, and returns true.
   - `touch(generation:, id:, now:) throws`. Moves an existing entry to the top with `copied = now`.
   - `delete(generation:, id:) throws`, and `clear(generation:) throws -> Int`, which returns the number of
     entries removed.
   - Applying limits works on a copy of the list. Drop the oldest entries while `count > limits.count`.
     Then, while the summed `byteSize` of image entries exceeds `limits.maxTotalImageBytes`, drop the oldest
     image entry.
   - **Commit order**, for every mutation:
     1. Write any new image files.
     2. Atomically write the new index.
     3. Only then replace the in-memory list.
     4. Only then delete the files of entries that are no longer listed.
     If step 1 or 2 throws, remove the image files written in step 1, keep the old in-memory list and the old
     index, and rethrow. Deletion failures in step 4 are ignored; the next `claim` removes those files as
     orphans.

7. **Rows: `ClipboardProvider.swift`.** A public enum with a pure function
   `respond(to request: PluginQuery, access: Access, entries: [ClipboardEntry], directory: URL, failure: String?) -> [PluginItem]`.
   `Access` is a public enum: `allowed`, `setup`, or `denied`. Behavior `.alwaysAllow` maps to `allowed`,
   `.alwaysDeny` to `denied`, and anything else to `setup`. Rows use `kind: "Clipboard"`.
   - `setup` → one row, id `access`, title `Turn on clipboard history`, subtitle
     `Copy some text in another app, then press Return here.`, symbol
     `doc.on.clipboard`. Primary `PluginAction(.callback, "authorize", payload: .object([:]))`,
     secondary `PluginAction(.openURL, "x-apple.systempreferences:com.apple.preference.security")`.
   - `denied` → one row, id `access`, title `Clipboard access is off`, subtitle
     `Press Return to open Privacy & Security and choose Always Allow for Odd Frog.`, symbol
     `doc.on.clipboard`. Primary is the same `.openURL` action.
   - `allowed` with a non-nil `failure` → a first row, id `failure`, title `Clipboard history is not being saved`,
     subtitle = `failure`, symbol `exclamationmark.triangle`, no actions. It counts toward `cap`, and the rows
     below follow the normal rules with one slot fewer. It is shown only in `allowed`, the only state that
     captures.
   - `allowed` with no entries at all → one row, id `empty`, title `Clipboard history is empty`, subtitle
     `Copied text and images will appear here.`, symbol `doc.on.clipboard`, no actions.
   - `allowed` otherwise. The filter is `request.query` trimmed. Text entries match with
     `localizedStandardContains` on the full text; image entries match on their title. Let
     `cap = max(1, min(request.maxResults, 50))`. With an empty filter and `cap > 1`, show `prefix(cap - 1)`
     entries plus the clear row. Otherwise, with a filter or with `cap == 1`, show `prefix(cap)` matches and no
     clear row. With `max_results = 1` there is then no way to clear the whole history. That is accepted.
   - Entry row: id = entry id, title `ClipboardEntry.title(for:)`, subtitle = a date label with the same
     rules as `NotesProvider.dateLabel` (Today/Yesterday + short time, else `EEE d MMM`, in
     `request.timeZoneIdentifier`). Text rows use symbol `doc.on.clipboard`. Image rows use symbol `photo`
     and `icon: ClipboardArchive.thumbnailPath(in: directory, id: id)`. Primary `PluginAction(.callback, "copy", payload: {"id": id})`,
     secondary `PluginAction(.callback, "delete", payload: {"id": id})`. Leave `history` unset.
   - Clear row: id `clear`, title `Clear clipboard history`, subtitle
     `Removes \(entries.count) saved entries. What is on the clipboard now stays.`, symbol `trash`,
     primary `PluginAction(.callback, "clear", payload: .object([:]))`.

8. **Handler: `ClipboardHandler.swift`.** A public `actor` conforming to `ProviderHandler`, with
   `init(archive: ClipboardArchive, pasteboard: ClipboardPasteboard, interval: Duration = .milliseconds(500))`.
   The init takes `generation = archive.nextGeneration()`. Other state: `emit`, `closed: Bool`,
   `claimed: Bool`, `failure: String?`, `poll: Task<Void, Never>?`, `lastCount: Int`, `lastBehavior`, and `limits`.
   - `start(emit:)` only stores `emit`. It starts nothing.
   - `initialize`:
     1. If `closed` or `Task.isCancelled`, return `{"apiVersion": 2}` without claiming.
     2. Read `pasteboard.state()` as the baseline (`lastCount`, `lastBehavior`, no content read). It is
        taken *before* claiming, so anything copied from this point on is captured.
     3. `try await archive.claim(generation:directory:limits:)` with `context.storagePath` and
        `ClipboardLimits(settings: context.settings)`. A thrown error propagates, and the coordinator shows
        it as the plugin's failure. If it returns false, return `{"apiVersion": 2}` without polling.
     4. **After that await, check `closed` again.** If shutdown ran in the meantime,
        `await archive.release(generation:)` and return without polling.
     5. Otherwise set `claimed`, start `poll`, and return `{"apiVersion": 2}`.
   - `settings`: rebuild `limits` from the context, `try await archive.configure(generation:limits:)` (which
     trims immediately), and return `{}`.
   - `query`: read `pasteboard.state().behavior`, map it to `Access`, and return
     `ClipboardProvider.respond(…)` with `await archive.entries(generation:)`,
     `URL(fileURLWithPath: context.storagePath)` as the directory, and the handler's `failure`.
   - `activate`:
     - `copy`: look up the entry in `entries(generation:)`, and for images also `imageData(generation:id:)`.
       If either is missing, throw `RPCError("clipboard", "This entry no longer exists.")`. Write with
       `pasteboard.write(text:)` or `write(png:)`. If that returns false, throw
       `RPCError("clipboard", "The clipboard changed while copying. Try again.")` and do not touch the entry.
       Otherwise `try await archive.touch(…)` and return `PluginEffects()`. The marker type keeps the poll
       from recording the write, whichever of the two runs first.
     - `delete`: `try await archive.delete(…)`, then return `PluginEffects(refreshQuery: true)`.
     - `clear`: `try await archive.clear(…)`, then return
       `PluginEffects(notification: "Cleared \(n) clipboard entries.", refreshQuery: true)`.
     - `authorize`: `pasteboard.requestAccess()`, then read `state().behavior`. The notification depends on
       the outcome, and `refreshQuery` is true:
       - `noText` → `Copy some text in another app first, then press Return here again.`
       - `read`, and the behavior is now `.alwaysAllow` → `Clipboard history is on.`
       - `read`, and the behavior is still `.default` → `macOS did not ask for access. Copy some text in another app and try again.`
       - `read`, anything else → `Now set Odd Frog to Always Allow in System Settings › Privacy & Security.`
     - Anything else → `RPCError("action", "Unknown action: …")`.
   - Poll loop (inside `poll`, sleeping `interval` between ticks, stopping on cancellation or `closed`):
     1. Read `state()`. If `behavior != lastBehavior`, emit `queryInvalidated`. If the new behavior is
        `.alwaysAllow`, set `lastCount` to the current count **without reading**, so contents that were on the
        pasteboard before consent are never imported. Store the behavior and continue.
     2. If behavior is not `.alwaysAllow`, or `changeCount == lastCount`, continue.
     3. Set `lastCount = changeCount` before reading, so a failed or denied read is never retried for that
        count.
     4. `capture()`, then read `state()` again. If the count changed in between, discard the capture; the
        next tick sees the new count.
     5. For an image: skip if `limits.captureImages` is false, otherwise run `ClipboardImages.process` in a
        detached task and skip on nil.
     6. If `closed`, stop. Otherwise `try await archive.record(…, generation:, now: Date())`.
        - When it returns true, set `failure = nil` and emit `queryInvalidated`.
        - When it throws, set `failure` to `"The last copy was not saved: \(error)"` and emit
          `queryInvalidated`. The loop goes on, and the count stays seen, so the same clipboard contents are
          never read again. `failure` is cleared only by the next successful `record`.
   - `shutdown()`: set `closed = true`, cancel `poll`, and await its completion. Then
     `await archive.release(generation:)`.
   - Guarantees this gives:
     - A late `initialize` after `shutdown` never claims or polls.
     - An older handler whose `claim` arrives after a newer one's is rejected by generation.
     - A late shutdown of an old handler never unseats the newer owner.
     - A stale handler's reads and writes are no-ops.
   - Limit: after a disable, capture is **best effort until `shutdown()` runs**. The coordinator does not
     await it, so the spec promises no time bound.

9. **`BuiltinProviders.swift`.** Add `import ClipboardPluginCore` and a
   `static let clipboardArchive = ClipboardArchive()`. Register
   `"clipboard": { ClipboardHandler(archive: clipboardArchive, pasteboard: ClipboardPasteboard(name: .general)) }`.
   Every generation shares that one archive, which serializes all reads and writes.

10. **Existing tests.**
    - `Package.swift`: add `"ClipboardPluginCore"` to the `OddFrogCoreTests` dependencies.
    - `BundledPackageTests.shippedFeaturesRunInProcessAndEachCanBeDisabled`:
      - Change `packages.count == 11` to `12` and add `"clipboard": "clip"` to `queries`.
      - Right after `coordinator.builtins = BuiltinProviders.factories`, override the clipboard factory with
        `ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: NSPasteboard.Name("odd-frog-test-\(UUID().uuidString)")))`.
        That needs `import AppKit` and `import ClipboardPluginCore`.
      - A named pasteboard always allows access and the archive is fresh, so the query answers with the
        `empty` row, which has no primary action. Extend the wait condition for this package only: it also
        succeeds when `package.manifest.id == "clipboard"` and the first row's item id is `"empty"`. Add
        `if package.manifest.id == "clipboard" { #expect(rows.first?.item.title == "Clipboard history is empty") }`
        next to the calculator and terminal checks.
      - Change nothing else in the test.
    - `MigrationTests`: change `packages.count == 11` to `12`.

11. **New tests** (`ClipboardPluginTests`, Swift Testing, in the style of `NoteStoreTests`/`NotesProviderTests`,
    with temporary directories under `NSTemporaryDirectory()` removed in `defer`). Tests build sample images
    with `NSBitmapImageRep` (`representation(using: .png/.tiff, properties: [:])`).
    - `ClipboardImagesTests`:
      - A PNG keeps its bytes.
      - A TIFF becomes PNG data with the right width/height.
      - The thumbnail's longest side is ≤ 64 px.
      - `maxOutputBytes: 10` returns nil.
      - Garbage data returns nil.
    - `ClipboardArchiveTests`:
      - Record/list order.
      - Hash dedupe moves to the top without duplicating.
      - Count trim deletes the dropped image files.
      - The total image byte cap evicts the oldest image first; inject a small `maxTotalImageBytes`.
      - `captureImages = false` rejects images.
      - Reconcile drops an entry whose PNG is missing and deletes an unreferenced file.
      - **A corrupt `index.json` makes `claim` throw, and it and every file in `images/` stay byte-for-byte
        unchanged.**
      - **A failed commit.** After a claim, make the directory read-only (`0o555`), restored in `defer`. Then
        `record` throws, and `entries` and `index.json` are unchanged.
      - `clear` empties the index and `images/`.
      - After generation 2 claims, generation 1's `record`/`delete`/`clear`/`configure`/`entries` are no-ops.
      - **Generation 2 claims, then generation 1's `claim` returns false**, and 2 stays the owner.
      - `release` by a stale generation leaves the owner in place.
      - `configure` with a lower count trims immediately.
    - `ClipboardProviderTests`:
      - The setup and denied rows and their actions.
      - The empty row.
      - The failure row comes first and takes one slot of `cap`.
      - `maxResults: 1` → one entry and no clear row.
      - Empty filter → `cap - 1` entries plus the clear row last.
      - Filter → matches only, with no clear row.
      - Image rows carry `icon` and the `photo` symbol.
      - Title rules for multi-line and long text.
    - `ClipboardHandlerTests`. Use `ClipboardPasteboard(name: NSPasteboard.Name("odd-frog-test-\(UUID())"))`,
      `interval: .milliseconds(20)`, and a deadline-based wait helper like `BundledPackageTests.wait`:
      - After `initialize`, text written to the named pasteboard appears in `entries`.
      - Contents present *before* `initialize` are not imported.
      - A PNG written to the pasteboard is recorded as an image with both files on disk.
      - Concealed, transient and file-URL items are skipped.
      - `activate copy` of an image puts PNG data and the marker type on the pasteboard's first item. After several poll
        intervals there is still exactly one entry, and it is on top.
      - **Late initialize.** Call `shutdown()` first, then `handle("initialize")`. The archive stays
        unclaimed: `entries` stays empty after a pasteboard write.
      - **Reload, A then B.** Initialize A, then B, on one archive, then shut A down. B keeps capturing, and
        A's writes are dropped.
      - **Reload, B then A.** Create A, then B. Initialize B, then A. A does not become owner, B keeps
        capturing, and shutting A down leaves B the owner.
      - `settings` with a lower `limit` trims.
      - `authorize` on an empty named pasteboard returns the `noText` notification.
      - **A capture that cannot be saved.** After `initialize`, make the storage directory read-only (`0o555`,
        restored in `defer`) and write text to the pasteboard. `query` then answers with the `failure` row
        first. After restoring permissions and copying new text, the `failure` row is gone and the entry is listed.
      - After `activate copy` of a text entry, the pasteboard's first item carries both `.string` (the text)
        and the marker type.

## Constraints
- Swift 6 strict concurrency must compile without new warnings. `NSPasteboard` and `NSPasteboardItem`
  are used only inside `@MainActor` methods of `ClipboardPasteboard`. Only `Sendable` values
  (`ClipboardCapture`, `Data`, `String`, `Int`) cross actors.
- Match the surrounding code: one type per new file; `public` API where `OddFrogBuiltins` or tests need it; errors as
  `RPCError(code, message)`; JSON through `PluginProtocol.encoder()/decoder()` and `JSONValue`.
- Early returns and `guard … else` bodies are always braced. Follow the Notes plugin's layout, where the
  body goes on its own line.
- Write no comments of any kind in new or edited code: no doc comments, no `// MARK:`, no TODOs.
- No changes to `PluginCoordinator`, `LocalProvider`, `HostServiceRegistry`, `AppDelegate`,
  `ActionExecutor`, or any other plugin. No new host services or capabilities.
- Tests never read or write `NSPasteboard.general`, including through `BuiltinProviders.factories`. They
  use a uniquely named pasteboard only.
- Surgical changes only; do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings beyond the pre-existing one in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`.
- `swift test` passes.

## Manual review
The Acceptance commands test against a named pasteboard, so they prove nothing about capture from the
general pasteboard, the macOS permission flow, or disable. **Treat the feature as unverified until these
steps pass on a real Mac.** Build and launch with `make run`.
1. Settings › Plugins: Clipboard is listed and **off**. Copy some text, then enable Clipboard. Type `clip`:
   the row reads "Turn on clipboard history", and the text copied before enabling never shows up later.
2. With some text copied from another app, press Return on that row. Note whether macOS shows an alert
   and what its buttons say. If the notification or subtitle wording is wrong for them, file a follow-up.
   Also try it once with an empty clipboard or a copied image: the notification asks you to copy text
   first, and no alert appears. Then open System Settings › Privacy & Security, find the pasteboard
   setting for Odd Frog, and choose Always Allow. Note the pane's name and whether a more specific
   `x-apple.systempreferences` anchor exists.
3. Type `clip` again: the row is now "Clipboard history is empty". Nothing that was on the clipboard at
   the moment you allowed access was imported.
4. With the launcher closed, copy text in TextEdit, take a screenshot to the clipboard (⌃⇧⌘4), and copy
   an image in Preview. `clip` lists all three, newest first, with a thumbnail on each image row.
5. Copy a password from a password manager that marks concealed items, and copy a file in Finder. Neither
   appears.
6. Return on the screenshot row, then paste into TextEdit or Preview: an image is pasted. The row moves to
   the top and is not duplicated.
7. Change Settings › Plugins › Clipboard › History size to 2: the list trims to 2 at once. ⌘↩ on a row
   deletes it. The "Clear clipboard history" row empties the list, and the current clipboard still pastes.
8. Quit and relaunch: the history is still there. Disable the plugin, wait a second, copy something new,
   and enable it again: the copy made while disabled is absent. This shows typical behavior only; the
   spec promises no bound on how fast capture stops (Plan 8).
9. In System Settings, switch Odd Frog to Always Deny: `clip` shows "Clipboard access is off", and Return
   opens Privacy & Security.

## Out of scope
- Pasting into the frontmost app (a synthetic ⌘V needs Accessibility), pinning entries, file or
  rich-text entries, and more than one pasteboard item per copy.
- Clearing the current system clipboard.
- Recording which app a copy came from.
- Any change to the coordinator lifecycle (for example, awaiting `stop()` during `reload`).
- Settings UI beyond what `plugin.toml` settings already render.

## Open questions
none
