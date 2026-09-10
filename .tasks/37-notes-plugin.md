# Task: Notes plugin — bundled in-process `note` provider with a plain-text editor

Second of two tasks (36–37). Task 36 must be complete first: this task relies on
`PluginView`, `PluginEffects.view`, `PluginActivation.text`, and the host document window.

## Goal
Typing `note` in the launcher lists existing notes, newest modified first, followed by a
"New note" row; `note <text>` filters notes by title or body and offers "New note “<text>”".
Return on a note opens it in the host document window; Return on "New note" opens an empty (or
prefilled) editor. Edits are saved to one plain-text file per note under the plugin's storage
directory; a never-saved blank draft leaves no file behind. `swift test` passes, and
`make bundle` ships `plugin.toml` for the new package.

## Files
- Plugins/Notes/plugin.toml                                          (create)
- Plugins/Notes/Sources/NotesPluginCore/Note.swift                    (create — value type)
- Plugins/Notes/Sources/NotesPluginCore/NoteStore.swift               (create — file storage)
- Plugins/Notes/Sources/NotesPluginCore/NotesProvider.swift           (create — pure query/response)
- Plugins/Notes/Sources/NotesPluginCore/NotesHandler.swift            (create — in-process provider)
- Plugins/Notes/Tests/NotesProviderTests.swift                        (create)
- Plugins/Notes/Tests/NoteStoreTests.swift                            (create)
- Package.swift                                                       (modify — two targets, one builtin dependency)
- Sources/OddFrogBuiltins/BuiltinProviders.swift                      (modify — register `notes`)
- Tests/OddFrogCoreTests/BundledPackageTests.swift                    (modify — package count and query map)
- docs/plugin-system-rework.md                                        (modify — package table row)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersHandler.swift (read — handler shape to mirror)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift (read — provider conventions)
- Plugins/Reminders/Tests/RemindersProviderTests.swift                (read — test style to mirror)

## Context
- Swift 6 package, macOS 14 target, strict concurrency; tests use the `Testing` framework.
- Bundled plugins are Swift library targets compiled into the host and run in-process. A bundled
  package ships only `plugin.toml`; `make bundle` packages every directory under `Plugins/` with
  `.build/release/OddFrogPackage`. Discovery reads `Plugins/<folder>/plugin.toml`; the folder name
  is irrelevant, the manifest `id` is the key.
- `Sources/OddFrogBuiltins/BuiltinProviders.swift` maps manifest id → `PluginCoordinator.BuiltinProviderFactory`
  (`@Sendable () -> any ProviderHandler`), e.g. `"reminders": { RemindersHandler() }`. The
  `OddFrogBuiltins` target in `Package.swift` depends on `BundledFeatures`, `CalendarPluginCore`,
  `RemindersPluginCore`, `OddFrogCore`, `OddFrogPluginAPI`. Plugin core targets are declared as
  `.target(name: "RemindersPluginCore", dependencies: ["OddFrogPluginAPI", "OddFrogHostServicesAPI"], path: "Plugins/Reminders/Sources/RemindersPluginCore")`
  and their tests as
  `.testTarget(name: "RemindersPluginTests", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Tests")`.
- `ProviderHandler` (`Sources/OddFrogPluginAPI/ProviderHandler.swift`):
  `start(emit:)`, `handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue`,
  `shutdown()`; the first and last have empty default implementations. `RemindersHandler` is an
  `actor` answering `initialize` with `{"apiVersion": 2}`, `settings` with `{}`, `query` by
  decoding `params["input"]` as `PluginQuery`, and throwing `RPCError("method", "Unsupported method: …")`
  otherwise.
- Every request's `params` is `{apiVersion, context: {settings, storagePath, configPath}, input}`.
  `context.storagePath` is `<application support>/odd-frog/v2/plugins/<id>` and is **not created
  by the host**; the provider creates it. `PluginContext` decodes from `params["context"]`.
- `PluginQuery` carries `query` (text after the keyword, trimmed), `fullQuery`, `now`,
  `timeZoneIdentifier`, `maxResults`. Query results are capped twice by the host: `runQuery`
  keeps `prefix(limit)` and `search` keeps `prefix(maxResults)` again, so a row placed after
  `maxResults` matches is dropped. `maxResults` comes from `config.general.maxResults` (default 8).
- `PluginActivation` (task 36) carries `actionID`, `payload`, `item`, `argument`, `text`.
  `PluginEffects(notification:refreshCatalog:refreshQuery:view:)`; `PluginView(kind:id:title:text:placeholder:save:)`
  with `save` a `callback` action. The host applies only `title` from a view returned by a save.
- Manifest rules (`Sources/OddFrogCore/PluginPackage.swift`): exclusive activation needs exactly one
  `keyword` matching `^[a-z][a-z0-9_-]*$`; `mode` is `declarative`, `one-shot`, or `persistent`;
  `capabilities` defaults to `[]`; `catalog`/`background` default false, so a query-only
  persistent provider starts on the first `note` query.
- `BundledPackageTests.shippedFeaturesRunInProcessAndEachCanBeDisabled` asserts
  `packages.count == 9` and has a `queries` dictionary keyed by package id with a query that must
  produce at least one row with a `primary` action within its wait; `rem` and `cal` are there.
- `docs/plugin-system-rework.md` has a package table whose last row is
  `| Reminders | Exclusive keyword \`rem\` | \`rem\` range/filter/labels and requested writes |`.
- Reminders provider conventions to keep: rows capped at `max(1, min(request.maxResults, 50))`,
  trimmed titles with an "Untitled …" fallback, subtitles joined with `" · "`, status rows with a
  fixed id, `Calendar(identifier: .gregorian)` in the request's time zone falling back to `.gmt`.
  `RemindersProviderTests` fixes `now` at `2026-09-09T12:00:00Z`, UTC, `maxResults: 50`.
- Verified today: `swift test` passes with 156 tests before task 36; `make bundle` exits 0.

## Plan
1. `Plugins/Notes/plugin.toml` (create):
   ```toml
   id = "notes"
   name = "Notes"
   version = "0.1.0"
   api_version = 2
   keyword = "note"
   mode = "persistent"
   activation = "exclusive"
   capabilities = []
   ```
2. `Note.swift` (create): `public struct Note: Sendable, Hashable { public let id: String; public var text: String; public var modified: Date }`
   with a memberwise `public init`, plus `public static func title(of text: String) -> String`
   (first non-empty line, trimmed, at most 80 characters, "Untitled" when none) and
   `public static func snippet(of text: String) -> String?` (the first non-empty line after the
   title line, trimmed, at most 80 characters, nil when none).
3. `NoteStore.swift` (create): `public struct NoteStore: Sendable` with `public let directory: URL`.
   - `public init(directory: URL)`.
   - `public func list() throws -> [Note]`: creates the directory if missing, reads every regular
     file named `<uuid>.txt` whose stem parses with `UUID(uuidString:)` (others ignored), decodes
     UTF-8, uses the file modification date, and returns notes sorted by `modified` descending,
     ties by id.
   - `public func read(id: String) throws -> Note`: validates `id` with `UUID(uuidString:)`,
     rejects anything else with `RPCError("params", "Invalid note ID.")`, reads `<directory>/<id>.txt`,
     and throws `RPCError("notes", "This note no longer exists.")` when missing.
   - `public func write(id: String, text: String) throws -> Note`: validates the id the same way;
     writes atomically (`Data.write(to:options: .atomic)`) to `<id>.txt`, and returns the note with
     the fresh modification date. An empty `text` is written as an empty file; the store never
     deletes.
   - `public func newID() -> String { UUID().uuidString.lowercased() }`.
   - Path resolution always builds `<directory>/<validated uuid>.txt`; no other component of the
     id ever reaches the filesystem.
4. `NotesProvider.swift` (create): `public enum NotesProvider` with three pure functions.
   - `public static func respond(to request: PluginQuery, notes: [Note]) -> [PluginItem]`:
     `filter = request.query` trimmed; matches are the notes whose `text` `localizedStandardContains(filter)`
     (all notes when the filter is empty), already in store order. Rows are capped at
     `max(1, min(request.maxResults, 50))`; when the cap is greater than one, at most `cap - 1`
     matches are emitted so the creation row always fits; with a cap of one the creation row is the
     only row. Each note row: `id = note.id`, `title = Note.title(of:)`, `kind: "Note"`,
     `symbol: "note.text"`, subtitle = date label and `Note.snippet(of:)` (when present) joined by
     `" · "`, `primary: PluginAction(.callback, "open", payload: .object(["id": .string(note.id)]))`,
     no secondary, no `history`. The date label uses `Calendar(identifier: .gregorian)` in the
     request's time zone (fallback `.gmt`): "Today HH:mm" / "Yesterday HH:mm" (`timeStyle = .short`)
     when `modified` falls on those days relative to `request.now`, otherwise `EEE d MMM`.
     The creation row is last: `id: "new"`, `symbol: "plus.square"`, `kind: "Note"`; with an empty
     filter `title: "New note"`, `subtitle: "Press Return to start writing."`, payload `{}`; with a
     filter `title: "New note “\(filter)”"`, `subtitle: "Press Return to start a note with this text."`,
     payload `{"text": filter}`. Both use `PluginAction(.callback, "create", payload:)`.
   - `public static func view(for note: Note) -> PluginView`:
     `PluginView(id: note.id, title: Note.title(of: note.text), text: note.text, placeholder: "Start writing…", save: PluginAction(.callback, "save", payload: .object(["id": .string(note.id)])))`.
     A brand-new draft uses the same function with `text` equal to the prefill (possibly empty)
     and the title "New note" when the text is empty.
5. `NotesHandler.swift` (create): `public actor NotesHandler: ProviderHandler` with
   `private var drafts = Set<String>()` (ids issued by `create` that have no file yet).
   `handle` switches on the method:
   - `initialize` → `{"apiVersion": 2}`; `settings` → `{}`.
   - `query` → decode `PluginQuery` from `params["input"]`, build
     `NoteStore(directory: URL(fileURLWithPath: context.storagePath))` from `params["context"]`
     decoded as `PluginContext`, return `.encode(NotesProvider.respond(to:notes: try store.list()))`.
   - `activate` → decode `PluginActivation` from `params["input"]`; switch on `actionID`:
     - `open`: `id = payload["id"].string` (else `RPCError("params", "A note ID is required.")`),
       `store.read(id:)`, return `.encode(PluginEffects(view: NotesProvider.view(for: note)))`.
     - `create`: `id = store.newID()`, insert into `drafts`, text = `payload["text"].string ?? ""`,
       return effects with the draft view (title "New note" when text is empty).
     - `save`: `id` from payload (validated by the store), `text = activation.text ?? ""`. If the
       text is whitespace-only and `drafts.contains(id)` and no file exists, return
       `PluginEffects(view: draft view)` without writing. Otherwise `store.write(id:text:)`,
       remove `id` from `drafts`, and return `PluginEffects(refreshQuery: true, view: NotesProvider.view(for: saved))`.
       An existing note whose text becomes empty is kept as an empty file titled "Untitled".
     - anything else: `RPCError("action", "Unknown action: \(actionID)")`.
   - other methods: `RPCError("method", "Unsupported method: \(method)")`.
   No `start`/`shutdown` work is needed; rely on the protocol's defaults.
6. `Package.swift`: after the `RemindersPluginCore` target add
   `.target(name: "NotesPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Notes/Sources/NotesPluginCore")`;
   add `"NotesPluginCore"` to the `OddFrogBuiltins` dependencies; after `RemindersPluginTests` add
   `.testTarget(name: "NotesPluginTests", dependencies: ["NotesPluginCore", "OddFrogPluginAPI"], path: "Plugins/Notes/Tests")`.
7. `BuiltinProviders.swift`: `import NotesPluginCore` and add `"notes": { NotesHandler() }` after
   the reminders entry.
8. `BundledPackageTests.swift`: change `packages.count == 9` to `10` and add `"notes": "note"`
   to `queries`. The creation row has a `primary` action, so the existing wait condition holds
   with an empty store (the test's `storage: root` puts the notes directory under the temp root).
9. `docs/plugin-system-rework.md`: append `| Notes | Exclusive keyword \`note\` | \`note\` list/filter, plain-text notes in the document window |`
   to the package table, and add `NotesPluginCore` to the sentence listing the libraries
   `OddFrogBuiltins` links.
10. Tests.
    - `Plugins/Notes/Tests/NotesProviderTests.swift`: `struct NotesProviderTests` with a fixed
      `now` of `2026-09-09T12:00:00Z`, UTC, helper `request(_ query:, maxResults:)` and
      `note(_ id:, _ text:, modified:)`. Cover: empty query lists all notes in given order and ends
      with "New note" carrying `create` with an empty payload; a filter matches title and body,
      case-insensitively, and the last row is `New note “<filter>”` with `{"text": filter}`;
      `maxResults: 3` with five notes yields two note rows plus the creation row; `maxResults: 1`
      yields only the creation row; `maxResults: 50` with 60 notes yields 49 note rows plus the
      creation row; title falls back to "Untitled" for whitespace text and truncates at 80
      characters; the snippet is the second non-empty line; date labels give "Today", "Yesterday",
      and `EEE d MMM`; `view(for:)` builds a `callback` save whose payload carries the id and whose
      title matches the first line; a `PluginEffects` with the view round-trips through
      `JSONValue.encode`/`decode`.
    - `Plugins/Notes/Tests/NoteStoreTests.swift`: on a temporary directory: `list()` creates the
      directory and returns `[]`; `write` then `read` round-trips text and the id; `list()` orders
      by modification date descending (set distinct `modificationDate` attributes explicitly);
      files with non-UUID names and non-`.txt` extensions are ignored; `read`/`write` throw
      `RPCError` for `"../x"`, `"a/b"`, and `"not-a-uuid"`; writing empty text keeps the file;
      `newID()` parses as a UUID and is lowercase.
    - Handler behaviour (`create` then blank `save` leaves no file; `open` of a missing id fails
      with code `notes`) is covered in `NoteStoreTests` through a small `NotesHandler` test that
      calls `handle("activate", …)` with a hand-built params object whose `context.storagePath`
      is the temp directory and a `ProviderOperation(id:service:emit:)` (public init in
      `Sources/OddFrogPluginAPI/ProviderServer.swift`) whose `service` closure throws.

## Constraints
- No comments, doc comments, or section banners anywhere in new or edited code.
- Always brace conditionals and returns.
- Swift 6 strict concurrency: `Note` and `NoteStore` are `Sendable`; the handler is an actor.
- `NotesPluginCore` depends only on `OddFrogPluginAPI` (no `OddFrogCore`, no AppKit, no
  `OddFrogHostServicesAPI`); the host must not import `NotesPluginCore` outside `OddFrogBuiltins`.
- No note text, titles, or ids in `Log.write`, notifications, or launcher history (`history` stays nil).
- Only ids that parse as UUIDs reach the filesystem; never build a path from raw payload text.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes from the repo root, including `NotesProviderTests` and `NoteStoreTests`,
  and `shippedFeaturesRunInProcessAndEachCanBeDisabled` passes with ten packages.
- `make bundle` exits 0 and `build/OddFrog.app/Contents/Resources/Plugins/notes/plugin.toml` exists.
- Manual, after `scripts/release.sh`: open the launcher, type `note`, see "New note", press
  Return; a document window opens with the placeholder. Type two lines, wait a second, close the
  window with Esc; `note` now lists the note titled with the first line and a "Today HH:mm" subtitle;
  `note <word from line two>` filters to it and still shows the creation row; Return reopens the
  text; opening the same note again while its window is open only refocuses the window; open a
  second note and the first is saved before the window switches. Open "New note", type nothing,
  close it: `ls "$HOME/Library/Application Support/odd-frog/v2/plugins/notes"` shows no new file.
  Choose Reload Plugins from the status menu while a note is open with unsaved text: the window
  shows "Notes was reloaded…", editing stays possible, and "Discard and Close" is the only button.

## Out of scope
- Deleting or renaming notes, pinning, tags, folders, Markdown, or any styling.
- A note-body index or caching (every query re-reads the directory; fine for hundreds of notes).
- A `copy` secondary action or exposing note bodies in query rows.
- iCloud, external file watching, or reacting to edits made outside the app.
- Changing the document window, the coordinator, or any other plugin.

## Open questions
none
