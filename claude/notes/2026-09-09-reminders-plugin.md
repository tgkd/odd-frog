# Reminders plugin — 2026-09-09

## Implementation

Reminders is the second bundled query plugin, written from two task specs,
`.tasks/32-reminders-plugin-read.md` (read-only) and `.tasks/33-reminders-plugin-write.md` (writes).
Source lives in `Plugins/Reminders/`, with `plugin.toml`, `RemindersPluginCore`, `OddFrogReminders`,
and feature tests, mirroring `Plugins/Calendar/`. The keyword is `rem`.

`OddFrogPluginAPI` gained a second host service, `reminders.items`, with `RemindersScope`,
`ReminderItem`, and `RemindersSnapshot`. The host owns EventKit through a `RemindersService` actor;
the provider links only the shared API and never imports EventKit.

## Behavior

- `rem` / `rem today`: overdue reminders plus everything due before the end of today.
- `rem tomorrow`: tomorrow only, without overdue items.
- `rem week`: overdue plus the next seven calendar days, including today.
- `rem <N>d`: the same for N days, clamped to 30 (`rem 12d`).
- `rem all`: every incomplete reminder, including undated ones.
- `rem <text>`: search titles and list names across every incomplete reminder, undated included.
- Range words accept a filter: `rem week design`, `rem 12d design`.
- `rem add <title>` / `rem new <title>`: create a reminder in the default list. `rem add` alone is an
  inert status row. A search matching nothing returns the same add row for the typed text.
- Return opens Reminders. Command-Return completes the selected reminder and posts a notification.
- Rows show due date, list name, a high-priority marker for EventKit priority 1–4, and the
  Command-Return hint. Undated rows read "No date".
- An all-day reminder is overdue only once its day has passed; a timed one the moment it is late.
- Empty states name the period, and append "(list truncated)" when the host cut the list.

## Plugin runtime

`prepare` returns `remindersRequest: {"limit": 2000}` for every query; the host validates 1–2000 and
returns incomplete reminders only, sorted by due date with undated last, deduplicated by identifier,
truncated to the limit. This differs from Calendar's date-range request on purpose: EventKit's
incomplete-reminder predicate returns undated reminders only when the range is nil, so the payload is
bounded by count instead of by dates. Snapshots cache for 30 seconds and invalidate on store changes.

Writes are host actions, not provider code. `completeReminder` carries a reminder identifier and
`createReminder` a title; `PluginCoordinator` requires the declaring package, a non-empty identifier,
and a trimmed title of 1–500 characters before `AppDelegate` touches the store. The plugin sets
`isCompleted` and creates reminders in `defaultCalendarForNewReminders`; it never edits, deletes, or
reads notes. `EKReminder` values are mapped inside the fetch callback because the class is not
`Sendable` and cannot cross the continuation under Swift 6 strict concurrency.

`Notifier.post` gained an optional `log:` parameter, and the two reminder notifications pass `false`,
so reminder titles stay out of the app log while the notification still shows them. That is a
deliberate deviation from the spec, which listed `Notifier.swift` as read-only.

## Build and installation

- Bundled provider: `/Applications/OddFrog.app/Contents/Resources/Plugins/reminders/`.
- `make bundle` builds and signs both providers before the app.
- `make reminders-plugin` independently produces `build/plugins/reminders/`.
- `Resources/Info.plist` carries `NSRemindersFullAccessUsageDescription`.

## Verification and remaining work

Passed 140 Swift tests (117 core, 8 Calendar, 15 Reminders), the release bundle build, provider
signature checks, and JSON smoke tests against both the debug and bundled Reminders executables.
Coverage includes range boundaries, the all-day overdue rule, undated ordering, search over titles and
list names, permission states, empty-state wording, truncation, the add row and its create action,
the complete secondary action, scope validation, and action authorization for declaring packages.

The verified bundle was installed into `/Applications` and launched; bundled and installed provider
hashes matched. Live behavior against a real account was not verified: Reminders Full Access had not
been granted at the time of writing, so `rem` shows the access row until the user answers the macOS
prompt. Due dates, list choice, and priority on created reminders, plus undo, delete, edit, notes, and
subtasks, remain deferred. Changes were not committed during this work.

References: `.tasks/32-reminders-plugin-read.md`, `.tasks/33-reminders-plugin-write.md`,
`docs/query-plugins.md` (protocol), the Reminders section of `README.md`, and
`claude/notes/2026-09-09-calendar-plugin.md` (the plugin this one mirrors).
