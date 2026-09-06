# Task: Stop rescanning on every panel show — watch app folders, cache app names, reload only what changed

Task 11 of the "user flow" series. Run last (it touches `AppDelegate` and
`LauncherViewController`, which 05, 06, 09 and 10 also edit). Assumes `refresh(keepSelection:)`
from task 05; if absent, use `refresh()`.

## Goal
Opening the panel does no filesystem work. Apps are rescanned only at launch, on "Rescan Apps",
or when a watched application folder changes, and a rescan reuses cached names for bundles whose
`Info.plist` has not changed. Unchanged scan results never reload the table. Each loaded icon
refreshes only its own row. Launch-time icon prewarming runs at utility priority, one task.

## Files
- Sources/OddFrogCore/AppIndexer.swift              (modify — cache, watched directories, drop `refreshIfStale`)
- Sources/OddFrog/AppDelegate.swift                 (modify — watcher, guards, show path)
- Sources/OddFrog/IconCache.swift                   (modify — prewarm, observer payload)
- Sources/OddFrog/LauncherViewController.swift      (modify — per-row icon reload, equality guards)
- Sources/OddFrog/SettingsWindowController.swift    (modify — per-row icon reload)
- Sources/OddFrogCore/DirectoryWatcher.swift        (read — `watch(_:onChange:)` replaces the watched set; one debounce for all)
- Tests/OddFrogCoreTests/AppIndexerTests.swift      (create)
- Tests/OddFrogCoreTests/ScriptTests.swift          (read — `appScanSkipsBrokenSymlinksAndDedupesAliases` shows how to build a fake `.app` in a temp dir)

## Context
- Swift 6 strict concurrency. `AppIndexer` is an `actor`; `AppScanner` is a pure enum.
  `AppScanner.scan(roots:maxDepth:)` enumerates each root two levels deep, skips dotfiles,
  dedupes by resolved path, and builds an `AppItem` per bundle via `makeItem`, which loads
  `Bundle(url:)` and reads `localizedInfoDictionary` / `infoDictionary` for the display name.
  That Bundle load is the expensive part (hundreds of bundles). `AppItem` is
  `Sendable, Hashable`, id is `url.path`.
- `AppDelegate.refreshApps(force:)` (line ~215) calls `indexer.refreshIfStale(olderThan: 60)`
  unless forced, then `icons.prewarm(apps)` and `rebuildItems()`. It is called at launch,
  from `showPanel` (line ~293, every show), and from the menu's Rescan (forced).
  `refreshScripts()` is likewise called on every show with its own 60 s staleness check;
  `settings.scripts.watch` (default true) already drives `scriptWatcher`, a `DirectoryWatcher`
  that forces a script rescan on change (`rewatchScripts`). `refreshWeights()` is called on
  every show and after every recorded launch (`executor.onRecorded`).
- `rebuildItems()` assigns `controller.items = settings.apply(to: allItems)` unconditionally,
  which triggers `LauncherViewController.items.didSet` → `subtitles` recompute → `refresh()`
  → `tableView.reloadData()`. `controller.weights.didSet` does the same. `FrecencyTable.decay`
  depends on the current time, so two `decayedWeights()` snapshots are never equal even when
  nothing was recorded; the relative order of two used items is time-independent, only the
  absolute bonus drifts (half-life 7 days).
- `IconCache.observeLoads` handlers receive the loaded app path. `LauncherViewController.init`
  (line 44) reloads every row on each load; `SettingsWindowController.init` reloads the whole
  `itemTable`. `IconCache.load(path:)` spawns one `Task.detached(priority: .userInitiated)`
  per path; `prewarm(_:)` calls `icon(forFile:size:)` for every app, so launch spawns one task
  per installed app. `NSWorkspace.shared.icon(forFile:)` is the loader.
- `DirectoryWatcher.watch(_ directories: [URL], onChange:)` watches exactly the given set
  (adds new, cancels missing), debounces 0.3 s, and invokes `onChange` on its own queue; the
  existing `rewatchScripts` shows how to hop to the main actor
  (`DispatchQueue.main.async { MainActor.assumeIsolated { … } }`). A directory dispatch source
  fires for entries added or removed directly inside that directory, not deeper.
- `AppScanner.defaultRoots`: `/Applications`, `~/Applications`, `/System/Applications`,
  `/System/Library/CoreServices/Applications`. `maxDepth` 2 means `/Applications/Utilities/X.app`
  is indexed, so watching needs the roots plus their immediate non-bundle subdirectories.
- Test conventions: Swift Testing, temp dirs under `FileManager.default.temporaryDirectory`
  with a UUID suffix and `defer { removeItem }`, fake bundles are `Name.app/Contents`
  directories (no `Info.plist`; `makeItem` then falls back to the file name).
- `swift test` runs 56 tests and passes today.

## Plan
1. `AppIndexer.swift`
   - Add `public struct AppScanCache: Sendable, Equatable { public var entries: [String: Entry] }`
     with `public struct Entry: Sendable, Equatable { public var modified: Date; public var item: AppItem }`,
     keyed by the standardized bundle path, plus `public init(entries: [:] = [:])`.
   - Add `public static func scan(roots:maxDepth:cache: AppScanCache) -> (apps: [AppItem], cache: AppScanCache)`.
     For each bundle, read `.contentModificationDateKey` of `Contents/Info.plist`, falling back
     to the bundle directory's date; if the cache has an entry for the path with the same date,
     reuse its `item`, otherwise call `makeItem`. The returned cache contains only bundles seen
     in this scan. Keep the existing `scan(roots:maxDepth:)` as a wrapper that passes an empty
     cache and returns `.apps`.
   - Add `public static func watchedDirectories(roots: [URL]) -> [URL]`: every existing root
     plus each immediate child of a root that is a directory, is not a `.app` bundle
     (`pathExtension != "app"`) and does not start with `.`.
   - `AppIndexer`: keep a `cache` between refreshes; `refresh()` passes and stores it. Delete
     `refreshIfStale(olderThan:)` and `lastScan` (no remaining callers after step 2).
2. `AppDelegate.swift`
   - Add `private let appWatcher = DirectoryWatcher()`. After the first `refreshApps` completes
     in `applicationDidFinishLaunching`, and again after every forced rescan, call
     `appWatcher.watch(AppScanner.watchedDirectories(roots: AppScanner.defaultRoots))` with an
     `onChange` that hops to the main actor and runs `refreshApps(force: true)`.
   - `refreshApps(force:)` becomes `refreshApps()` that always calls `indexer.refresh()`;
     assign `apps`, prewarm and `rebuildItems()` only when the result differs from the current
     `apps`.
   - `showPanel`: remove the `refreshApps()` call. Keep `refreshScripts()` only when
     `settings.scripts.watch` is false. Replace the unconditional `refreshWeights()` with a call
     guarded by a `lastWeightsRefresh: Date?` older than 10 minutes; `executor.onRecorded`
     and launch still refresh unconditionally and update the timestamp.
   - `rebuildItems()`: compute the new list first and assign `controller.items` only when it
     differs.
3. `LauncherViewController.swift`
   - `items.didSet`: `guard items != oldValue else { return }` before recomputing subtitles and
     refreshing. `weights.didSet`: same guard.
   - Icon observer: find the rows whose `results[row].item` is `.app` with `app.url.path`
     equal to the loaded path and reload only those (`reloadData(forRowIndexes:columnIndexes:)`);
     do nothing when none match.
4. `SettingsWindowController.swift` — icon observer: reload only the rows of `visibleItems`
   whose app path matches, for the name column only (`itemTable.column(withIdentifier:
   Column.name)`), still guarded by `window.isVisible`.
5. `IconCache.swift`
   - `prewarm(_:)`: collect app paths that are neither cached nor pending, mark them all
     pending, and start one `Task.detached(priority: .utility)` that loads them sequentially,
     hopping to the main actor per icon to call `store`. `load(path:)` (on-demand, user is
     looking at the row) keeps `.userInitiated`.
6. Tests — `AppIndexerTests.swift`:
   - `cacheReusesUnchangedBundles`: build `Real.app/Contents` in a temp dir; scan with an empty
     cache; poison the returned cache by replacing the entry's `item` with one named
     `"Cached"` (same date); scan again with the poisoned cache → the name is `"Cached"`.
     Touch `Real.app/Contents/Info.plist` (create the file) → scan again → the name is `"Real"`
     and the cache entry's date changed.
   - `cacheDropsRemovedBundles`: after deleting the bundle the returned cache has no entry.
   - `watchedDirectoriesIncludesSubfoldersButNotBundles`: temp root with `Utilities/`,
     `Some.app/`, `.hidden/` → result is `[root, root/Utilities]`.

## Constraints
- No code comments of any kind.
- Swift 6 strict concurrency: `AppScanCache` crosses actor boundaries and must be `Sendable`;
  `DirectoryWatcher` callbacks are `@Sendable` and must hop to the main actor as
  `rewatchScripts` does.
- Swift Testing only. No new dependencies.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes with the three new tests.
- `swift build -c release` succeeds.
- Manual after `make run`:
  1. Open the panel repeatedly over two minutes while tailing `~/Library/Logs/odd-frog.log`:
     no "scripts scanned" or app-scan lines appear on show.
  2. Copy any `.app` into `~/Applications`: within a second the log shows a scan and the app
     is findable in the launcher. Delete it: it disappears after the next scan.
  3. Menu bar → Rescan Apps still logs a scan.
  4. Arrow to row 3 with the panel open, then trigger step 2's copy in the background: the
     selection does not move and the rows do not flicker.
  5. Launch the app and open the panel immediately: rows with icons still loading fill in
     one by one without the whole list repainting.

## Out of scope
- Persisting the scan cache to disk between launches. Indexing Finder or other
  `/System/Library/CoreServices` items. Changing `ScriptScanner`.

## Open questions
none
