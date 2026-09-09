# Calendar plugin: base implementation

Calendar is the first independently packaged live-query provider. This is an incremental slice of
`plugin-system-rework.md`; existing built-in features and configuration stay in place for now.

## Scope

- `cal` / `cal today`: remaining events today, including ongoing and all-day events.
- `cal tomorrow`: tomorrow's events. `cal week`: the next seven calendar days, including today.
- `cal <N>d`: the next N calendar days, including today, up to 30 (`cal 12d`).
- `cal <text>`: search titles, calendar names, and locations over the next 30 calendar days.
- Chronological, transient list results with local times, calendar names, and locations.
- Return opens Calendar; Command-Return joins a recognized meeting URL when available, otherwise
  opens Calendar. Opening a specific event and editing/creating events are deferred.
- Explicit permission action, denied/restricted states, and an empty-agenda result.

## Boundary

`OddFrogPluginAPI` defines a versioned JSON contract. A `plugin.toml` package declares an executable,
an exclusive keyword, and required services. The Calendar executable depends only on that API and
its own feature library; the host does not link Calendar query or presentation logic.

A query has two one-shot exchanges: `prepare` declares the required calendar date range; `query`
receives the host's snapshot and returns generic rows/actions. Dates on the wire are Unix seconds.
The host owns EventKit, macOS permission prompts, bounded range validation, and action execution.
Only packages declaring `calendar.events` receive calendar data or may request calendar access.
Providers are trusted local executables, not sandboxed. The service declaration gates host API access.

The runtime discovers bundled and user packages, rejects ambiguous IDs/keywords, supports user
overrides, and defaults new user packages to disabled. Settings exposes enable state, source, keyword,
errors, and Reload. Each query is debounced, cancels its predecessor, and rejects stale results.
Processes have a two-second deadline per exchange and four-MiB input/output limits; failures remain
visible until Reload. Closing the launcher cancels work and clears event rows.

EventKit runs on a dedicated actor. In-memory snapshots expire after 30 seconds and invalidate on
store changes. Permission is requested only when the user activates the access row. Calendar data
is not persisted in history or plugin configuration. No custom plugin UI is introduced.

## Delivery and verification

1. Shared contract, discovery, process runner, and behavior tests with real fixture executables.
2. Separate Calendar package, agenda/search/date-boundary tests, and JSON smoke test.
3. Host calendar service, asynchronous list integration, actions, and Plugins settings pane.
4. Bundle/sign the provider before the app; document independent package replacement.
5. Run the full Swift test suite, release bundle build, and app/UI smoke checks. Real account access
   requires the user's response to macOS's Calendar permission prompt.

Persistent providers, package watching, migration of existing features, custom settings schemas,
event editing, calendar filtering, and detail views remain outside this base slice.
