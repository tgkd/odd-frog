# Task: Reminders plugin 2/2 — complete a reminder with Command-Return and add one with `rem add`

Second of two tasks (32–33). Requires task 32 merged: the `reminders.items` service,
`RemindersSnapshot`, `RemindersService`, and the `rem` provider under `Plugins/Reminders/`. This
task adds the first write path through a plugin: two host actions that the provider can attach to
rows, executed by the host through EventKit.

## Goal
On any reminder row, Command-Return marks that reminder completed and posts a notification
"Completed: <title>". `rem add Buy milk` shows one row "Buy milk" whose Return creates an
incomplete reminder titled "Buy milk" in the default Reminders list and posts "Added: <title>".
A `rem <text>` search with no matches offers the same add row for `<text>`. The provider never
touches EventKit; it only returns actions the host validates and runs.

## Files
- Sources/OddFrogPluginAPI/PluginItem.swift                   (modify — two action kinds)
- Sources/OddFrogPluginAPI/RemindersSnapshot.swift            (modify — default list name)
- Sources/OddFrogCore/PluginCoordinator.swift                 (modify — validate the two actions)
- Sources/OddFrog/RemindersService.swift                      (modify — complete and create)
- Sources/OddFrog/AppDelegate.swift                           (modify — run the two actions)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift   (modify — `add` word, secondary action, fallback row)
- Plugins/Reminders/Tests/RemindersProviderTests.swift        (modify)
- Tests/OddFrogCoreTests/PluginTests.swift                    (modify — action validation)
- README.md                                                   (modify — Reminders bullets)
- docs/query-plugins.md                                       (modify — actions table)
- Sources/OddFrog/Notifier.swift                              (read — `post(title:body:)` and `failure(_:)`)
- Sources/OddFrog/CalendarService.swift                       (read — actor style)

## Context
- After task 32, `PluginAction.Kind` is `openURL, openApplication, copy, requestCalendarAccess,
  requestRemindersAccess`; `PluginCoordinator.validate(_:package:)` switches over it and throws
  `PluginError.message` for undeclared services or bad URL schemes; `AppDelegate.runPluginAction`
  authorizes via `plugins.authorize(action, pluginID:)` and then switches on the kind. Both switches
  are exhaustive, so new kinds fail to compile until handled.
- `ReminderItem.id` is the EventKit `calendarItemIdentifier`. `EKEventStore.calendarItem(withIdentifier:)`
  returns `EKCalendarItem?`; cast to `EKReminder`. Setting `isCompleted = true` sets the completion
  date; persist with `save(_ reminder: EKReminder, commit: true)` (throws). New reminders are
  `EKReminder(eventStore:)` with `title` and `calendar = defaultCalendarForNewReminders()`; a nil
  default calendar means no list is available and the create must fail with a message.
  `EKReminder.calendar.title` is the list name.
- Saving through the store fires `.EKEventStoreChanged`, which `AppDelegate` already observes to
  invalidate both services and the coordinator. The launcher panel is hidden before any action
  runs, so the visible feedback for a write is a notification, not a row change.
- `Notifier.post(title:body:)` shows a user notification; `Notifier.failure(_:)` is what
  `AppDelegate.report(_:)` uses for errors. `AppDelegate` holds `notifier`.
- Provider parsing after task 32: first word among `today`, `tomorrow`, `week`, `<N>d`, `all` is a
  range word, remaining words filter; any other first word makes the whole query a search over all
  incomplete reminders. Rows carry `primary: openApplication com.apple.reminders` and no secondary.
  Empty states are status rows with id `"status"`.
- The launcher runs the secondary action on Command-Return through
  `ActionExecutor.runSecondary` → `onPluginAction(result, true)`; a missing secondary falls back to
  primary. Subtitles in the Calendar provider advertise the secondary with a trailing " · ⌘↩ Join".
- Title limits: the host caps the create title at 500 characters after trimming; the launcher field
  never produces newlines, but the provider must still trim.

## Plan
1. `PluginItem.swift`: add `completeReminder` and `createReminder` to `PluginAction.Kind`.
   `value` is the reminder id for `completeReminder` and the new title for `createReminder`.
2. `RemindersSnapshot.swift`: add `public var defaultListName: String?` to `RemindersSnapshot`
   with a defaulted init parameter after `truncated`. `RemindersService.snapshot(for:)` fills it from
   `defaultCalendarForNewReminders()?.title` when access is `.fullAccess`.
3. `PluginCoordinator.validate`: both new kinds require `PluginProtocol.remindersService`
   ("Plugin did not declare reminders access."). `completeReminder` additionally requires a non-empty
   `value` ("Plugin returned an empty reminder ID."); `createReminder` requires a trimmed `value`
   of 1...500 characters ("Plugin returned an invalid reminder title.").
4. `RemindersService.swift`: add `func complete(id: String) async throws -> String` that finds the
   reminder, throws a private `RemindersServiceError.notFound` when the item is missing or already
   completed, sets `isCompleted = true`, saves with commit, clears the cache, and returns the title
   (or "Untitled reminder"). Add `func create(title: String) async throws -> String` that builds the
   reminder in the default list, throws `RemindersServiceError.noDefaultList` when there is none,
   saves with commit, clears the cache, and returns the list name. Both check
   `authorizationStatus(for: .reminder) == .fullAccess` first and throw
   `RemindersServiceError.noAccess` otherwise. Give the error enum `LocalizedError` conformance
   with `errorDescription` strings: "Reminder not found.", "No default Reminders list.",
   "Reminders access is not granted."
5. `AppDelegate.runPluginAction`: add the two cases. `.completeReminder` awaits
   `remindersService.complete(id: action.value)` and posts `notifier.post(title: "Completed", body: title)`;
   `.createReminder` awaits `remindersService.create(title:)` and posts
   `notifier.post(title: "Added to <list>", body: action.value)`. Errors go to
   `report("Reminders: \(error.localizedDescription)")`. Both end with `plugins.invalidate()` like
   the access case.
6. `RemindersProvider.swift`:
   - Recognize `add` (and `new`) as a first word. With a non-empty remaining title (trimmed), return
     one row: `id: "add"`, `title` = the text, `subtitle` = "Press Return to add to <defaultListName>"
     (or "Press Return to add a reminder" when the snapshot has no default list name), `kind:
     "Reminder"`, `symbol: "plus.circle"`, `primary: PluginAction(.createReminder, text)`. With an
     empty title, return the status row "Add a reminder" / "Type a title after rem add." with no
     action. `add` needs the same access rows as other queries, so it still goes through `prepare`
     and the access switch; do not special-case it before the access check.
   - Give every reminder row `secondary: PluginAction(.completeReminder, reminder.id)` and append
     " · ⌘↩ Complete" to its subtitle.
   - When a search (`rem <text>`, not a range word and not `add`) matches nothing, return the add
     row for `<text>` instead of the "No matching reminders" status row, with subtitle
     "No matches · Press Return to add to <defaultListName>". Range-word queries keep their
     empty-state status rows.
7. `RemindersProviderTests.swift`: add tests for the `add` row and its action value, the empty
   `add` status row, the secondary complete action and subtitle suffix on reminder rows, the
   search-miss add row, and that `add` with `notDetermined` access still returns the access row.
8. `PluginTests.swift`: in the action validation test, assert `authorize` accepts
   `completeReminder` with an id and `createReminder` with a title for the reminders package, and
   rejects an empty id, a whitespace-only title, a 501-character title, and both kinds for the
   calendar package.
9. `README.md` Reminders bullets: add `rem add Buy milk` and the Command-Return completion, and
   change the permission sentence to say the plugin can complete and create reminders but never
   edits or deletes them. `docs/query-plugins.md`: add `completeReminder` (reminder id from the
   snapshot) and `createReminder` (title, 1–500 characters) rows to the actions table, both
   requiring `reminders.items`.

Approach note: completion and creation live in the host as generic actions with validated string
values, rather than in the provider, because the provider has no EventKit access by design and the
host already owns permissions, the store, and change notifications. Alternative rejected: a third
`mutate` exchange that would have given providers a write channel and required its own sandboxing.

## Constraints
- No comments, doc comments, or section banners in any new or edited code.
- Always brace conditionals and returns.
- Swift 6 strict concurrency: EventKit objects stay inside `RemindersService`; strings cross actors.
- The provider must not import EventKit or link anything but `OddFrogPluginAPI` and Foundation.
- Never delete reminders or edit titles, dates, or notes; `isCompleted` and creation are the only
  writes.
- Reminder titles and ids do not enter the app log or launcher history; notifications may show the
  title.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes from the repo root.
- `make bundle` exits 0.
- JSON smoke test after `swift build -c release --product OddFrogReminders`:
  ```
  printf '{"apiVersion":1,"id":"1","operation":"query","query":"add Buy milk","fullQuery":"rem add Buy milk","now":%d,"timeZoneIdentifier":"UTC","maxResults":8,"reminders":{"access":"fullAccess","reminders":[],"truncated":false,"defaultListName":"Inbox"}}' "$(date +%s)" | .build/release/OddFrogReminders
  ```
  prints one item titled "Buy milk" with `primary.kind` `createReminder` and `primary.value`
  `Buy milk`.
- Manual, after installing the bundle into `/Applications/OddFrog.app` as in task 32: `rem add Test
  from Odd Frog` then Return creates the reminder in the default list and shows the "Added to"
  notification; `rem` shows it; Command-Return on it shows "Completed" and it disappears from `rem`
  within 30 seconds or on the next open. Reminders.app reflects both changes.

## Out of scope
- Due dates, lists, or priorities on created reminders (`rem add` takes only a title).
- Undoing a completion, deleting, or editing reminders.
- Any change to the Calendar provider or to `PluginProcess`.

## Open questions
none
