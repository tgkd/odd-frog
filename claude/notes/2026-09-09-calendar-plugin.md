# Calendar plugin — 2026-09-09

## Implementation

Calendar is a separate executable plugin, not a Calendar-specific launcher view. Source lives in
`Plugins/Calendar/`, with `plugin.toml`, `CalendarPluginCore`, `OddFrogCalendar`, and feature tests.
The host does not link Calendar query/presentation logic. `OddFrogPluginAPI` defines the shared,
versioned JSON contract; the host owns EventKit access, permissions, rendering, and actions.

This is the first slice of `docs/plugin-system-rework.md`, not the full migration of existing
features. Other built-ins still use their original implementation.

## Behavior

- `cal` / `cal today`: remaining events today, including ongoing and all-day events.
- `cal tomorrow`: tomorrow's agenda.
- `cal week`: the next seven calendar days, including today.
- `cal <N>d`: the next N calendar days, including today, clamped to 30 (`cal 12d`). Numbers without
  the `d` suffix, `0d`, or other spellings fall through to text search.
- `cal <text>`: search event titles, calendar names, and locations over 30 calendar days.
- Explicit periods can also be filtered: `cal tomorrow design`, `cal week design`, `cal 12d design`.
- Empty states name the period: "No more events today", "No more events in the next 12 days",
  "No matching events in the next 30 days". A 30-day message without `<N>d` means the text search
  matched nothing, not that the calendar is empty; bare `cal` only covers today.
- Return opens Calendar, without selecting a specific event. Command-Return joins a recognized
  HTTPS Zoom, Google Meet, Teams, or Webex URL from the event URL/location; otherwise opens Calendar.
- The access row requests macOS Full Access only when activated. The feature does not edit events
  or read event notes. Denied access links to Calendar privacy settings.
- Results remain chronological and transient; they do not enter launcher history.

## Plugin runtime

Each query uses two one-shot JSON exchanges: `prepare` requests a date range, then `query` receives
a host snapshot and returns generic rows/actions. Dates are Unix seconds. The manifest declares
the exclusive keyword and `calendar.events` service; the host validates service access and ranges.

Queries debounce for 75 ms, cancel superseded work, and reject stale results. Each process exchange
has a two-second deadline and four-MiB input/output limits. Private temporary transport files are
removed after exchanges. Cancellation immediately kills the provider, including during app exit.
Failures remain visible until Reload Plugins. EventKit runs on an actor; snapshots are cached in
memory for up to 30 seconds and invalidated on store changes. Background refresh retains rows so
the selected event can be preserved.

Settings → Plugins provides enable/disable controls, source/status/errors, and Reload. The menu bar
also provides Reload Plugins. Packages are trusted local executables, not sandboxed. User packages
default to disabled and can override bundled packages by manifest ID. Conflicting enabled keywords
fail visibly. Package changes require an explicit reload; persistent providers and watching are deferred.

## Build and installation

- Installed app: `/Applications/OddFrog.app`.
- Bundled Calendar: `/Applications/OddFrog.app/Contents/Resources/Plugins/calendar/`.
- Additional user packages: `~/.config/odd-frog/plugins/`, respecting `XDG_CONFIG_HOME`.
- `make bundle` builds the app with Calendar included and signs the provider before the app.
- `make calendar-plugin` independently produces `build/plugins/calendar/`.
- Project `build/` is only build output. The installed app has no dependency on it.
- Provider enable overrides are `[[plugins]]` entries with `id` and `enabled` in `settings.toml`.

The verified build was installed into `/Applications` and launched. App and provider hashes matched
the tested build. Only the installed instance remained running. During UI verification, the computer
use tool launched a second copy from `build/` and timed out; that test instance was explicitly stopped.
Do not launch a build copy alongside the installed app when verifying future changes.

## Verification and remaining work

Passed 123 Swift tests (116 core and 7 Calendar), release app and standalone-provider packaging,
signature checks, and JSON smoke tests against both packaged Calendar executables. Coverage includes
date/DST boundaries, overlap filtering, permissions, meeting URLs, discovery/overrides, invalid
responses, timeouts, oversized output, cancellation, stale results, and service/action validation.

Later on 2026-09-09, `cal <N>d` was added after the user read "No matching events in the next 30
days" as an empty calendar. Calendar tests passed (7), `make bundle` was rsynced into
`/Applications/OddFrog.app`, the app was relaunched from there, and `cal 30d` showed the real agenda
with Calendar access granted. The bundled and installed provider hashes matched.

One real event rendered with a blank title because the provider substituted "Untitled event" only
for an exactly empty title. Titles are now trimmed first, so whitespace-only titles read "Untitled event".

Live UI behavior and the real-calendar permission flow were not verified in the first pass: UI automation timed out,
and the user had not reported the result of granting Calendar access. Exact-event opening, event
creation/editing, calendar selection, and detail views remain deferred.

References: `docs/calendar-plugin.md` (base plan), `docs/query-plugins.md` (protocol and example),
and the Calendar/plugins section of `README.md`. The pre-existing user edit in
`Sources/OddFrog/main.swift` was preserved. Changes were not committed during this work.
