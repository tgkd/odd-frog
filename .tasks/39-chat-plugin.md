# Task: Chat plugin — bundled in-process `chat` provider over an OpenAI-compatible endpoint

Second of two tasks (38–39). Task 38 must be complete first: this task relies on
`PluginView.Kind.chat`, the chat `PluginView` init, `PluginMessage`, `PluginMessageDelta`,
`ProviderOperation.emit(_:params:)`, and the host chat window.

## Goal
Typing `chat` in the launcher lists saved conversations, newest first, followed by a "New chat"
row; `chat <text>` filters conversations and offers "Ask “<text>”". Return on a conversation opens
it in the host chat window; Return on "Ask" opens a new chat and the host sends the text at once.
Each send streams the reply token by token from an OpenAI-compatible `chat/completions` endpoint
(Ollama, LM Studio, OpenAI, or any proxy) configured in the plugin's settings, then persists the
conversation as one JSON file under the plugin's storage directory. Conversations can be deleted
from the launcher. `swift test` passes without network access, and `make bundle` ships the new
`plugin.toml`.

## Files
- Plugins/Chat/plugin.toml                                          (create)
- Plugins/Chat/Sources/ChatPluginCore/Conversation.swift            (create — value type)
- Plugins/Chat/Sources/ChatPluginCore/ConversationStore.swift       (create — JSON file storage)
- Plugins/Chat/Sources/ChatPluginCore/ChatProvider.swift            (create — pure query/response and view building)
- Plugins/Chat/Sources/ChatPluginCore/ChatBackend.swift             (create — backend protocol, request model, OpenAI-compatible implementation, SSE parsing)
- Plugins/Chat/Sources/ChatPluginCore/ChatHandler.swift             (create — in-process provider)
- Plugins/Chat/Tests/ChatProviderTests.swift                        (create)
- Plugins/Chat/Tests/ConversationStoreTests.swift                   (create)
- Plugins/Chat/Tests/ChatBackendTests.swift                         (create)
- Plugins/Chat/Tests/ChatHandlerTests.swift                         (create)
- Package.swift                                                     (modify — two targets, one builtin dependency)
- Sources/OddFrogBuiltins/BuiltinProviders.swift                    (modify — register `chat`)
- Tests/OddFrogCoreTests/BundledPackageTests.swift                  (modify — package count and query map)
- docs/plugin-system-rework.md                                      (modify — package table row)
- Plugins/Notes/Sources/NotesPluginCore/NotesHandler.swift          (read — handler shape to mirror)
- Plugins/Notes/Sources/NotesPluginCore/NoteStore.swift             (read — store conventions to mirror)
- Plugins/Notes/Sources/NotesPluginCore/NotesProvider.swift         (read — row and view conventions)
- Plugins/Notes/Tests/NoteStoreTests.swift                          (read — test style, `ProviderOperation` fixture)
- Plugins/Shared/Sources/BundledFeatures/CurrencyRates.swift        (read — the only existing `URLSession` use)
- .tasks/38-chat-view-and-window.md                                 (read — the host contract this plugin targets)

## Context
- Swift 6 package, macOS 14 target, strict concurrency; tests use the `Testing` framework
  (`@Test`, `#expect`, `#require`). No Xcode project: `swift build`, `swift test`, `make bundle`.
- Bundled plugins are Swift library targets compiled into the host and run in-process. A bundled
  package ships only `plugin.toml`; `make bundle` packages every directory under `Plugins/`.
  Discovery reads `Plugins/<folder>/plugin.toml`; the manifest `id` is the key.
- `Package.swift` declares plugin cores as
  `.target(name: "NotesPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Notes/Sources/NotesPluginCore")`
  and tests as
  `.testTarget(name: "NotesPluginTests", dependencies: ["NotesPluginCore", "OddFrogPluginAPI"], path: "Plugins/Notes/Tests")`.
  `OddFrogBuiltins` depends on `BundledFeatures`, `CalendarPluginCore`, `RemindersPluginCore`,
  `NotesPluginCore`, `OddFrogCore`, `OddFrogPluginAPI`.
- `Sources/OddFrogBuiltins/BuiltinProviders.swift` maps manifest id → factory, e.g.
  `"notes": { NotesHandler() }`.
- `Tests/OddFrogCoreTests/BundledPackageTests.swift`: `shippedFeaturesRunInProcessAndEachCanBeDisabled`
  asserts `packages.count == 10` and drives one query per package from the map
  `["applications": "Safari", ..., "notes": "note"]`; each package is reloaded alone with
  `coordinator.builtins = BuiltinProviders.factories` and queried; a provider failure fails the test.
  A `chat` query must therefore succeed with no network: listing conversations never touches the
  backend.
- `docs/plugin-system-rework.md` has a package table; the Notes row is
  `| Notes | Exclusive keyword \`note\` | \`note\` list/filter, plain-text notes in the document window |`.
- Manifest rules (`Sources/OddFrogCore/PluginPackage.swift`): exclusive activation needs exactly one
  `keyword` matching `^[a-z][a-z0-9_-]*$`; `mode` is `declarative`, `one-shot`, or `persistent`;
  settings have `key`, `title`, `type` (`boolean`, `string`, `number`, `choice`, `folders`) and
  `default`. There is no secret type: a `string` setting renders as a plain `NSTextField` in the
  Plugins pane. Validated defaults and overrides arrive in `context.settings` on every request.
- `ProviderHandler` (`Sources/OddFrogPluginAPI/ProviderHandler.swift`): `start(emit:)`,
  `handle(_ method:params:operation:) async throws -> JSONValue`, `shutdown()`. `NotesHandler` is
  an `actor` answering `initialize` with `{"apiVersion": 2}`, `settings` with `{}`, `query` by
  decoding `params["input"]` as `PluginQuery`, `activate` by decoding `PluginActivation`, and
  throwing `RPCError("method", "Unsupported method: …")` otherwise. It keeps a `drafts` set so a
  never-saved draft leaves no file behind.
- Every request's `params` is `{apiVersion, context: {settings, storagePath, configPath}, input}`.
  `context.storagePath` is `<application support>/odd-frog/v2/plugins/<id>` and is not created by
  the host. `PluginContext` decodes from `params["context"]`.
- After task 38: `PluginView(id:title:messages:placeholder:prompt:send:)` builds a chat view;
  `PluginMessage(id:role:text:)` with `Role` `user`/`assistant`; `PluginMessageDelta(viewID:messageID:delta:)`;
  `operation.emit("messageDelta", params: try .encode(delta))` streams to the host while an
  `activate` runs. The host sends `prompt` immediately after opening a chat view, invokes `send`
  with the input in `activation.text`, replaces the transcript with the `messages` of the returned
  view, and restores the draft when the callback throws. The host treats `CancellationError` as
  "Stopped." and any other error as "Send failed: …". In-process cancellation is cooperative: the
  host cancels the Swift task running `handle`, so `URLSession` calls and `Task.checkCancellation()`
  inside the handler observe it.
- The only existing HTTP call is `ExchangeRateAPIProvider.fetchRates` using
  `URLSession.shared.data(from:)`; nothing in the repo parses server-sent events yet.
  `URLSession.bytes(for:)` returns `(URLSession.AsyncBytes, URLResponse)`; `bytes.lines` yields
  lines without terminators, which is what SSE parsing needs.
- OpenAI-compatible streaming contract targeted here: `POST {base_url}/chat/completions` with JSON
  `{"model": ..., "stream": true, "messages": [{"role": "system"|"user"|"assistant", "content": ...}]}`,
  header `Authorization: Bearer <key>` when a key is set, `Content-Type: application/json`. The
  response body is `text/event-stream`: lines `data: {...}` where the JSON has
  `choices[0].delta.content` (string or absent), comment lines starting with `:`, blank separators,
  and a final `data: [DONE]`. Ollama (`http://localhost:11434/v1`), LM Studio
  (`http://localhost:1234/v1`) and OpenAI (`https://api.openai.com/v1`) all follow this.

## Plan
1. `Plugins/Chat/plugin.toml`:
   ```toml
   id = "chat"
   name = "Chat"
   version = "0.1.0"
   api_version = 2
   keyword = "chat"
   mode = "persistent"
   activation = "exclusive"
   capabilities = []

   [[settings]]
   key = "base_url"
   title = "API base URL"
   type = "string"
   default = "http://localhost:11434/v1"

   [[settings]]
   key = "api_key"
   title = "API key (leave empty for local servers)"
   type = "string"
   default = ""

   [[settings]]
   key = "model"
   title = "Model"
   type = "string"
   default = "llama3.2"

   [[settings]]
   key = "system_prompt"
   title = "System prompt"
   type = "string"
   default = ""
   ```
2. `Conversation.swift`: `public struct Conversation: Codable, Sendable, Hashable` with `id: String`,
   `title: String`, `created: Date`, `modified: Date`, `messages: [PluginMessage]`, memberwise init.
   `public static func title(from text: String) -> String`: first non-empty line, whitespace
   collapsed, truncated to 60 characters, `"New chat"` when empty.
3. `ConversationStore.swift`: `public struct ConversationStore: Sendable` mirroring `NoteStore`:
   `init(directory:)`; `list() throws -> [Conversation]` (creates the directory, reads every
   `<uuid>.json` that decodes, sorted by `modified` descending then `id`); `read(id:) throws`
   (`RPCError("chat", "This conversation no longer exists.")` when missing); `write(_:) throws`
   (atomic, `PluginProtocol.encoder()`); `delete(id:) throws`; `exists(id:) throws -> Bool`;
   `newID() -> String` (lowercased UUID). Invalid IDs throw `RPCError("params", "Invalid conversation ID.")`.
   Files that fail to decode are skipped by `list`, never deleted.
4. `ChatProvider.swift`: `public enum ChatProvider`.
   - `respond(to request: PluginQuery, conversations: [Conversation]) -> [PluginItem]`: filter by
     `title` or any message `text` with `localizedStandardContains`; `cap = max(1, min(request.maxResults, 50))`;
     rows for the first `cap - 1` matches with `id` = conversation id, `title`, `subtitle` =
     "<date label> · <n> messages" using the same `dateLabel` logic as `NotesProvider`
     (copy it; it is private there), `kind: "Chat"`, `symbol: "bubble.left.and.bubble.right"`,
     `primary` = callback `open` with `{"id"}`, `secondary` = callback `delete` with `{"id"}`.
     Last row: `id "new"`, symbol `"plus.bubble"`, kind `"Chat"`; with an empty filter the title
     is "New chat", subtitle "Press Return to start a conversation.", primary callback `create`
     with `{}`; otherwise title "Ask “<filter>”", subtitle "Press Return to send this message.",
     primary callback `create` with `{"text": filter}`.
   - `view(for conversation: Conversation, prompt: String? = nil) -> PluginView`: chat view with
     `id` = conversation id, `title` = conversation title, `messages`, `placeholder: "Message…"`,
     `prompt`, `send` = callback `send` with `{"id"}`.
5. `ChatBackend.swift`:
   - `public struct ChatRequest: Sendable, Equatable { baseURL: URL, apiKey: String, model: String, systemPrompt: String, messages: [PluginMessage] }`.
   - `public protocol ChatBackend: Sendable { func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error> }`.
   - `public struct OpenAICompatibleBackend: ChatBackend` with `init(session: URLSession = .shared)`.
     `public static func urlRequest(for request: ChatRequest) throws -> URLRequest`: URL is
     `baseURL.appendingPathComponent("chat/completions")`, method POST, JSON body as described
     in Context (system message first only when `systemPrompt` is non-blank; roles map to
     `user`/`assistant`), `Authorization` header only when `apiKey` is non-empty, `Accept: text/event-stream`.
     `stream(_:)`: `session.bytes(for:)`; a non-2xx status reads up to 2 KiB of the body and throws
     `RPCError("chat", "HTTP <status> from <host>: <body>")`; otherwise iterate `bytes.lines`,
     yield each non-nil `delta(fromLine:)`, finish on `[DONE]` or EOF, propagate errors.
   - `public static func delta(fromLine line: String) -> String?`: `nil` for blank lines, lines
     starting with `:`, lines not starting with `data:`, and `data: [DONE]`; otherwise decode the
     JSON after `data:` (leading space optional) and return `choices[0].delta.content` when it is
     a non-empty string; malformed JSON returns `nil` (a malformed line is skipped, not fatal).
     A `data:` line carrying `{"error": {"message": ...}}` is surfaced: expose it as
     `public enum StreamLine { case delta(String), error(String), done, skip }` from
     `public static func parse(line:) -> StreamLine`, with `delta(fromLine:)` a thin wrapper;
     `stream` throws `RPCError("chat", message)` on `.error`.
6. `ChatHandler.swift`: `public actor ChatHandler: ProviderHandler`, `init(backend: any ChatBackend = OpenAICompatibleBackend())`,
   `private var drafts = Set<String>()`. Methods as in `NotesHandler`. `activate` cases:
   - `open` `{id}`: `view(for: try store.read(id:))`.
   - `create` `{text?}`: `id = store.newID()`, insert into `drafts`, return `view(for: Conversation(id:, title: "New chat", created: now, modified: now, messages: []), prompt: text)`.
     Nothing is written.
   - `send` `{id}` with `activation.text`: trim; empty text throws `RPCError("params", "Nothing to send.")`.
     Load the conversation from the store, or an empty one when `id` is in `drafts`; otherwise
     `read` throws. Resolve settings from `params["context"]`: `base_url` must parse as a URL with
     a scheme and host, else `RPCError("chat", "Set a valid API base URL in Chat settings.")`;
     `model` non-blank, else `RPCError("chat", "Set a model name in Chat settings.")`. Append the
     user message (`PluginMessage(id: store.newID(), role: .user, text:)`), build the
     `ChatRequest`, and stream: `replyID = store.newID()`; for every chunk
     `try Task.checkCancellation()`, append to `reply`, and
     `try await operation.emit("messageDelta", params: .encode(PluginMessageDelta(viewID: id, messageID: replyID, delta: chunk)))`.
     When the stream ends, append `PluginMessage(id: replyID, role: .assistant, text: reply)`;
     if `reply` is empty throw `RPCError("chat", "The model returned no text.")`. Set `title`
     from the first user message when the conversation was a draft or titled "New chat", set
     `modified`, `write`, remove from `drafts`, and return
     `PluginEffects(refreshQuery: true, view: ChatProvider.view(for: saved))`. Any error before
     the write propagates unchanged (the host restores the draft); nothing partial is written.
   - `delete` `{id}`: `store.delete(id:)`, remove from `drafts`, return
     `PluginEffects(notification: "Conversation deleted.", refreshQuery: true)`.
   - Unknown action: `RPCError("action", "Unknown action: …")`.
7. `Package.swift`: add `ChatPluginCore` (`dependencies: ["OddFrogPluginAPI"]`, path
   `Plugins/Chat/Sources/ChatPluginCore`) and `ChatPluginTests` (`dependencies: ["ChatPluginCore", "OddFrogPluginAPI"]`,
   path `Plugins/Chat/Tests`); add `ChatPluginCore` to `OddFrogBuiltins` dependencies.
   `BuiltinProviders.swift`: `import ChatPluginCore` and `"chat": { ChatHandler() }`.
8. `Tests/OddFrogCoreTests/BundledPackageTests.swift`: `packages.count == 11`; add `"chat": "chat"`
   to the query map. `docs/plugin-system-rework.md`: add
   `| Chat | Exclusive keyword \`chat\` | \`chat\` list/filter, streamed conversations in the chat window over an OpenAI-compatible API |`
   after the Notes row and add `ChatPluginCore` to the sentence listing linked cores.
9. Tests (all offline).
   - `ChatProviderTests`: empty query lists conversations newest first and ends with "New chat";
     a filter matches title and message bodies case-insensitively and yields "Ask “…”" with the
     text payload; `maxResults` caps rows keeping the last row; `view(for:prompt:)` has
     `kind == .chat`, the conversation's messages, `placeholder == "Message…"`, `prompt`, and
     `send == PluginAction(.callback, "send", payload: .object(["id": .string(id)]))`.
   - `ConversationStoreTests`: `list` creates the directory and starts empty; `write`/`read`
     round-trip messages and dates; ordering by `modified`; `delete` removes the file; an
     undecodable `.json` is skipped; an invalid id throws.
   - `ChatBackendTests`: `parse(line:)` covers blank, comment, `data: [DONE]`, a content delta,
     a delta without `content`, malformed JSON, and an error object; `urlRequest(for:)` builds the
     URL, method, headers (Authorization present only with a key), and a body whose decoded
     messages start with the system prompt only when it is non-blank.
   - `ChatHandlerTests`: a `FakeBackend` actor implementing `ChatBackend` that records the last
     request and yields configured chunks or throws. Build `params` like `NoteStoreTests`
     (`PluginContext(settings: [...], storagePath:)`), and a `ProviderOperation` whose `emit`
     records `(method, params)` into an actor. Assert: `create` with text returns a chat view with
     `prompt == "hi"` and writes no file; `send` on that draft emits one `messageDelta` per chunk
     with `viewID` = the draft id and one shared `messageID`, writes the file, and returns a view
     whose messages are `[user "hi", assistant "Hello"]` with title "hi" and `refreshQuery == true`;
     the request the backend received carries the system prompt and model from settings; a
     throwing backend propagates the error and leaves no file; `send` with an unknown id throws;
     an invalid `base_url` throws before the backend is called; `delete` removes the file and
     sets `refreshQuery`.

Approach notes: the conversation is written only after a complete reply so a failed or stopped
send never persists a half turn; the host already restores the user's draft in that case. The
backend is a protocol so tests and a future Anthropic-native backend need no changes elsewhere.
The API key lives in an ordinary string setting because the host has no secret setting type; a
`secret` type with a secure field is a separate host task.

## Constraints
- No comments, doc comments, or section banners in new or edited code.
- Always brace conditionals and returns; never a bare single-expression `if`/`guard` body.
- `ChatPluginCore` depends only on `OddFrogPluginAPI` and Foundation; no AppKit, no `OddFrogCore`.
- Swift 6 strict concurrency: `ChatHandler` is an actor; the backend and store are `Sendable`;
  no `@unchecked Sendable`.
- Tests must not touch the network; `OpenAICompatibleBackend.stream` is exercised only through
  its pure `parse`/`urlRequest` helpers.
- No message text or API keys in `Log.write`, errors, or notifications beyond the HTTP error
  body excerpt described in step 5.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds from the repo root with no new warnings.
- `swift test` passes from the repo root, including the four new `ChatPluginTests` suites and
  the updated `BundledPackageTests`.
- `make bundle` exits 0 and `build/plugins` (or the app bundle's `Plugins` directory) contains a
  `chat` package with only `plugin.toml`.
- Manual, after `make run` with a local OpenAI-compatible server running (for example Ollama with
  `llama3.2` pulled): type `chat hello`, press Return; the chat window opens, "…" appears and is
  replaced by a streamed reply; a second message continues the conversation; `chat` then lists it
  with its title; Cmd+Return on the row deletes it. With the server stopped, sending shows
  "Send failed: …" in the status bar and the draft is back in the input.

## Out of scope
- A `secret` setting type or Keychain storage for the API key.
- Anthropic-native or other non-OpenAI-shaped backends.
- Tool use, images, attachments, token counting, or model listing.
- Exporting conversations, renaming them from the UI, or a Settings pane beyond the generated one.
- Any change to the host chat window, `PluginView`, or the coordinator (task 38 owns them).

## Open questions
none
