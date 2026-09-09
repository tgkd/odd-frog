# Task: Reminders plugin 1/2 — read-only `rem` provider and the `reminders.items` host service

First of two tasks (32–33). Mirrors the bundled Calendar plugin under `Plugins/Calendar/` one to
one: a new host service, a new snapshot type, a new access-request action, a separate provider
executable, and packaging. Task 33 adds completing and creating reminders on top of this one.

## Goal
Typing `rem` in the launcher lists incomplete Apple Reminders that are overdue or due today;
`rem all`, `rem tomorrow`, `rem week`, `rem <N>d`, and `rem <text>` narrow or widen that list the
same way the Calendar plugin's `cal` words do. Return opens the Reminders app. The first use offers
an "Allow Reminders access" row that triggers the macOS Full Access prompt. `swift test` passes and
`make bundle` ships the provider inside `build/OddFrog.app`.

## Files
- Sources/OddFrogPluginAPI/PluginProtocol.swift               (modify — service name, request/response fields)
- Sources/OddFrogPluginAPI/PluginItem.swift                   (modify — new action kind)
- Sources/OddFrogPluginAPI/RemindersSnapshot.swift            (create — scope, snapshot, reminder value types)
- Sources/OddFrogCore/PluginPackage.swift                     (modify — manifest accepts the new service)
- Sources/OddFrogCore/PluginCoordinator.swift                 (modify — second reader, scope validation, action validation)
- Sources/OddFrog/RemindersService.swift                      (create — EventKit actor for reminders)
- Sources/OddFrog/AppDelegate.swift                           (modify — wire the service, invalidate, run the access action)
- Sources/OddFrog/PluginsPane.swift                           (modify — one helper sentence)
- Resources/Info.plist                                        (modify — reminders usage description)
- Plugins/Reminders/plugin.toml                               (create)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift   (create)
- Plugins/Reminders/Sources/OddFrogReminders/main.swift       (create)
- Plugins/Reminders/Tests/RemindersProviderTests.swift        (create)
- Tests/OddFrogCoreTests/PluginTests.swift                    (modify — constructor call sites, service tests)
- Package.swift                                               (modify — three new targets)
- Makefile                                                    (modify — bundle step and standalone target)
- README.md                                                   (modify — "Calendar and plugins" section)
- docs/query-plugins.md                                       (modify — protocol additions)
- Sources/OddFrogPluginAPI/CalendarSnapshot.swift             (read — the shape to mirror)
- Sources/OddFrog/CalendarService.swift                       (read — the actor to mirror)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarProvider.swift   (read — the provider to mirror)
- Plugins/Calendar/Sources/OddFrogCalendar/main.swift          (read — copy verbatim with names changed)
- Plugins/Calendar/Tests/CalendarProviderTests.swift          (read — test style to mirror)

## Context
- Swift 6 package, `swift-tools-version: 6.0`, macOS 14 deployment target, strict concurrency.
  Tests use the `Testing` framework (`@Test`, `#expect`), not XCTest. TOML parsing uses TOMLKit.
- Plugin protocol today (`PluginProtocol.swift`): `PluginProtocol.version == 1`, `maxBytes` is
  four MiB, `calendarService == "calendar.events"`. `PluginRequest` carries `operation`
  (`prepare` or `query`), `query` (text after the keyword), `fullQuery`, `now`,
  `timeZoneIdentifier`, `maxResults`, and an optional `calendar: CalendarSnapshot`.
  `PluginResponse` carries `id`, optional `calendarRequest: CalendarRange`, and `items`.
  Dates on the wire are Unix seconds via `PluginProtocol.encoder()/decoder()`.
- `PluginAction.Kind` is `openURL, openApplication, copy, requestCalendarAccess`.
  `PluginCoordinator.validate(_:package:)` requires `calendar.events` for
  `requestCalendarAccess` and whitelists URL schemes `https`, `http`, `x-apple.systempreferences`.
- `PluginManifest.parse` rejects any service other than `calendar.events` with the message
  "Unsupported host service."
- `PluginCoordinator.init(readCalendar:exchange:)` takes a `CalendarReader` closure
  `(CalendarRange) async throws -> CalendarSnapshot`. Its query task runs `prepare`, and if the
  response has `calendarRequest` it checks the manifest declares the service and
  `range.isValid(relativeTo: request.now)`, then calls the reader and sets `next.calendar`. After
  `query` it throws "Query cannot request more services." if `calendarRequest` is non-nil.
  The four coordinator constructions in `Tests/OddFrogCoreTests/PluginTests.swift` and the one in
  `AppDelegate.makePluginCoordinator()` are the only call sites.
- `CalendarService` (`Sources/OddFrog/CalendarService.swift`) is an actor holding a lazy
  `EKEventStore`, a 30-second cache keyed by range, `invalidate()`, `requestAccess()` wrapping
  `requestFullAccessToEvents`, and `snapshot(for:)` which maps `EKEventStore.authorizationStatus`
  to `CalendarSnapshot.Access` and returns an empty snapshot unless `.fullAccess`.
- `AppDelegate` owns `calendarService`, observes `.EKEventStoreChanged` and
  `NSApplication.didBecomeActiveNotification` (both call `calendarDidChange()`, which invalidates the
  service and the coordinator), runs a 30-second timer that invalidates while the panel is visible,
  and executes plugin actions in `runPluginAction(_:secondary:)` with a `switch action.kind`. The
  `.requestCalendarAccess` case awaits `calendarService.requestAccess()` and then
  `plugins.invalidate()`. `report(_:)` logs and posts a failure notification.
- The launcher hides the panel before running an item (`controller.onSubmit` calls `hidePanel()`
  then `executor.run`). Plugin rows with no `primary` action ignore Return.
- Icons: `IconCache` renders a plugin row's `symbol` as an SF Symbol, defaulting to
  `puzzlepiece.extension`.
- `PluginsPane.swift` line 15 has helper text ending "Calendar permission is requested when you
  choose Allow Calendar access."
- EventKit reminders API on macOS 14 (verified in the SDK headers):
  `EKEventStore.requestFullAccessToReminders(completion:)`,
  `EKEventStore.authorizationStatus(for: .reminder)` (same `EKAuthorizationStatus` enum as events),
  `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)` selects
  every incomplete reminder including undated ones, and
  `fetchReminders(matching:completion:)` delivers `[EKReminder]?` on a callback (wrap it in
  `withCheckedContinuation`). `EKReminder` exposes `calendarItemIdentifier`, `title`,
  `dueDateComponents: DateComponents?`, `priority: Int` (0 none, 1–4 high, 5 medium, 6–9 low),
  `isCompleted`, `calendar.title`, `url`. Undated reminders have nil `dueDateComponents`; a
  date-only due date has nil `hour`.
- The Reminders app bundle identifier is `com.apple.reminders`. The privacy pane URL is
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders`. The Info.plist key
  for the permission prompt is `NSRemindersFullAccessUsageDescription`.
- Calendar provider conventions to keep: `Calendar(identifier: .gregorian)` with the request's time
  zone, `startOfDay` for day boundaries, exclusive end, rows capped at `min(maxResults, 50)`, empty
  titles replaced by "Untitled …" after trimming, status rows use a fixed id `"status"`, subtitles
  join parts with `" · "`, dates print as `EEE d MMM` and times with `timeStyle = .short`.
- The Calendar range word parser: first word among `today`, `tomorrow`, `week`, `<N>d` (positive
  integer with a `d` suffix, clamped to 30) is a range; anything else is search text; text after a
  range word filters within it.
- `make bundle` copies `.build/release/OddFrogCalendar` and `Plugins/Calendar/plugin.toml` into
  `Contents/Resources/Plugins/calendar/` and codesigns the executable before signing the app.
  `make calendar-plugin` builds the standalone package into `build/plugins/calendar/`.
  Bundled packages are discovered from `Bundle.main.resourceURL/Plugins/<folder>/plugin.toml`.
- Verified today: `swift test` passes with 116 core tests and 8 Calendar tests; `make bundle` exits 0.
  A cold release build takes several minutes.

## Plan
1. `Sources/OddFrogPluginAPI/RemindersSnapshot.swift` (create). Define:
   - `RemindersScope: Codable, Sendable, Equatable` with `var limit: Int` and
     `func isValid() -> Bool` returning `1...2000 ~= limit`. This is the provider's request in
     `prepare`; the host caps the snapshot at `limit` reminders.
   - `ReminderItem: Codable, Sendable, Equatable` with `id: String` (the
     `calendarItemIdentifier`), `title: String`, `due: Date?`, `allDay: Bool`, `listName: String`,
     `priority: Int`, `url: String?`. Give it a memberwise `public init` with defaults for
     `due`, `allDay`, `listName`, `priority`, `url`, like `CalendarEvent`.
   - `RemindersSnapshot: Codable, Sendable, Equatable` with nested
     `enum Access: String { notDetermined, fullAccess, denied, restricted, writeOnly }`,
     `access`, `reminders: [ReminderItem]`, and `truncated: Bool` (true when the host dropped
     reminders past `limit`). `public init(access:reminders: = [], truncated: = false)`.
2. `PluginProtocol.swift`: add `public static let remindersService = "reminders.items"` and
   `public static let services: Set<String> = [calendarService, remindersService]`. Add
   `public var reminders: RemindersSnapshot?` to `PluginRequest` (init parameter with default nil,
   after `calendar`). Add `public var remindersRequest: RemindersScope?` to `PluginResponse` (init
   parameter with default nil, after `calendarRequest`).
3. `PluginItem.swift`: add `requestRemindersAccess` to `PluginAction.Kind`.
4. `PluginPackage.swift`: replace the `allSatisfy` check with
   `value.services.allSatisfy { PluginProtocol.services.contains($0) }`. Keep the message.
5. `PluginCoordinator.swift`: add `public typealias RemindersReader = @Sendable (RemindersScope) async throws -> RemindersSnapshot`,
   a stored `readReminders`, and an init parameter `readReminders:` placed between
   `readCalendar:` and `exchange:` (required, no default). In the query task, after the calendar
   block, mirror it: if `preparation.remindersRequest` is set, require the manifest to contain
   `PluginProtocol.remindersService` and `scope.isValid()`, else throw
   `PluginError.message("Plugin requested an undeclared service or an invalid reminders scope.")`;
   then `next.reminders = try await readReminders(scope)`. Extend the post-query guard so either
   `calendarRequest` or `remindersRequest` being non-nil throws the existing "Query cannot request
   more services." In `validate`, add a `.requestRemindersAccess` case that requires
   `PluginProtocol.remindersService` with message "Plugin did not declare reminders access."
6. `Sources/OddFrog/RemindersService.swift` (create). An `actor RemindersService` shaped like
   `CalendarService`: lazy `EKEventStore`, `invalidate()`, `requestAccess()` wrapping
   `requestFullAccessToReminders`, and `func snapshot(for scope: RemindersScope) async throws -> RemindersSnapshot`.
   Map `authorizationStatus(for: .reminder)` to `RemindersSnapshot.Access` exactly as
   `CalendarService` does for events (`@unknown default` → `.restricted`), and return an empty
   snapshot with `cached = nil` unless `.fullAccess`. Cache the last snapshot for 30 seconds keyed
   by scope. Fetch with `predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)`
   and `fetchReminders(matching:completion:)` bridged through `withCheckedContinuation`; treat a nil
   result as empty. Map each reminder: `id = calendarItemIdentifier`, `title = title ?? ""`,
   `due = components.calendar?.date(from: components) ?? Calendar.current.date(from: components)`
   when `dueDateComponents` is non-nil, `allDay = components.hour == nil`,
   `listName = calendar.title`, `priority`, `url = url?.absoluteString`. Sort by `due` ascending
   with undated reminders last, ties by title then id. Drop duplicates by id (EventKit can repeat
   items after a store change), then take `prefix(scope.limit)` and set `truncated` when more
   remained. Throw a private `RemindersServiceError.invalidScope` if `!scope.isValid()`.
7. `AppDelegate.swift`: add `private let remindersService = RemindersService()`; pass
   `readReminders: { scope in try await service.snapshot(for: scope) }` in
   `makePluginCoordinator()`. In `calendarDidChange()` also `await remindersService.invalidate()`
   (rename the method to `storeDidChange` and update both observer registrations). Add a
   `.requestRemindersAccess` case to `runPluginAction` that mirrors the calendar case with the
   message prefix "Reminders access: ".
8. `Resources/Info.plist`: add `NSRemindersFullAccessUsageDescription` after the calendars key with
   the string "Odd Frog reads your reminders to list what is due when you use the Reminders plugin."
9. `PluginsPane.swift`: change the helper sentence to "Calendar and Reminders permission is
   requested when you choose the Allow access row."
10. `Plugins/Reminders/plugin.toml` (create):
    ```toml
    id = "reminders"
    name = "Reminders"
    version = "0.1.0"
    api_version = 1
    executable = "OddFrogReminders"
    keyword = "rem"
    services = ["reminders.items"]
    ```
11. `Plugins/Reminders/Sources/OddFrogReminders/main.swift` (create): copy the Calendar `main.swift`
    verbatim, importing `RemindersPluginCore`, calling `RemindersProvider.respond(to:)`, and
    prefixing stderr with "Reminders provider: ".
12. `Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift` (create).
    `public enum RemindersProvider { public static func respond(to request: PluginRequest) -> PluginResponse }`.
    Parsing, on the whitespace-split words of `request.query`, lowercasing the first word:
    - `today` (or no words): overdue plus due before the end of today.
    - `tomorrow`: due within tomorrow only (no overdue).
    - `week`: overdue plus due before the end of the seventh day counting today.
    - `<N>d` (same `dayCount` rule as Calendar, clamped to 30): overdue plus due before the end of
      day N counting today.
    - `all`: every incomplete reminder, including undated ones.
    - Anything else: search text over every incomplete reminder, including undated ones.
    - Words after a range word are a filter, matched with `localizedStandardContains` against
      `title` and `listName`.
    "Overdue" means a dated reminder with `due < request.now`, except that an `allDay` reminder is
    overdue only when `due < startOfDay(now)`, so a date-only reminder due today is not overdue
    until tomorrow. Undated reminders appear only for `all` and for search. Day boundaries use `Calendar(identifier: .gregorian)` in the request's time zone
    (falling back to `.gmt`), `startOfDay(for: request.now)`, and `date(byAdding: .day, ...)`.
    `prepare` returns `PluginResponse(id:, remindersRequest: RemindersScope(limit: 2000))` for every
    query. `query` without `request.reminders` returns the status row "Reminders unavailable" /
    "The host did not supply reminders data." Access rows mirror Calendar: `notDetermined` and
    `writeOnly` → "Allow Reminders access" / "Press Return to let Odd Frog read your reminders." with
    `PluginAction(.requestRemindersAccess)`; `denied` → "Reminders access is off" / "Press Return to
    open Reminders privacy settings." with `.openURL` to the privacy pane URL above; `restricted` →
    "Reminders access is restricted" / "Your Mac's restrictions prevent reading reminders." with no
    action. Sort matches: overdue and dated ascending by `due`, then undated by title, ties by id.
    Each row: `id = reminder.id`, `title` trimmed with "Untitled reminder" fallback, `kind:
    "Reminder"`, `symbol: "checklist"`, `primary: PluginAction(.openApplication, "com.apple.reminders")`,
    no secondary. Subtitle parts joined by `" · "`: first the date part, then `listName` when
    non-empty, then "High priority" when `1...4 ~= priority`. Date part: "Overdue · EEE d MMM" for
    overdue (add " h:mm a" via `timeStyle = .short` when not `allDay`), "EEE d MMM" plus the short
    time for dated, "No date" for undated. Cap rows at `max(1, min(request.maxResults, 50))`.
    Empty state: title "No reminders due today" / "…tomorrow" / "…in the next 7 days" /
    "…in the next N days" / "No reminders" for `all`; with a filter, "No matching reminders …";
    subtitle "Press Return to open Reminders." with the open-application action. When
    `snapshot.truncated` is true, append " (list truncated)" to the empty-state title only.
    Keep the file comment-free.
13. `Plugins/Reminders/Tests/RemindersProviderTests.swift` (create), `struct RemindersProviderTests`
    in the style of `CalendarProviderTests` (fixed `now` of `2026-09-09T12:00:00Z`, UTC, helper
    builders). Cover: `prepare` always requests limit 2000; `today` includes overdue and due-today
    but excludes tomorrow and undated; `tomorrow` excludes overdue; `week` and `12d` boundaries;
    `all` orders overdue, dated, undated; search matches title and list name and includes undated;
    filter after a range word; access rows and their actions; empty-state titles; whitespace title
    becomes "Untitled reminder"; the "High priority" suffix; a JSON round trip of a
    `PluginRequest` with `reminders` through `PluginProtocol.encoder()/decoder()`.
14. `Tests/OddFrogCoreTests/PluginTests.swift`: add `readReminders:` to the four constructor
    calls (the undeclared-service test records an `Issue` if it is called, like the calendar
    reader). Extend `manifest(service:)` so the helper can emit `["reminders.items"]` and assert
    `PluginManifest.parse` accepts it and rejects `["nope"]`. In
    `hostServiceRangeActionAndKeywordValidation`, add a package declaring `reminders.items`, check
    `authorize(PluginAction(.requestRemindersAccess), pluginID:)` succeeds for it and throws for the
    calendar package, and add a coordinator test where `prepare` returns
    `RemindersScope(limit: 5)` and the reminders reader is invoked once for a declaring package.
15. `Package.swift`: add `.target(name: "RemindersPluginCore", dependencies: ["OddFrogPluginAPI"], path: "Plugins/Reminders/Sources/RemindersPluginCore")`,
    `.executableTarget(name: "OddFrogReminders", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Sources/OddFrogReminders")`,
    and `.testTarget(name: "RemindersPluginTests", dependencies: ["RemindersPluginCore", "OddFrogPluginAPI"], path: "Plugins/Reminders/Tests")`,
    each directly after its Calendar counterpart.
16. `Makefile`: add `reminders-plugin` to `.PHONY` and a target mirroring `calendar-plugin`
    (product `OddFrogReminders`, folder `$(BUILD)/plugins/reminders`). In `bundle`, after the
    calendar lines, copy `Plugins/Reminders/plugin.toml` and `.build/release/OddFrogReminders` into
    `$(CONTENTS)/Resources/Plugins/reminders/` and codesign the executable before the app is signed.
17. `README.md`: rename the section to "Calendar, Reminders, and plugins"; after the Calendar
    bullets and paragraphs add a Reminders block listing the `rem` forms above, the permission flow
    (Full Access, no writes in this slice), Return opening Reminders, and that `make reminders-plugin`
    produces `build/plugins/reminders/`. `docs/query-plugins.md`: document `reminders.items`, the
    `remindersRequest` object `{"limit": 2000}` with its 1–2000 bound, the `reminders` snapshot
    example, and the `requestRemindersAccess` row in the actions table.

Approach note: the host fetches every incomplete reminder and the provider filters, instead of a
date-window request like Calendar's, because EventKit's incomplete-reminder predicate with a
nil range is the only form that also returns undated reminders, and the payload is bounded by
`limit` plus the four-MiB transport cap.

## Constraints
- No comments, doc comments, or section banners in any new or edited code. The existing comments
  in `PluginProcess.swift` and `CalendarProvider.swift` stay untouched.
- Always brace conditionals and returns: `if x { return nil }` on one line is fine; bare
  `if x return` is not.
- Swift 6 strict concurrency: new types crossing the process boundary are `Sendable`; EventKit
  objects never leave `RemindersService`.
- The host must not link `RemindersPluginCore`; `OddFrogCore` and `OddFrog` depend only on
  `OddFrogPluginAPI`.
- Keep the wire format additive: existing Calendar JSON from `docs/query-plugins.md` still decodes;
  every new field is optional or has a default on the API side.
- No `fetchReminders` results, titles, or ids in the app log or in launcher history.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes from the repo root (expect the existing 116 core and 8 Calendar tests plus
  the new Reminders suite; the core suite count grows with step 14).
- `swift build -c release --product OddFrogReminders` succeeds and leaves
  `.build/release/OddFrogReminders`.
- `make bundle` exits 0 and `build/OddFrog.app/Contents/Resources/Plugins/reminders/` contains
  `plugin.toml` and a signed `OddFrogReminders`.
- JSON smoke test from the repo root, after the build above:
  ```
  printf '{"apiVersion":1,"id":"1","operation":"prepare","query":"12d","fullQuery":"rem 12d","now":%d,"timeZoneIdentifier":"UTC","maxResults":8}' "$(date +%s)" | .build/release/OddFrogReminders
  ```
  prints a response whose `remindersRequest` is `{"limit":2000}` and whose `items` is empty.
- Manual: quit the running app, `rsync -a --delete build/OddFrog.app/ /Applications/OddFrog.app/`,
  `open /Applications/OddFrog.app`, type `rem`. First run shows "Allow Reminders access"; Return
  triggers the macOS prompt; after granting, `rem` lists overdue and due-today reminders and
  `rem all` lists everything incomplete. Do not launch `build/OddFrog.app` while the installed
  copy is running.

## Out of scope
- Completing, creating, editing, or deleting reminders (task 33).
- Reading reminder notes, alarms, recurrence, or subtasks.
- Choosing lists, showing completed reminders, or any Reminders-specific UI.
- Changing the Calendar provider, `PluginProcess`, discovery, or the Plugins settings pane beyond
  the helper sentence.

## Open questions
none
