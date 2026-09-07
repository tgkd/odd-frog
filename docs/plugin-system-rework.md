# Odd Frog plugin system rework

## Summary

Make every launcher feature a separately packaged plugin: applications, configured commands and links, script discovery, calculator, window commands, web fallbacks, and terminal input. Ship these plugins with the app and load them through the same mechanism as user-installed plugins.

The host retains the launcher UI, ranking, history, configuration storage, plugin lifecycle, and macOS services. Adding or replacing a feature plugin must not require rebuilding the host.

Version one supports local installation, trusted executable code, simple command scripts, and scripts returning live results. No marketplace, automatic downloads, custom plugin UI, or sandbox. Use a fresh configuration format without automatic migration; preserve old files on disk.

## Plugin contract and runtime

- Introduce a shared, versioned `OddFrogPluginAPI` library containing serializable manifests, items, actions, settings definitions, and protocol messages. Feature implementations must not be dependencies of the host.
- Each package contains `plugin.toml`, optional executable entry points, and assets. The manifest declares its stable ID, version, API version, commands, query activation, execution mode, settings, and required host services.
- Support three forms through one contract:
  - **Declarative commands:** searchable items and host actions declared in the manifest; no running provider required.
  - **One-shot scripts:** receive one JSON request on stdin, write one JSON response to stdout, and exit. Ordinary command scripts retain plain output and run only on selection.
  - **Persistent providers:** exchange newline-delimited JSON requests, responses, and events over stdin/stdout. Diagnostics go to stderr.
- Protocol operations cover initialization, catalog retrieval, querying, activation, configuration changes, cancellation, and shutdown. Events publish catalog changes and request refreshing the current query. Requests carry IDs; initialization checks API compatibility before accepting results.
- Results describe local item ID, title, subtitle, kind label, icon, aliases, optional argument specification, completion text, actions, and history eligibility. The host combines plugin and item IDs into a stable identity. Live results are transient in v1.
- Actions support clipboard copy, URL/path opening, application launch/reveal, executable invocation with an argument array, terminal execution, window operations, and plugin callbacks. Rendering and execution must not switch on plugin identities.
- A missing secondary action falls back to the primary action. Script adapters explicitly supply “run in terminal” as their secondary action. Required arguments use the existing completion behavior and remain a single text argument in v1.
- User live-query scripts require a keyword by default. A manifest can explicitly request all-query activation. Strip the keyword for the plugin’s input while also supplying the full query.
- Discover bundled packages in the app’s resources and user packages in `~/.config/odd-frog/plugins`. A user package with the same ID overrides the bundled package without modifying it; ambiguous duplicates within either location are rejected.
- Bundled plugins start with current feature defaults, including window management off. Newly discovered user plugins remain disabled until enabled. Display their execution mode and query activation in Settings.
- Watch package changes and provide Reload Plugins. Reload stops the affected provider, invalidates its results, rereads its manifest, and restarts it if enabled. Invalid packages expose an error without affecting other plugins.

## Host architecture and feature extraction

**Search and lifecycle**

- Replace feature-specific `LauncherItem` cases with the generic item model. Keep fuzzy scoring, exact-alias matching, argument splitting, result limits, and frecency in the host.
- Add a search coordinator that displays cached catalog matches immediately and merges asynchronous plugin results. Discard responses from older query or plugin generations.
- Use three manifest-declared query roles: exclusive prefix handlers, live answers, and fallbacks. The terminal plugin owns `>`; the calculator supplies live answers. Exclusive handlers suppress other providers; otherwise live answers precede catalog matches, and fallbacks appear only when neither has results.
- Resolve ordering using manifest order followed by plugin ID; preserve result order within each provider. Plugins cannot supply arbitrary host ranking scores.
- Debounce live requests by 75 ms. Allow one active query per provider, cancel superseded work, and retain only the latest pending query. Preserve a user-moved selection by item ID when asynchronous results arrive.
- Start catalog providers when enabled and query-only providers when first needed. Keep persistent providers alive until disabled, reloaded, or app exit. Clear transient results and cancel queries when the panel closes.
- Use separate initialization/catalog and query deadlines: 30 seconds and 2 seconds. Bound protocol messages to 4 MiB. On malformed output, crash, or timeout, terminate the provider, show its failure in Plugins, and allow explicit Reload; avoid automatic restart loops. Normal user-invoked commands retain their existing unrestricted duration.

**Built-in packages**

| Package | Responsibility |
|---|---|
| Applications | App scanning, metadata caching, directory watching, and publishing app items |
| Commands | Configured shell commands, paths, links, URL templates, and link editing |
| Scripts | Existing folder scanning and Raycast-header interpretation; publishes generic command items |
| Calculator | Arithmetic, unit conversion, currency rates, cache, formatting, and copy-result actions |
| Windows | Declares window command names, aliases, icons, and parameterized host actions |
| Web | URL detection and web-search fallbacks |
| Terminal | Exclusive `>` query handling and terminal action creation |

- Preserve existing script behavior, including filename fallback, execution modes, working directory, argument quoting, notifications, and secondary terminal execution. Script discovery does not execute scripts.
- Move calculator code and tests into its own executable/library targets. The host must have no arithmetic or currency types, refresh logic, formatting, or special icons.
- Currency remains local evaluation against a cached table with the existing six-hour refresh policy. Its setting defaults on; turning it off cancels network work while arithmetic and units continue. Refresh events update the current result without transmitting queries.
- Keep Accessibility calls and existing window placement/cascade operations in the host service layer. The Windows package declares the available commands and parameters. Other plugins may request the same service; validate parameters before reaching existing preconditions.
- Build and bundle separate executable products using the existing SwiftPM and Makefile workflow. Sign plugin executables before signing the containing app. Provide a calculator-only build/package target to demonstrate independent replacement.

## Settings, configuration, and authoring

- Use `~/.config/odd-frog/v2/` for fresh host and plugin configuration, and a corresponding application-support `v2` directory for history and plugin data. Do not import, overwrite, or delete legacy configuration, history, or currency cache.
- Keep General for host preferences. Replace Script Folders with a Plugins pane showing enable state, package source, status, error details, Reload, and manifest-defined settings.
- Support boolean, string, number, choice, and folder-list settings with defaults and validation. Host-owned atomic storage supplies effective settings to providers. Invalid external edits retain the last valid configuration.
- Keep Items for catalog-item visibility and aliases. Keep Manage Links as a host-rendered editor backed by a declared link-management capability, rather than checking a plugin ID.
- Define link-management requests for listing, creating, updating, and deleting links. Use stable link IDs and revision checks so renaming preserves item settings and concurrent edits fail visibly. Disable the editor when its provider is unavailable.
- The Commands plugin owns a documented TOML command list; the Scripts plugin owns folder/watch settings; the Calculator owns currency settings; the Windows package declares cascade-step settings.
- Supply working examples for a plain shell command, a keyword-triggered JSON query script, and a persistent provider. Document messages, installation, enabling, reload, logs, and manual migration from the old format.
- Declare host service access in manifests and reject undeclared service requests. This governs the host API; trusted plugin processes still have ordinary local process access.

## Implementation sequence and verification

1. Add the shared contract, generic items/actions, and host service dispatcher. Adapt current features temporarily so the application remains buildable.
2. Add discovery, process supervision, query coordination, plugin settings, and fixture providers.
3. Extract all seven packages, wire the fresh configuration and link editor, then remove temporary adapters and feature-specific host branches.
4. Complete bundling, independent plugin packaging, documentation, and end-to-end verification.

Port existing behavioral tests to their new owners. Add tests for discovery and override rules, API mismatch, generic argument/action behavior, settings validation, link edit conflicts, and script compatibility.

Exercise real fixture processes for one-shot and persistent providers: successful queries, stale responses, cancellation, malformed/oversized output, crashes, timeouts, reload, and disable cleanup. Verify ranking, fallbacks, `>` exclusivity, selection stability, result limits, and transient results staying out of history.

Run the full Swift test suite and release bundle build in separate agterm run sessions. Manually verify app launch/reveal, script notifications and terminal output, link editing, calculator copy, offline currency, window permissions/actions, and plugin settings.

Final acceptance: install a new query script and replace the calculator package while leaving the host binary unchanged; verify both through the launcher. Disabling any feature package must remove its items and background work without breaking the host or other plugins.
