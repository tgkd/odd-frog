# Task: Plugin system rework 3/13 — package discovery and the plugin registry

Third of thirteen tasks (19–31). Requires tasks 19 and 20: `OddFrogPluginAPI` (`ManifestParser`,
`PluginManifest`, `HostService`, `PluginItem`) and the generic `LauncherItem` with `LegacyAdapters`.

## Goal
The host discovers plugin packages in the app bundle's `Contents/PlugIns` and in
`~/.config/odd-frog/plugins`, applies the override and duplicate rules, keeps invalid packages
visible with their error, exposes enable state and declared services, publishes declarative
`[[items]]` of enabled packages into the launcher, watches both directories, and offers "Reload
Plugins" in the status menu. No bundled package exists yet, so the launcher behaves as before; the
registry is exercised by tests on temporary directories.

## Files
- Sources/OddFrogCore/PluginDiscovery.swift            (create — PluginSource, PluginStatus, PluginPackage, PluginDiscovery)
- Sources/OddFrogCore/PluginRegistry.swift             (create — PluginRegistry)
- Sources/OddFrog/AppDelegate.swift                    (modify — own a registry, merge declarative items, wire services + reload)
- Sources/OddFrog/StatusMenu.swift                     (modify — "Reload Plugins" item)
- Tests/OddFrogCoreTests/PluginDiscoveryTests.swift    (create)
- Tests/OddFrogCoreTests/PluginRegistryTests.swift     (create)
- Sources/OddFrogCore/DirectoryWatcher.swift           (read — `watch(_:onChange:)` / `stop()` to reuse)
- Sources/OddFrogCore/Config.swift                     (read — `ConfigLoader.defaultDirectory`, XDG handling)
- Sources/OddFrogPluginAPI/ManifestParser.swift        (read — `ManifestParser.load(from:)`, `ManifestError`)

## Context
- `ManifestParser.load(from url: URL) throws -> PluginManifest` (task 19) reads and validates a
  `plugin.toml`; errors are `ManifestError` whose `description` is the user-facing message.
  `PluginManifest` fields: `id, name, version, api, description, defaultEnabled, provider:
  ProviderSpec?, query: QuerySpec?, uses: Set<HostService>, provides: Set<ProvidedCapability>,
  settings: [SettingDefinition], items: [PluginItem]`.
- `LauncherItem(pluginID:item:transient:)` (task 20) wraps a `PluginItem`; global id
  `"<pluginID>:<item.id>"`. `HostServices.declaredServices: (String) -> Set<HostService>` is the
  closure the executor consults before dispatching; task 20 left it returning every service.
- `ConfigLoader.defaultDirectory` is `$XDG_CONFIG_HOME/odd-frog` or `~/.config/odd-frog`.
- `DirectoryWatcher` (`Sources/OddFrogCore/DirectoryWatcher.swift`): `watch(_ directories: [URL],
  onChange: @escaping @Sendable () -> Void)` replaces the watched set (missing directories are
  silently skipped), 0.3 s debounce, fires on its own queue; callers hop to the main actor with
  `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` as `AppDelegate.rewatchScripts` does.
- `StatusMenu.menuNeedsUpdate` rebuilds the menu each time: Show, failure line, Settings…, Reload
  Config, Open Config, Open Log, Rescan Apps, Launch at Login, Quit; each entry is `action(title,
  selector)` calling an `onX` closure.
- `AppDelegate` is `@MainActor`, builds `allItems` in `rebuildItems()` from `LegacyAdapters` and
  applies `settings.apply(to:)`; `wireStatusMenu()` sets the status closures; `executor` wraps
  `HostServices` (`executor.services`).
- `Bundle.main.builtInPlugInsURL` is `<app>/Contents/PlugIns` for a bundled app and a non-existent
  path when running from `swift run` or in tests; treat a missing directory as "no bundled packages".
- Decisions fixed for the whole rework:
  - A package is any immediate subdirectory of a location that contains `plugin.toml`; its id comes
    from the manifest, not the directory name. Nested directories are not searched.
  - User packages override bundled ones with the same id (the bundled one is dropped from the list).
  - Two packages with the same id inside one location are both rejected: `manifest = nil`, `error =
    "duplicate plugin id 'x' in bundled"` / `"… in user"`, and neither participates in overriding.
  - A package whose manifest fails to parse keeps `manifest = nil`, `error = <ManifestError
    description>`, `id = <directory name>`; other packages are unaffected.
  - Enable default: bundled → `manifest.defaultEnabled`; user → `false`. Persisted enable state
    arrives in task 24 as `[String: Bool]` overrides; until then only defaults apply.
  - Plugin ids without a package (the legacy adapter ids `applications`, `commands`, `scripts`,
    `windows`, `web`, `terminal`, `calculator`) keep every service until task 29 removes the adapters.

## Plan
1. `Sources/OddFrogCore/PluginDiscovery.swift` (import Foundation, OddFrogPluginAPI):
   ```swift
   public enum PluginSource: String, Sendable, Hashable { case bundled, user }
   public enum PluginStatus: Sendable, Equatable {
       case disabled, idle, running, failed(String), invalid(String)
   }
   public struct PluginPackage: Sendable, Hashable, Identifiable {
       public let id: String
       public let manifest: PluginManifest?
       public let directory: URL
       public let source: PluginSource
       public let error: String?
       public init(id: String, manifest: PluginManifest?, directory: URL, source: PluginSource, error: String? = nil)
   }
   public enum PluginDiscovery {
       public static var bundledDirectory: URL? { Bundle.main.builtInPlugInsURL }
       public static var userDirectory: URL { ConfigLoader.defaultDirectory.appendingPathComponent("plugins", isDirectory: true) }
       public static func packages(in location: URL, source: PluginSource) -> [PluginPackage]
       public static func scan(bundled: URL?, user: URL) -> [PluginPackage]
   }
   ```
   `packages(in:source:)`: list immediate subdirectories (skip hidden, non-directories, and
   directories without `plugin.toml`), parse each manifest, build packages, then mark same-id groups
   of size > 1 as rejected duplicates (message above, `manifest` nil). `scan`: user packages first,
   then bundled packages whose id is not claimed by a valid user package; result sorted by id, then
   source (`bundled` before `user`, only relevant for rejected ids). A missing location yields `[]`.

2. `Sources/OddFrogCore/PluginRegistry.swift`:
   ```swift
   @MainActor public final class PluginRegistry {
       public private(set) var packages: [PluginPackage] = []
       public var enabledOverrides: [String: Bool] = [:] { didSet { onChange?() } }
       public var onChange: (() -> Void)?
       public init(bundled: URL?, user: URL, watcher: DirectoryWatcher = DirectoryWatcher())
       public func rescan()
       public func startWatching()
       public func stopWatching()
       public func package(for id: String) -> PluginPackage?
       public func manifest(for id: String) -> PluginManifest?
       public func hasPackage(_ id: String) -> Bool
       public func defaultEnabled(for package: PluginPackage) -> Bool
       public func isEnabled(_ id: String) -> Bool
       public func status(for id: String) -> PluginStatus
       public func declaredServices(for id: String) -> Set<HostService>
       public func enabledPackages() -> [PluginPackage]
       public func declarativeItems() -> [LauncherItem]
   }
   ```
   `rescan()` = `PluginDiscovery.scan` then `onChange?()` when the package list changed.
   `isEnabled` = `enabledOverrides[id] ?? defaultEnabled(for:)` and false for ids without a valid
   manifest. `status(for:)`: no package → `.invalid("not installed")`; `error` set → `.invalid(error)`;
   disabled → `.disabled`; else `.idle` (task 22 reports `.running`/`.failed` from the runtime).
   `declaredServices(for:)` = `manifest.uses` or `[]`. `declarativeItems()` = for each enabled package
   with a manifest, its `items` as `LauncherItem(pluginID: id, item:)`, packages in `packages` order.
   `startWatching()` watches the bundled directory (when non-nil) and the user directory; the
   callback hops to the main actor and calls `rescan()`.

3. `AppDelegate.swift`:
   - Add `private let registry = PluginRegistry(bundled: PluginDiscovery.bundledDirectory, user:
     PluginDiscovery.userDirectory)`.
   - In `applicationDidFinishLaunching` after `loadInitialSettings()`: `registry.onChange = { [weak
     self] in self?.rebuildItems() }`, `registry.rescan()`, `registry.startWatching()`, and log
     `"plugins: <n> packages (<m> enabled)"` via `Log.write` listing each invalid package as
     `"plugin <id> invalid: <error>"`.
   - `rebuildItems`: append `registry.declarativeItems()` after the adapter items.
   - `wirePanel`: `executor.services.declaredServices = { [weak self] id in guard let self,
     registry.hasPackage(id) else { return Set(HostService.allCases) }; return
     registry.declaredServices(for: id) }`.
   - `wireStatusMenu`: `status.onReloadPlugins = { [weak self] in self?.registry.rescan() }`.
   - Log each rescan result the same way from the `onChange` handler.

4. `StatusMenu.swift`: add `var onReloadPlugins: (() -> Void)?`, a menu entry "Reload Plugins"
   immediately after "Reload Config", and the `@objc private func reloadPlugins()` forwarder.

5. Tests:
   - `PluginDiscoveryTests` (temporary directories under `FileManager.default.temporaryDirectory`,
     removed in `defer`): a helper writing `plugin.toml` from a minimal manifest string
     (`[plugin]\nid = "<id>"\nname = "<Name>"\nversion = "1.0.0"\napi = 1\n` plus optional extra
     text). Cases: `scan` on two missing directories → `[]`; one valid bundled + one valid user
     package → both listed, sorted by id; same id in bundled and user → only the user package, `source
     == .user`; same id twice in the user location → two packages with `manifest == nil` and `error ==
     "duplicate plugin id 'dup' in user"`, and a bundled package with that id still listed (no valid
     override); a directory with a malformed manifest (`api = 2`) → `manifest == nil`, `error` contains
     "needs API 2", `id` equals the directory name, and a sibling valid package is still returned;
     a subdirectory without `plugin.toml` and a hidden directory are ignored.
   - `PluginRegistryTests` (`@MainActor` tests): a registry over temp directories (pass a fresh
     `DirectoryWatcher`; do not call `startWatching`): `defaultEnabled` true for a bundled package,
     false for a bundled one with `default_enabled = false`, false for a user package;
     `enabledOverrides["x"] = true` flips a user package on and fires `onChange`; `status(for:)`
     covers `.invalid`, `.disabled`, `.idle`, and "not installed"; `declarativeItems()` for an enabled
     package whose manifest has `[services] uses = ["window"]` and one `[[items]]` window action yields
     one item with id `"<plugin>:<item id>"` and none when the package is disabled;
     `declaredServices(for:)` returns `[.window]` for it and `[]` for an unknown id; `rescan()` after
     adding a package on disk fires `onChange` and lists it.

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; `PluginRegistry` is `@MainActor`; `OddFrogCore` never imports AppKit.
- Swift Testing only; tests use temporary directories and never touch `~/.config` or the network.
- No new third-party dependencies.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes.
- `swift test --filter PluginDiscoveryTests` and `swift test --filter PluginRegistryTests` pass.
- Manual after `make run`: create `~/.config/odd-frog/plugins/demo/plugin.toml` containing a manifest
  with `[services] uses = ["open"]` and one `[[items]]` entry `id = "site"`, `title = "Demo Site"`,
  `action = { type = "open", url = "https://example.com" }`; the log shows `plugins: 1 packages (0
  enabled)` and typing `demo` shows nothing (user packages start disabled). Edit the manifest to break
  it (`api = 2`): within a second the log shows `plugin demo invalid: … needs API 2 …`. Status menu
  → Reload Plugins re-logs the package count.

## Out of scope
- Starting provider processes (task 22), persisting enable state and rendering settings (tasks 24 and
  30), bundled manifests (task 25 onward).

## Open questions
none
