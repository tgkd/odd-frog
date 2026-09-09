# Task: Run bundled providers in-process behind the same coordinator interface

First of two tasks (34–35). Task 35 removes the now-unused provider executables, manifests'
`executable` keys, Makefile targets and documentation; it requires this task. After this task the
tree still ships and builds every executable, but the host never spawns them.

## Goal
`PluginCoordinator` talks to providers through one transport abstraction with two implementations:
the existing `PluginProcess` (NDJSON over stdin/stdout, unchanged) for user-installed packages, and
a new in-process `LocalProvider` that calls a Swift handler directly. All nine bundled packages
(Applications, Commands, Scripts, Calculator, Web, Terminal, Calendar, Reminders; Windows is
declarative and untouched) run through `LocalProvider` when the host runs. A user package that
overrides a bundled ID still runs out-of-process through `PluginProcess`. Behaviour visible in the
launcher is unchanged; `ps` shows no `OddFrog*` provider processes while the app is running.

## Files
- Sources/OddFrogPluginAPI/ProviderServer.swift              (modify — `ProviderOperation` loses its `server` field; add `ProviderHandler` protocol)
- Sources/OddFrogPluginAPI/ProviderHandler.swift              (create — `ProviderHandler` protocol; may live in ProviderServer.swift instead, either is fine)
- Sources/OddFrogCore/ProviderTransport.swift                 (create — `ProviderTransport` protocol, `LocalProvider` actor)
- Sources/OddFrogCore/PluginProcess.swift                     (modify — conform to `ProviderTransport`)
- Sources/OddFrogCore/PluginCoordinator.swift                 (modify — `builtins` map, transport selection, executable check)
- Sources/OddFrogCore/PluginPackage.swift                     (modify — `executable` optional for non-declarative manifests)
- Plugins/Shared/Sources/BundledFeatures/FeatureProvider.swift (modify — conform to `ProviderHandler`, emit via closure)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarHandler.swift   (create — `CalendarHandler` actor)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersHandler.swift (create — `RemindersHandler` actor)
- Plugins/Calendar/Sources/OddFrogCalendar/main.swift          (modify — use `CalendarHandler`)
- Plugins/Reminders/Sources/OddFrogReminders/main.swift        (modify — use `RemindersHandler`)
- Plugins/Applications/Sources/main.swift, Plugins/Commands/Sources/main.swift, Plugins/Scripts/Sources/main.swift, Plugins/Calculator/Sources/main.swift, Plugins/Web/Sources/main.swift, Plugins/Terminal/Sources/main.swift (modify — use the `ProviderHandler` init)
- Sources/OddFrogBuiltins/BuiltinProviders.swift              (create — the id → handler factory table)
- Package.swift                                               (modify — new `OddFrogBuiltins` target; app and core tests depend on it)
- Sources/OddFrog/AppDelegate.swift                           (modify — pass `BuiltinProviders.factories` to the coordinator)
- Tests/OddFrogCoreTests/BundledPackageTests.swift            (modify — bundled packages run in-process; no executable copying)
- Tests/OddFrogCoreTests/LocalProviderTests.swift             (create)
- Tests/OddFrogCoreTests/PluginTests.swift                    (read — `manifest(extra:)`, `fixture(_:source:)`, `waitUntil` helpers and the echo fixture to mirror)
- Sources/OddFrogCore/HostServiceRegistry.swift               (read — `invoke(_:params:context:declared:)` signature used by the coordinator)

## Context
- Swift Package, `swift-tools-version: 6.0`, Apple Swift 6.4, macOS 14 deployment target. Build with
  `swift build`, test with `swift test`, release bundle with `make bundle` (copies
  `.build/release/OddFrog` and every package under `Plugins/` into `build/OddFrog.app`).
- Target graph today (Package.swift): `OddFrogPluginAPI` (no deps) → `OddFrogCore` (+TOMLKit) →
  `OddFrog` app (+`OddFrogHostServicesAPI`). `BundledFeatures` (path
  `Plugins/Shared/Sources/BundledFeatures`) already depends on `OddFrogCore` and
  `OddFrogPluginAPI`, so the app may depend on it without a cycle. `CalendarPluginCore` and
  `RemindersPluginCore` depend only on `OddFrogPluginAPI` + `OddFrogHostServicesAPI`.
  `OddFrogCoreTests` already depends on `BundledFeatures`.
- Provider wire model (`Sources/OddFrogPluginAPI/PluginProtocol.swift`): `JSONValue`, `RPCError`,
  `PluginEnvelope`, `PluginContext {settings, storagePath, configPath}`, `PluginQuery`,
  `PluginActivation`, `PluginEffects`. Methods a provider answers: `initialize`, `settings`,
  `catalog`, `query`, `activate`. Events a provider emits: `catalogChanged`, `queryInvalidated`.
  Every request's params are `{"apiVersion": 2, "context": PluginContext, "input": ...}` — built
  in `PluginCoordinator.perform(_:package:params:timeout:activated:)`.
- `PluginProcess` (`Sources/OddFrogCore/PluginProcess.swift`) is an actor with
  `init(executable:persistent:event:)`, `request(_ method:params:timeout:service:) async throws -> JSONValue`
  and `stop()`. `Service = @Sendable (String, JSONValue) async throws -> JSONValue` answers
  `host.service` calls from the provider; `Event = @Sendable (String, JSONValue) async -> Void`
  receives `catalogChanged` / `queryInvalidated` / `failure`. The coordinator stores instances in
  `processes: [String: PluginProcess]` and creates them lazily in `process(_ package:)`
  (PluginCoordinator.swift:99–107).
- `PluginCoordinator.reload` (line 52) fails a non-declarative package whose
  `package.executable` is not an executable file: `"Missing or non-executable provider: …"`.
- `PluginManifest.parse` (PluginPackage.swift:80–83) throws `"Invalid executable path."` when a
  non-declarative manifest has no `executable`. `PluginPackage.executable` is
  `directory.appendingPathComponent(manifest.executable ?? "")`.
- `PluginPackage.bundled` is true for packages discovered under the app's
  `Contents/Resources/Plugins`; `PluginDiscovery.scan(bundled:user:)` merges by id with the user
  package winning (`bundled == false`). That merge is the existing "user package replaces a bundled
  one" mechanism and must keep working.
- Provider-side SDK (`Sources/OddFrogPluginAPI/ProviderServer.swift`): `ProviderServer` actor,
  `init(oneShot: Bool = false, handler: @escaping Handler)` where
  `Handler = @Sendable (String, JSONValue, ProviderOperation) async throws -> JSONValue`;
  `run()`, `emit(_ method:)`. `ProviderOperation { id: String; server: ProviderServer; service(_:params:) }`.
  The only code that touches `operation.server` is `FeatureProvider.handle` →
  `setup(context, server: operation.server)`, which calls `server.emit("catalogChanged")` /
  `server.emit("queryInvalidated")` from watcher callbacks and periodic tasks.
- Bundled executables are eight-line wrappers, e.g. `Plugins/Applications/Sources/main.swift`:
  `let provider = FeatureProvider(.applications); let server = ProviderServer(oneShot: false) { m, p, op in try await provider.handle(m, params: p, operation: op) }; try await server.run()`.
  Calendar and Reminders (`Plugins/*/Sources/OddFrog*/main.swift`, 23 lines each) inline a
  handler that answers `initialize`/`settings`, and for `query` decodes `PluginQuery`, calls
  `operation.service("calendar.read@1", params: .encode(CalendarProvider.range(for: query)))`
  (Reminders: `"reminders.read@1"` with `.encode(RemindersScope(limit: 2000))`), decodes the
  snapshot and returns `.encode(CalendarProvider.respond(to:snapshot:))`
  (`RemindersProvider.respond(to:snapshot:)`), plus a detached task that emits
  `queryInvalidated` every 30 seconds.
- `FeatureProvider` (`Plugins/Shared/Sources/BundledFeatures/FeatureProvider.swift`) is
  `public actor FeatureProvider { init(_ feature: Feature); handle(_:params:operation:) }` with
  `Feature` cases `applications, commands, scripts, calculator, web, terminal`.
- The app creates the coordinator in `AppDelegate.makePluginCoordinator()`
  (`Sources/OddFrog/AppDelegate.swift:13–16`): `PluginCoordinator(services: registry)`.
- `Tests/OddFrogCoreTests/BundledPackageTests.swift` has `installBundled(to:)`, which copies each
  `Plugins/<id>/plugin.toml` plus the built executable from `.build/debug` (or
  `$ODD_FROG_TEST_PRODUCTS`) into a temp folder and returns `PluginPackage(…, bundled: true)`.
  `shippedFeaturesRunThroughAPI2AndEachCanBeDisabled` drives every package through a fresh
  coordinator with one query each (`queries` dictionary) and then disables it.
  `independentPythonSettingsCallbackAndCalculatorReplacementLeaveHostUnchanged` runs
  `examples/plugins/counter` (Python, persistent) and then replaces `calculator` with the
  `examples/plugins/one-shot` Python package; both must keep running through `PluginProcess`.
- `Tests/OddFrogCoreTests/PluginTests.swift` builds packages from inline manifests with
  `bundled: true` and Python fixture executables and drives them through `PluginCoordinator`. Those
  packages must keep using `PluginProcess`: the coordinator only goes in-process when a factory for
  the id is registered, and those tests register none.
- Tests use swift-testing (`import Testing`, `@Test`, `#expect`, `#require`); coordinator tests
  are `@MainActor` and poll with a `waitUntil { … }` helper (deadline 8 s).
- Code style in this repository: no comments in new code; braces on every `if`/`guard` body;
  one type per file for new files; `@MainActor` on AppKit-facing classes; actors for anything
  that owns background work.

## Plan
1. `Sources/OddFrogPluginAPI/ProviderServer.swift`: make `ProviderOperation` transport-neutral.
   Replace the `server: ProviderServer` stored property with two stored closures,
   `@Sendable (String, JSONValue) async throws -> JSONValue` for services and
   `@Sendable (String) async throws -> Void` for events, and give it a public
   `emit(_ method: String) async throws`. Keep `service(_ capability:params:)`. Keep the memberwise
   initialiser public so any transport can build one. `ProviderServer.run()` constructs operations
   with closures that call its existing private `service(_:params:owner:)` and `emit(_:)`.
2. Add `ProviderHandler` to `OddFrogPluginAPI` (own file or next to `ProviderServer`):
   ```swift
   public protocol ProviderHandler: Sendable {
       func start(emit: @escaping @Sendable (String) async -> Void) async
       func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue
       func shutdown() async
   }
   ```
   with default no-op `start` and `shutdown` in an extension. Add
   `ProviderServer.init(oneShot: Bool = false, provider: any ProviderHandler)` which calls
   `provider.start(emit:)` at the top of `run()` (the emit closure forwards to `emit(_:)`,
   swallowing send errors), forwards requests to `provider.handle`, and calls
   `provider.shutdown()` after the message loop ends. The closure-based init stays.
3. `Plugins/Shared/Sources/BundledFeatures/FeatureProvider.swift`: conform `FeatureProvider` to
   `ProviderHandler`. `setup` takes the emit closure instead of a `ProviderServer`; the watcher
   callbacks and periodic tasks call that closure. Store the closure passed to `start(emit:)` and
   use it in `setup`; `handle("initialize"/"settings")` keeps calling `setup` so settings changes
   still re-arm watchers. `shutdown` cancels the `refresh` task and stops the watcher.
4. `Plugins/Calendar/Sources/CalendarPluginCore/CalendarHandler.swift`: `public actor CalendarHandler: ProviderHandler`
   holding the logic that is inline in `OddFrogCalendar/main.swift` today (`initialize`, `settings`,
   `query` via `operation.service("calendar.read@1", …)` and `CalendarProvider`), and the 30-second
   `queryInvalidated` task started in `start(emit:)` and cancelled in `shutdown()`. Same for
   `RemindersHandler` in `RemindersPluginCore` with `"reminders.read@1"` and
   `RemindersScope(limit: 2000)`. Rewrite both `main.swift` files to
   `try await ProviderServer(provider: CalendarHandler()).run()` (exit 1 on error, as today).
5. Rewrite the six `FeatureProvider` `main.swift` files to
   `ProviderServer(oneShot: <as today>, provider: FeatureProvider(.<feature>))`.
   The tree builds and every executable behaves as before; `swift test` passes here.
6. `Sources/OddFrogCore/ProviderTransport.swift`:
   ```swift
   public protocol ProviderTransport: Actor {
       func request(_ method: String, params: JSONValue, timeout: Duration?, service: @escaping PluginProcess.Service) async throws -> JSONValue
       func stop()
   }
   ```
   Conform `PluginProcess` (its `request` already has this shape; add `timeout` as a labelled
   parameter without default if needed so the signatures match). Add
   `public actor LocalProvider: ProviderTransport` with `init(handler: any ProviderHandler, event: @escaping PluginProcess.Event)`.
   On the first `request` it calls `handler.start(emit:)` once, where the emit closure forwards
   `catalogChanged`/`queryInvalidated` to `event(method, .object([:]))`. `request` builds a
   `ProviderOperation(id: UUID().uuidString, service: <the closure passed in>, emit: <same forwarder>)`
   and returns `try await handler.handle(method, params: params, operation: operation)`; `timeout`
   is ignored (a hang in bundled code is a host bug, not a misbehaving plugin; Swift task
   cancellation still propagates). `stop()` calls `handler.shutdown()` in a detached task and marks
   the provider stopped so a later `request` throws `RPCError("protocol", "Provider stopped.")`.
7. `Sources/OddFrogCore/PluginCoordinator.swift`:
   - Add `public typealias BuiltinProviderFactory = @Sendable () -> any ProviderHandler` and a
     `public var builtins: [String: BuiltinProviderFactory] = [:]` (set once by the app before the
     first `reload`).
   - Change `processes` to `[String: any ProviderTransport]`; `process(_:)` returns a
     `LocalProvider` when `package.bundled && builtins[id] != nil`, otherwise a `PluginProcess`
     exactly as today. Everywhere `PluginProcess` was referenced by type, use the protocol.
   - In `reload`, replace the executable check (line 52) with: declarative → no check;
     bundled with a factory → no check; otherwise require `manifest.executable != nil` and
     `isExecutableFile` — failure text stays `"Missing or non-executable provider: …"`. A bundled
     package without a factory and without an executable fails with
     `"No built-in provider for <id>."`.
   - `perform` passes `timeout` through unchanged; `stop()`/`fail(_:)` call `stop()` on the
     protocol.
8. `Sources/OddFrogCore/PluginPackage.swift`: in `PluginManifest.parse`, for non-declarative
   manifests validate `executable` only when present (same relative-path/no-`..` rules); absence
   is allowed. Keep `PluginPackage.executable` as is.
9. New target `OddFrogBuiltins` at `Sources/OddFrogBuiltins/` depending on `BundledFeatures`,
   `CalendarPluginCore`, `RemindersPluginCore`, `OddFrogPluginAPI`, `OddFrogCore`. One file
   `BuiltinProviders.swift`:
   `public enum BuiltinProviders { public static let factories: [String: PluginCoordinator.BuiltinProviderFactory] }`
   mapping `applications`, `commands`, `scripts`, `calculator`, `web`, `terminal` to
   `FeatureProvider(.<feature>)`, `calendar` to `CalendarHandler()`, `reminders` to
   `RemindersHandler()`. Package.swift: add the target; add it to the `OddFrog` executable's
   dependencies and to `OddFrogCoreTests`' dependencies.
10. `Sources/OddFrog/AppDelegate.swift` `makePluginCoordinator()`: after creating the coordinator,
    `coordinator.builtins = BuiltinProviders.factories` (add `import OddFrogBuiltins`).
11. `Tests/OddFrogCoreTests/BundledPackageTests.swift`: `installBundled(to:)` copies only
    `plugin.toml` (drop the executable copy and the `products` lookup for it); every coordinator
    in the file gets `coordinator.builtins = BuiltinProviders.factories` before `reload`
    (add `import OddFrogBuiltins`). In the replacement test the Python `calculator` package is
    `bundled == false`, so it keeps running through `PluginProcess`; assert additionally that
    `coordinator.failures.isEmpty` after the replacement query resolves. The host-hash assertion
    stays. Rename `shippedFeaturesRunThroughAPI2AndEachCanBeDisabled` to
    `shippedFeaturesRunInProcessAndEachCanBeDisabled`.
12. `Tests/OddFrogCoreTests/LocalProviderTests.swift`: a test-local `ProviderHandler` actor that
    records calls. Cover: `request` delivers `method`/`params` and returns the handler's result;
    `operation.service` reaches the `service` closure passed to `request`; `operation.emit("catalogChanged")`
    and `start(emit:)` reach the `event` callback with that method name; `start` runs exactly once
    across several requests; after `stop()` a request throws and `shutdown` was called; a handler
    error surfaces as the thrown error of `request`.
13. Run `swift test`, then `make bundle`, launch `build/OddFrog.app` and confirm with `ps` that no
    `Contents/Resources/Plugins/*/OddFrog*` process exists while `2+2`, `saf`, `> uptime`, `cal`
    and `rem` all return rows in the launcher.

Approach decision: the transport protocol lives in `OddFrogCore` and the handler protocol in
`OddFrogPluginAPI`, so `CalendarPluginCore`/`RemindersPluginCore` (which must not depend on
`OddFrogCore`) can conform to `ProviderHandler`, while `OddFrogCore` never depends on any bundled
feature library. The alternative — the coordinator linking `BundledFeatures` directly — was rejected
because it creates an `OddFrogCore` ↔ `BundledFeatures` cycle. The factory map is a plain value set
by the app rather than a manifest key, so the manifests stay valid API 2 packages and a user
package with the same id (never `bundled`) automatically takes the process path.

## Constraints
- No comments in new or edited code (no `//`, no `///`, no `MARK`). Existing comments in lines you
  do not otherwise touch stay as they are.
- Every `if`/`guard`/`else` body is braced on its own line; no single-line `if x { return }` in new
  code except the `guard … else { return }` idiom already used throughout the repository.
- New files hold one type each and use four-space indentation; match the multi-line declaration
  style of `Sources/OddFrog/SettingsLayout.swift`, not the semicolon-joined one-liners in
  `PluginCoordinator.swift`.
- Do not change the NDJSON wire format, `PluginEnvelope`, the `apiVersion`, method names, or
  event names; `docs/api2/exchanges.ndjson` must keep round-tripping (there is a test for it).
- `PluginProcess` semantics (deadlines, process groups, cancellation, `failure` events) are
  unchanged; only its conformance is added.
- `OddFrogCore` gains no dependency on `BundledFeatures`, `CalendarPluginCore`, or
  `RemindersPluginCore`.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` passes (from the repo root).
- `swift test` passes; the run includes `LocalProviderTests` and both `BundledPackageTests`, and no
  `OddFrog*` provider process is spawned by `BundledPackageTests` (run
  `swift test --filter BundledPackageTests` while watching `ps aux | grep Resources/Plugins` — the
  only provider processes are `python3` ones from `examples/plugins`).
- `make bundle` passes; `open build/OddFrog.app`, type `2+2` (row `4`), `saf` (Safari), `> uptime`,
  `cal`, `rem` in the launcher — each returns rows; `ps aux | grep 'OddFrog.app/Contents/Resources/Plugins'`
  shows no processes.
- Installing `examples/plugins/counter` into `~/.config/odd-frog/v2/plugins/counter`, enabling it
  in Settings → Plugins and typing its label still works and shows a `python3` provider process.

## Out of scope
- Removing the eight executable targets, `executable =` keys in bundled manifests, `make plugin`,
  `OddFrogPackage --product`, and documentation wording — that is task 35.
- Routing user providers' stderr into `odd-frog.log` (`ProviderChild` opens `/dev/null`).
- Any change to ranking, settings UI, migration, or host services.

## Open questions
none
