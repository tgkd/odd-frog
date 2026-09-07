# Task: Plugin system rework 4/13 — provider processes and the plugin runtime

Fourth of thirteen tasks (19–31). Requires tasks 19–21: the wire types and `PluginServer` in
`OddFrogPluginAPI`, the generic `LauncherItem`, `HostServices` with its `callback` closure, and the
`PluginRegistry`.

## Goal
The host can run plugin provider executables: persistent providers speak newline-delimited JSON
over stdin/stdout for the life of the app, one-shot providers are spawned per request, both are
bounded by deadlines and a 4 MiB line limit, and any malformed output, crash, or timeout marks the
plugin failed without an automatic restart. A `PluginRuntime` owns one process per enabled package,
publishes their catalogs into the launcher, answers queries with transient items, forwards
`activate`/`configure`/`links.*`, and honours `catalog_changed` and `refresh` events. Real fixture
providers exercise every failure path in tests.

## Files
- Sources/OddFrogCore/ProviderProcess.swift                (create — one process, framing, deadlines)
- Sources/OddFrogCore/PluginRuntime.swift                  (create — lifecycle across packages)
- Sources/OddFrogCore/PluginDiscovery.swift                (modify — nothing structural; `PluginStatus` reused)
- Sources/OddFrog/AppDelegate.swift                        (modify — own a runtime, merge catalogs, wire callback + reload)
- Tests/OddFrogCoreTests/Fixtures/providers/echo.py        (create — persistent provider)
- Tests/OddFrogCoreTests/Fixtures/providers/oneshot.py     (create)
- Tests/OddFrogCoreTests/Fixtures/providers/malformed.py   (create)
- Tests/OddFrogCoreTests/Fixtures/providers/crash.py       (create)
- Tests/OddFrogCoreTests/Fixtures/providers/slow.py        (create)
- Tests/OddFrogCoreTests/Fixtures/providers/oversized.py   (create)
- Tests/OddFrogCoreTests/Fixtures/providers/event.py       (create)
- Tests/OddFrogCoreTests/Fixtures/providers/wrongapi.py    (create)
- Tests/OddFrogCoreTests/ProviderProcessTests.swift        (create)
- Tests/OddFrogCoreTests/PluginRuntimeTests.swift          (create)
- Sources/OddFrogPluginAPI/Protocol.swift                  (read — Request/Response/Event, params/results, `Wire`, `Method`, `EventName`)
- Sources/OddFrog/TerminalLauncher.swift                   (read — `TerminalLauncher.run(_:_:)` shows the Process + Pipe idiom used in the host)
- Sources/OddFrog/HostServices.swift                       (read — `BackgroundRun.attach` shows `readabilityHandler` streaming)

## Context
- Wire contract (task 19, fixed): request `{"id", "method", "params"}`, response `{"id", "result"}`
  or `{"id", "error": {"code", "message"}}`, event `{"event", "params"?}`; `Wire.encodeLine`,
  `Wire.decode`, `Wire.decodeParams`, `Wire.encodeResult`, `Wire.maxLineBytes = 4 MiB`; `Method`
  constants (`initialize, catalog, query, activate, configure, cancel, shutdown, links.list,
  links.create, links.update, links.delete`); typed params/results (`InitializeParams {api,
  hostVersion, pluginId, settings, configDir, dataDir}`, `InitializeResult {api, name, version}`,
  `CatalogResult {items}`, `QueryParams {queryId, text, input, keyword, settings}`, `QueryResult
  {items}`, `ActivateParams`, `ActivateResult`, `ConfigureParams {settings}`, `CancelParams {queryId}`,
  `Link`, `LinksListResult`, `LinkCreateParams`, `LinkUpdateParams`, `LinkDeleteParams`,
  `LinkResult`); `EventName.catalogChanged = "catalog_changed"`, `EventName.refresh = "refresh"`;
  `PluginAPI.version = 1`.
- `PluginManifest.provider: ProviderSpec {mode: .persistent|.oneshot, executable: String (relative to
  the package directory), arguments: [String], catalog: Bool}`; `manifest.query: QuerySpec?`;
  `manifest.effectiveSettings(stored:)` and `settingsJSON(_:)` produce the `[String: JSONValue]` sent
  to providers. `PluginPackage {id, manifest, directory, source, error}`; `PluginStatus {disabled,
  idle, running, failed(String), invalid(String)}`; `PluginRegistry` exposes `enabledPackages()`,
  `package(for:)`, `status(for:)`, `onChange`.
- `HostServices.callback: (String, ActivateParams) async throws -> ActivateResult` (task 20) is how a
  `callback` action reaches its provider. `LauncherItem(pluginID:item:transient:)`.
- Deadlines (fixed): initialize 30 s, catalog 30 s, query 2 s, activate 30 s, links 10 s, shutdown
  grace 2 s before SIGKILL. Diagnostics: provider stderr lines are logged by the host as
  `plugin <id>: <line>`.
- Directories passed to `initialize` (fixed, created if missing before starting a provider):
  `config_dir = ~/.config/odd-frog/v2/plugins/<id>` (`ConfigLoader.defaultDirectory` +
  `v2/plugins/<id>`) and `data_dir = ~/Library/Application Support/odd-frog/v2/plugins/<id>`. Task 24
  moves the rest of the host to `v2`; the runtime uses these paths from the start.
- Start rules (fixed): a provider with `catalog = true` starts as soon as its package is enabled; a
  provider without a catalog starts lazily on its first query/activate; a persistent provider stays
  alive until disabled, reloaded, or app exit; a failed provider is not restarted until an explicit
  reload. Results from a provider generation that has since been stopped or reloaded are discarded.
  Items whose action (or secondary) requires a service not in `manifest.uses` are dropped at ingest
  with one log line per plugin and result.
- `/usr/bin/python3` (3.9) exists on the development machine; fixtures use it with a
  `#!/usr/bin/env python3` shebang. SwiftPM copies `Fixtures` with `.copy`, which does not guarantee
  the executable bit, so tests copy each fixture into a temporary package directory and `chmod 755`
  it via `FileManager.default.setAttributes([.posixPermissions: 0o755], …)`.
- Host `Log.write` exists only in the app target; Core code takes a `log: @Sendable (String) -> Void`
  closure (default `{ NSLog("odd-frog: %@", $0) }`).

## Plan
1. `Sources/OddFrogCore/ProviderProcess.swift` (import Foundation, OddFrogPluginAPI):
   ```swift
   public enum ProviderFailure: Error, Equatable, Sendable {
       case timeout(String)
       case malformed(String)
       case oversized
       case exited(Int32)
       case notRunning
       case spawn(String)
       case remote(ResponseError)
       case apiMismatch(Int)
   }
   public enum ProviderDeadline {
       public static let initialize: TimeInterval = 30
       public static let catalog: TimeInterval = 30
       public static let query: TimeInterval = 2
       public static let activate: TimeInterval = 30
       public static let links: TimeInterval = 10
       public static let shutdown: TimeInterval = 2
   }
   public actor ProviderProcess {
       public let executable: URL
       public let arguments: [String]
       public let directory: URL
       public nonisolated let events: AsyncStream<Event>
       public init(executable: URL, arguments: [String], directory: URL, log: @escaping @Sendable (String) -> Void)
       public func start() throws
       public var isRunning: Bool
       public func send<P: Encodable, R: Decodable>(_ method: String, params: P, result: R.Type, deadline: TimeInterval) async throws -> R
       public func notify<P: Encodable>(_ method: String, params: P) async
       public func shutdown() async
       public func terminate()
       public static func runOnce<P: Encodable, R: Decodable>(executable: URL, arguments: [String], directory: URL, method: String, params: P, result: R.Type, deadline: TimeInterval, log: …) async throws -> R
   }
   ```
   `timeout` carries the method name, `malformed` the decoding message. `start()` throws `.spawn`
   when the executable cannot be launched. `notify` assigns an id and ignores the response (used for
   `cancel`). `shutdown()` sends `shutdown`, waits `ProviderDeadline.shutdown`, then SIGKILLs.
   `terminate()` SIGKILLs at once and fails pending requests with `.notRunning`.
   Implementation notes: `Process` with three `Pipe`s, `currentDirectoryURL = directory`,
   `environment = ProcessInfo.processInfo.environment`. stdout `readabilityHandler` appends to a
   buffer and splits on `\n`; each complete line is decoded as `Response` first and, if it has no
   `id` but an `event`, as `Event` (decode `Event` when the line's object lacks `id`); undecodable →
   fail the provider with `.malformed(<message>)`. A buffer exceeding `Wire.maxLineBytes` without a
   newline → `.oversized`. Both failures terminate the process, fail all pending continuations, and
   finish the events stream. stderr lines → `log("plugin stderr: <line>")` (the runtime prefixes the
   id). `terminationHandler` → fail pending with `.exited(status)`, finish events. `send` assigns the
   next id, writes the line under actor isolation, stores a `CheckedContinuation` keyed by id, and
   races it against `Task.sleep(deadline)`; on timeout the provider is terminated and the caller gets
   `.timeout(method)`. A response whose id has no pending continuation is ignored. A response with
   `error` → `.remote`. `runOnce` spawns, writes one request line, closes stdin, reads stdout to EOF
   (bounded), takes the first line as the `Response`, applies the same deadline/oversize/malformed
   rules, and waits for exit.

2. `Sources/OddFrogCore/PluginRuntime.swift`:
   ```swift
   @MainActor public final class PluginRuntime {
       public var hostVersion = "0.2.0"
       public var configRoot: URL
       public var dataRoot: URL
       public var settingsProvider: (PluginPackage) -> [String: JSONValue]
       public var log: @Sendable (String) -> Void
       public var onCatalogChanged: ((String) -> Void)?
       public var onRefreshRequested: ((String) -> Void)?
       public var onStatusChanged: ((String, PluginStatus) -> Void)?
       public init(log: …)
       public func sync(enabled packages: [PluginPackage]) async
       public func stop(_ id: String) async
       public func reload(_ package: PluginPackage) async
       public func stopAll() async
       public func status(for id: String) -> PluginStatus?
       public func catalog(for id: String) -> [LauncherItem]
       public func catalogItems() -> [LauncherItem]
       public func query(_ id: String, queryID: Int, text: String, input: String, keyword: String?) async throws -> [LauncherItem]
       public func cancel(_ id: String, queryID: Int) async
       public func activate(_ id: String, params: ActivateParams) async throws -> ActivateResult
       public func configure(_ id: String, settings: [String: JSONValue]) async
       public func linksList(_ id: String) async throws -> [Link]
       public func linksCreate(_ id: String, _ params: LinkCreateParams) async throws -> Link
       public func linksUpdate(_ id: String, _ params: LinkUpdateParams) async throws -> Link
       public func linksDelete(_ id: String, _ params: LinkDeleteParams) async throws
   }
   ```
   `configRoot` defaults to `ConfigLoader.defaultDirectory/v2/plugins`, `dataRoot` to
   `~/Library/Application Support/odd-frog/v2/plugins`; `settingsProvider` defaults to
   `manifest.settingsJSON(manifest.effectiveSettings(stored: [:]))`. `sync(enabled:)` starts catalog
   providers for packages it does not know yet and stops providers whose package is gone, disabled,
   or now points at a different directory. `reload` stops, forgets any failure, and restarts a
   catalog provider (lazy providers restart on their next query). `status(for:)` is nil for ids the
   runtime never saw. `catalogItems()` returns every running provider's catalog in package order.
   Internal state per id: package, `ProviderProcess?`, `generation: Int`, `catalog: [LauncherItem]`,
   `status`. `start` (private): create the two directories, spawn, `initialize` with
   `InitializeParams(api: PluginAPI.version, hostVersion:, pluginId:, settings:, configDir:, dataDir:)`;
   a result whose `api != PluginAPI.version` → terminate, `.failed("plugin needs API n")`; then, when
   `provider.catalog`, request `catalog` and store the filtered items; start an event-consuming `Task`
   that maps `catalog_changed` → re-request `catalog` (30 s deadline) and call `onCatalogChanged(id)`,
   `refresh` → `onRefreshRequested(id)`. Any thrown `ProviderFailure` → `status = .failed(<message>)`,
   catalog cleared, `onStatusChanged`. One-shot packages never hold a process: `catalog` and `query`
   go through `ProviderProcess.runOnce` with `settings` added to the params; their status is `.idle`
   between calls. `query` on a lazily started persistent provider calls `start` first; results are
   discarded (return `[]`) when the generation captured before the call differs afterwards. Items
   from `query` are `transient: true`. Filter items via `action.requiredService`/`secondary` against
   `manifest.uses`. A failed provider throws `.notRunning` from `query`/`activate`/`links*` without
   restarting. `reload` increments the generation.

3. `AppDelegate.swift`:
   - Add `private let runtime = PluginRuntime(log: { Log.write($0) })`; `runtime.onCatalogChanged =
     { [weak self] _ in self?.rebuildItems() }`; `runtime.onRefreshRequested` stores nothing yet
     (task 23 wires it to the coordinator) — leave a call to `rebuildItems()`; `onStatusChanged` logs
     `"plugin <id>: <status>"`.
   - After `registry.rescan()` and in `registry.onChange`: `Task { await runtime.sync(enabled:
     registry.enabledPackages()); rebuildItems() }`.
   - `rebuildItems`: append `runtime.catalogItems()` after the declarative items.
   - `wirePanel`: `executor.services.callback = { [weak self] id, params in guard let self else {
     throw HostServiceError.noProvider(id) }; return try await runtime.activate(id, params: params) }`.
   - Reload Plugins: `registry.rescan()` then `Task { for package in registry.enabledPackages() {
     await runtime.reload(package) }; rebuildItems() }`.
   - `applicationWillTerminate(_:)`: `Task { await runtime.stopAll() }` is not awaited by AppKit;
     instead call a synchronous `runtime.terminateAll()` (SIGKILL every process) added for this purpose.
   - `PluginStatus` for the status menu is out of scope; only logs.

4. Fixture providers (`Tests/OddFrogCoreTests/Fixtures/providers/`, all python3, reading stdin line
   by line with `sys.stdin.buffer`, writing with `sys.stdout.write(json.dumps(obj) + "\n"); flush`):
   - `echo.py`: persistent. On start writes its pid to `pid.txt` in the current directory.
     `initialize` → `{"api": 1, "name": "Echo", "version": "1"}`; `catalog` →
     one item `{"id": "one", "title": "One", "action": {"type": "copy", "text": "one"}}`; `query` →
     one item id `q`, title = `"echo " + input`, `recordable: false`, but if `input == "wait"` it
     sleeps 0.5 s before answering; `activate` → `{"action": {"type": "copy", "text": "cb"},
     "message": null}`; `configure`/`cancel` → `{}` and append the method name to a file
     `$ECHO_LOG` when that env var is set; `shutdown` → `{}` then exit 0; unknown method → error
     `unsupported`; `links.list` → error `unsupported`.
   - `oneshot.py`: reads one line, answers `catalog` with one item `os` or `query` with one item
     whose title is `"os " + input + " " + str(params["settings"].get("flag", "none"))`, exits.
   - `malformed.py`: answers `initialize` correctly, then on `query` writes `not json\n`.
   - `crash.py`: answers `initialize`, then on `query` calls `sys.exit(3)` without responding.
   - `slow.py`: answers `initialize`, then on `query` sleeps 5 s before responding.
   - `oversized.py`: answers `initialize`, then on `query` writes `"x" * (5 * 1024 * 1024)` + `\n`.
   - `event.py`: answers `initialize`, then immediately writes `{"event": "catalog_changed"}`;
     `catalog` returns one item `a` the first time and two items `a`, `b` afterwards; on a `query`
     with input `refresh` it writes `{"event": "refresh"}` then answers with no items.
   - `wrongapi.py`: `initialize` → `{"api": 2, "name": "Old", "version": "1"}`.

5. Tests:
   - `ProviderProcessTests`: helper `fixture(_ name: String) -> URL` copying
     `Bundle.module.url(forResource: name, withExtension: "py", subdirectory:
     "Fixtures/providers")` into a temp directory and setting mode 0o755. Cases (each starts a
     process, sends `initialize`, asserts, then `terminate()`): echo initialize result; query round
     trip with matching id; two overlapping queries (`wait` and `x`) both resolve; `notify(cancel)`
     appends `cancel` to the `ECHO_LOG` file (pass the env through `ProcessInfo` in the test by
     setting it with `setenv` before spawning, and unset after); malformed → `send` throws
     `.malformed`, `isRunning` false; oversized → `.oversized`; crash → `.exited(3)`; slow with
     deadline 0.5 → `.timeout("query")` and the process is gone (`kill(pid, 0)` fails — expose
     `processIdentifier` on the actor); `runOnce` on oneshot returns the settings-flavoured title;
     `runOnce` with deadline 0.2 on slow-style behaviour is unnecessary (covered above); events from
     `event.py` arrive on `events` as `Event(event: "catalog_changed")`; `shutdown()` returns and the
     process exits 0.
   - `PluginRuntimeTests` (`@MainActor`): helper building a temp package directory with `plugin.toml`
     (`[provider] mode = "persistent", executable = "provider.py", catalog = true`, plus `[query] role
     = "live", activation = "all"` where needed, `[services] uses = ["clipboard"]`) and the copied
     fixture. Cases: `sync` starts echo and `catalogItems()` has `"<id>:one"`; `query` returns a
     transient `"<id>:q"` item titled `echo hi`; a query result after `reload` during the wait
     (`input = "wait"`) is discarded (`[]`); malformed/crash/slow/oversized → `status(for:) ==
     .failed(…)`, and a second `query` throws `.notRunning` immediately while `status` stays
     `.failed`;
     `reload` restores `.running` and the catalog; `stop` kills the process (read `pid.txt` from the
     package directory; `kill(pid, 0) != 0` afterwards); `wrongapi` →
     `.failed("plugin needs API 2")`; `event.py` → after `sync`, `onCatalogChanged` fires and
     `catalog(for:)` grows to two items; a query with `refresh` fires `onRefreshRequested`; a oneshot
     package (`mode = "oneshot"`, `executable = "oneshot.py"`) answers `query` with `settingsProvider`
     returning `["flag": "on"]` → title `os hi on`; items whose action needs an undeclared service are
     dropped (package declaring `uses = []` gets an empty catalog and one log line).

## Constraints
- No code comments of any kind, in any file (python fixtures included).
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency: `ProviderProcess` is an actor; `PluginRuntime` is `@MainActor`; no
  `@unchecked Sendable` on new types except a lock-guarded line buffer if needed.
- `OddFrogCore` never imports AppKit.
- Swift Testing only; tests use temporary directories, `Bundle.module` fixtures, and local processes
  only; total added test wall time under 20 s (use 0.5 s deadlines in tests where the spec says so).
- No new third-party dependencies.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes.
- `swift test --filter ProviderProcessTests` and `swift test --filter PluginRuntimeTests` pass, and
  `ps -ax | grep -c '[p]roviders/'` prints `0` afterwards (no leaked fixture processes).
- Manual after `make run`: place a user package at `~/.config/odd-frog/plugins/echo/` containing
  `plugin.toml` (`[provider] mode = "persistent"`, `executable = "echo.py"`, `catalog = true`,
  `[services] uses = ["clipboard"]`) and an executable copy of `echo.py`; since user packages start
  disabled nothing runs; there is no UI to enable it yet (task 24 persists enable state, task 30 adds
  the pane), so verify through the tests only.

## Out of scope
- Query routing, roles, and debounce (task 23); persisted settings and enable state (task 24); any
  bundled provider (tasks 25–28); showing provider status in Settings (task 30).

## Open questions
none
