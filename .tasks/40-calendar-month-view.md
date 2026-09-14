# Task: Calendar month view — `PluginView.month`, host month window, and `cal month`

The Calendar plugin gains a plain month grid. `cal month` opens it directly, and bare `cal` lists
a "Show month" row after its agenda rows. The grid is drawn and navigated entirely by the host
with the user's calendar settings. It reads no events and changes no host service.

## Goal
A provider's `activate` result may carry `view: {kind: "month", id, title}`. The host opens (or
brings forward) one month window showing the current month in the user's calendar: a month/year
heading, weekday headers starting at the user's first weekday, and a fixed 6×7 grid with today
marked and adjacent-month days muted. Previous/Next/Today buttons and the ← → T Esc keys
navigate and close. The Calendar plugin returns that view from a `month` callback. `cal month`
yields only that row without touching calendar services, and bare `cal` appends it as the last
row whenever at least two rows fit. `swift test` passes.

## Files
- Sources/OddFrogPluginAPI/PluginView.swift                          (modify — `Kind.month`, month initializer)
- Sources/OddFrogCore/PluginCoordinator.swift                        (modify — accept `.month` in view validation)
- Sources/OddFrogCore/MonthGrid.swift                                (create — pure grid model)
- Sources/OddFrog/MonthWindowController.swift                        (create — window, grid, navigation, refresh)
- Sources/OddFrog/AppDelegate.swift                                  (modify — route `.month` views to the window)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarProvider.swift (modify — month row/view, bare-query slot, range parsing dedupe)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarHandler.swift  (modify — `cal month` short-circuit, `activate`)
- Plugins/Calendar/Tests/CalendarProviderTests.swift                 (modify — month row tests, update two existing assertions)
- Plugins/Calendar/Tests/CalendarHandlerTests.swift                   (create)
- Tests/OddFrogCoreTests/MonthGridTests.swift                        (create)
- Tests/OddFrogCoreTests/PluginTests.swift                           (modify — month view passes coordinator validation)
- docs/query-plugins.md                                              (modify — Views section)
- docs/calendar-plugin.md                                            (modify — Scope list, "no custom UI" sentence)
- docs/api2/exchanges.ndjson                                         (modify — one activation result with a month view)
- Sources/OddFrog/ChatWindowController.swift                         (read — window construction, `activateWindow`, private nested `NSView` subclass pattern)
- Plugins/Chat/Tests/ChatHandlerTests.swift                          (read — handler test pattern: `params`, `operation`)
- Plugins/Chat/Tests/ChatProviderTests.swift                         (read — `capsAlwaysLeaveRoomForTheCreationRow`)
- Sources/OddFrogCore/PluginPackage.swift                            (read — `query(from:)` keyword stripping)
- Sources/OddFrogHostServicesAPI/CalendarSnapshot.swift              (read — must stay untouched)
- Sources/OddFrog/CalendarService.swift                              (read — must stay untouched)
- Sources/OddFrog/LauncherPanel.swift                                (read — must stay untouched)

## Context
- Swift 6 package, `swift-tools-version: 6.0`, macOS 14 deployment target, strict concurrency.
  Tests use the `Testing` framework (`@Test`, `#expect`, `#require`, `Issue.record`), not XCTest.
  No Xcode project. The workflow is `swift build`, `swift test`, and `make bundle` / `make run`.
  Today from the repo root, `swift build` has exactly two pre-existing warnings: `CGWindowListCreateImage`
  deprecated in `AppDelegate.swift`, and `nonisolated(unsafe)` unnecessary in `UnitRegistry.swift`.
  `swift test` passes 233 tests: core 112, bundled features 56, Chat 23, Notes 18, Reminders 16, Calendar 8.
- Targets (`Package.swift`):
  - `OddFrogPluginAPI` holds the wire types (Foundation only).
  - `OddFrogCore` holds host logic (Foundation + TOMLKit) and must not import AppKit.
  - `OddFrog` is the AppKit app.
  - `CalendarPluginCore` depends on `OddFrogPluginAPI` and `OddFrogHostServicesAPI`.
  - Test targets: `OddFrogCoreTests` (`Tests/OddFrogCoreTests`) and `CalendarPluginTests`
    (`Plugins/Calendar/Tests`). A new `.swift` file in either test directory is picked up without
    touching `Package.swift`.
- `PluginView` (`Sources/OddFrogPluginAPI/PluginView.swift`) is one flat struct:
  - `enum Kind: String, Codable, Sendable { case editor, chat }`.
  - Fields: `kind`, `id`, `title`, `text: String`, `placeholder`, and the optional `save`,
    `messages`, `prompt`, `send`.
  - Two inits: `init(kind: Kind = .editor, id:title:text:placeholder:save:)` for editor, and
    `init(id:title:messages:placeholder:prompt:send:)`, which sets `kind = .chat`.
  - Custom `init(from:)` decodes `text` with a default of `""` and every other non-core key with
    `decodeIfPresent`. Encoding is synthesized.
- `PluginCoordinator.validate(_ view: PluginView, package:)` (private) first requires non-empty
  `id` and `title`, then `switch view.kind` requires `save` for `.editor` and `send` + unique
  messages for `.chat`. `AppDelegate.runPluginAction` has the only other `switch view.kind`:
  - `.editor` goes to `documents.present(...)`.
  - `.chat` goes to `chats.present(...)`.
  - Windows are `private lazy var documents = DocumentWindowController()` and
    `private lazy var chats = ChatWindowController()`.
  - `reloadPlugins()` calls `documents.pluginsDidReload()` and `chats.pluginsDidReload()`.
- Launcher queries:
  - `PluginPackage.query(from:)` strips the exclusive keyword: `cal` gives `""`, and `cal month`
    gives `"month"`.
  - `PluginCoordinator.runQuery` builds `PluginQuery(query:fullQuery:maxResults: limit)` and
    throws `RPCError("protocol", "Query returned more than 50 rows.")` above 50 rows. It stores
    `items.prefix(limit)`.
  - `search` preserves provider row order for exclusive providers and prefixes to `maxResults`
    again.
  - The first row is the default selection, so Return runs it.
- `CalendarHandler.handle("query")` decodes `PluginQuery` from `params["input"]`, then calls
  `operation.service("calendar.read@1", params: .encode(CalendarProvider.range(for: query)))`, then
  `CalendarProvider.respond(to:snapshot:)`. There is no `activate` case today; unknown methods throw
  `RPCError("method", "Unsupported method: …")`.
- `CalendarProvider.range(for:)` and the top of `respond(to:snapshot:)` are the same parsing lines
  copied twice: calendar/zone, `day`, `words`, `first`, `explicitDays`, `hasRange`, `filter`,
  `offset`, `days`, `start`, `end`. `range(for:)` computes an unused `filter`.
- `respond` shape today:
  1. It returns one status row (id `"status"`) for `.notDetermined`/`.writeOnly`, `.denied` and
     `.restricted`.
  2. Otherwise it returns matching events, `prefix(max(1, min(request.maxResults, 50)))`.
  3. If none match, it returns one empty-agenda status row.

  A bare query is `words.isEmpty`.
- Handler test shape to mirror (`ChatHandlerTests`):
  - Call `handler.handle("activate", params: .object(["apiVersion": .number(2), "input": try .encode(activation)]), operation: …)`.
  - Build the operation as `ProviderOperation(id: "test", service: { capability, params in … }, emit: { _, _ in })`.
  - `PluginActivation(actionID:payload:item:argument:)` and `PluginItem(id:title:…)` are public.
    `RPCError` exposes `code`.
- `PluginTests.chatViewsAreValidatedAndDeltasAreRouted` shows how a coordinator view test is built:
  - A bundled `PluginPackage` with a `[[commands]]` entry whose primary is
    `{ kind = "callback", value = "open" }`.
  - `coordinator.builtins["fixture"] = { handler }`.
  - The private `DocumentHandler` actor's `respond(_:)` sets the activation reply.
  - `activate` completes with `.success`/`.failure`, and `waitUntil` polls.
- `publishedEnvelopeFixturesRoundTrip` decodes every line of `docs/api2/exchanges.ndjson` as a
  `PluginEnvelope`, then encodes it, decodes it again and compares `result` as `JSONValue`. A new
  line must be a valid envelope.
- Foundation facts, checked on this machine:
  - Stepping `Calendar(identifier: .hebrew)` (UTC) month by month from the month containing
    2023-09-16T00:00:00Z gives "Tishri 5784", "Heshvan 5784", "Kislev 5784", "Tevet 5784",
    "Shevat 5784", "Adar I 5784", "Adar II 5784", "Nisan 5784", "Iyar 5784", "Sivan 5784",
    "Tamuz 5784", "Av 5784", "Elul 5784", "Tishri 5785" (template `MMMMy`, locale `en_US`).
    Each step is `date(byAdding: .month, value: 1, to: monthStart)`. Tishri 5785 starts at
    2024-10-03T00:00:00Z, and Adar I 5784 has 30 days.
  - `Calendar.shortStandaloneWeekdaySymbols` is always Sunday-first, whatever `firstWeekday` is,
    so it must be rotated.
  - With a Gregorian calendar, `en_US` and UTC, template `MMMMy` formats 2026-09-14 as
    "September 2026", and `dateStyle = .full` gives "Monday, September 14, 2026".
- `Calendar.autoupdatingCurrent` follows setting changes, but values derived from it are not
  refreshed. Use a `Calendar.current` snapshot per grid build so the heading and cells agree.

## Plan
1. **`PluginView.swift`**: add `month` to `Kind`. Add
   `public init(month id: String, title: String)` that sets `kind = .month`, `id`, `title`,
   `text = ""` and leaves every optional nil. Do not change the editor or chat inits or the decoder.
2. **`PluginCoordinator.swift`**: in `validate(_ view:package:)`, add `case .month: break`. The
   shared id/title check already covers it, and a month view carries no actions to validate.
3. **`Sources/OddFrogCore/MonthGrid.swift`** (create): `public struct MonthGrid: Equatable, Sendable`.
   - Nested `public struct Day: Equatable, Sendable` with:
     - `date: Date`, the local start of day;
     - `number: String`, formatted with template `"d"`;
     - `inMonth: Bool`;
     - `isToday: Bool`;
     - `label: String`, formatted with `dateStyle = .full` and `timeStyle = .none`.
   - Stored properties: `public let month: Date` (start of the displayed month),
     `public let heading: String` (template `"MMMMy"`), `public let weekdays: [String]` and
     `public let days: [Day]`.
   - `public init(month anchor: Date, today: Date, calendar: Calendar)`:
     - `month = calendar.dateInterval(of: .month, for: anchor)!.start`.
     - `weekdays` is `calendar.shortStandaloneWeekdaySymbols` rotated left by
       `calendar.firstWeekday - 1`.
     - `leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7`,
       and `first = calendar.date(byAdding: .day, value: -leading, to: month)!`.
     - `days` has exactly 42 entries, `calendar.date(byAdding: .day, value: i, to: first)!` for
       `i in 0..<42`. This is civil-day stepping; never add 86 400 seconds.
     - `inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)`.
     - `isToday = calendar.isDate(date, inSameDayAs: today)`, which also marks today in an
       adjacent-month cell.
     - Every `DateFormatter` gets `calendar`, `calendar.timeZone` and `calendar.locale ?? .current`.
   - `public static func shifted(_ anchor: Date, months: Int, calendar: Calendar) -> Date`:
     `calendar.date(byAdding: .month, value: months, to: calendar.dateInterval(of: .month, for: anchor)!.start)!`.
     Anchoring on the month start is what keeps Jan 31 + 1 on February and steps correctly
     through leap months.
   - Never model the month as a Gregorian year/month pair and never do modulo-12 arithmetic. A
     month is a `Date` interpreted by the `Calendar`.
   - A 6-row grid always fits: the longest month (31 days) plus 6 leading days is 37 cells.
4. **`Sources/OddFrog/MonthWindowController.swift`** (create):
   `@MainActor final class MonthWindowController: NSWindowController, NSWindowDelegate`.
   - **Window:** `NSWindow(contentRect: 340×330, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)`.
     Set `isReleasedWhenClosed = false` and `setFrameAutosaveName("month")`, call `center()`,
     then `super.init(window:)`, set `window.delegate = self`, and build the content. It is not
     resizable and has no custom level.
   - **State:** `private var anchor = Date()` and `private var browsed = false`.
   - **Header row** (16 pt side insets, 12 pt top):
     - A heading `NSTextField(labelWithString:)` at 15 pt semibold on the leading side.
     - On the trailing side, three small (`controlSize = .small`) buttons:
       - Previous uses `NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous month")`.
       - A "Today" title button.
       - Next uses `chevron.right` with the description "Next month".
   - **Grid:** an `NSGridView` of 7 columns × 7 rows, all columns equal width, cells centered.
     - Row 0 holds weekday labels in 11 pt `secondaryLabelColor`.
     - Rows 1–6 hold 42 day cells. Each is a private nested `NSView` subclass (mirror the
       `Capsule` pattern in `ChatWindowController`: `wantsUpdateLayer`, colors set inside
       `effectiveAppearance.performAsCurrentDrawingAppearance`) holding a centered 13 pt label.
     - A today cell draws a 26 pt `controlAccentColor` circle behind the number, with
       `NSColor.white` text.
     - `inMonth` days use `labelColor`; other days use `tertiaryLabelColor`.
     - Each cell calls `setAccessibilityElement(true)`, `setAccessibilityRole(.staticText)` and
       `setAccessibilityLabel(day.label)`.
   - **Keyboard:** the grid sits inside a private nested `NSView` subclass with
     `acceptsFirstResponder = true`, and it is made first responder on present.
     - Its `keyDown` treats `charactersIgnoringModifiers?.lowercased() == "t"` with no Command,
       Control or Option modifier as Today. Everything else goes to `interpretKeyEvents([event])`.
     - `moveLeft(_:)` means previous, `moveRight(_:)` means next, and `cancelOperation(_:)` calls
       `window?.performClose(nil)`.
   - **Actions:** previous and next set `anchor = MonthGrid.shifted(anchor, months: ∓1, calendar: .current)`,
     `browsed = true`, then `rebuild()`. Today sets `anchor = Date()`, `browsed = false`, then
     `rebuild()`.
   - **`func present(_ view: PluginView)`:**
     1. Set `window?.title = view.title`, `anchor = Date()`, `browsed = false`.
     2. Call `rebuild()`.
     3. Call `NSApp.activate(ignoringOtherApps: true)`, `showWindow(nil)` and
        `window?.makeKeyAndOrderFront(nil)`.
     4. Make the key view first responder.

     Running the command again always resets to the current month.
   - **`private func rebuild()`:** build `MonthGrid(month: anchor, today: Date(), calendar: .current)`
     and push the heading, weekdays and 42 days into the existing views. Do not recreate the views.
   - **Refresh:** in init, observe with
     `NotificationCenter.default.addObserver(self, selector:name:object:)` (the selector form
     `AppDelegate` already uses):
     - `.NSCalendarDayChanged`
     - `.NSSystemTimeZoneDidChange`
     - `NSLocale.currentLocaleDidChangeNotification`

     Also refresh on `windowDidBecomeKey`. Refresh means `if !browsed { anchor = Date() }`, then
     `rebuild()`. A browsed month is kept, and today's mark still moves.
   - The controller holds no plugin state, and it does not need `pluginsDidReload`: after a reload
     the grid still works, because it never calls back into the plugin.
5. **`AppDelegate.swift`**: add `private lazy var months = MonthWindowController()` next to
   `chats`. In `runPluginAction`'s `switch view.kind`, add `case .month:` calling
   `months.present(view)`. Nothing else changes.
6. **`CalendarProvider.swift`**:
   - **Parsing dedupe:** extract the copied parsing into one private static helper that returns
     what both callers need: the calendar, `start`, `end`, `filter`, `first`, `days` and whether
     `words` is empty. `range(for:)` returns `CalendarRange(start:end:)` from it. `respond` uses
     it in place of its copy. No behaviour change; the existing range tests must pass untouched.
     Keep the existing `// Interval overlap…` comment and the `meetingURL` doc comment exactly as
     they are.
   - **`isMonthRequest`:** add `public static func isMonthRequest(_ request: PluginQuery) -> Bool`,
     true when `request.query` trimmed of whitespace and lowercased equals `"month"`. So `"month"`,
     `" Month "` and `"MONTH"` are true, while `"months"`, `"mo"`, `"month design"` and `""` are
     false.
   - **`monthItem`:** add `public static func monthItem() -> PluginItem` with
     `id: "show-month"`, `title: "Show month"`, `subtitle: "Open a month calendar · cal month"`,
     `kind: "Calendar"`, `symbol: "calendar"` and `primary: PluginAction(.callback, "month")`.
   - **`monthView`:** add `public static func monthView() -> PluginView`, returning
     `PluginView(month: "month", title: "Calendar")`.
   - **`respond` changes shape for bare queries only:**
     - Let `cap = max(1, min(request.maxResults, 50))`.
     - If the query is bare and `cap >= 2`, events are prefixed to `cap - 1`, and the month row is
       appended after whatever `respond` would otherwise return: the access status rows, the event
       rows, or the empty-agenda row.
     - At `cap == 1`, or for any non-bare query, the output is exactly what it is today. The
       agenda keeps its first row, so Return keeps its current target.
     - The result never exceeds 50 rows.
7. **`CalendarHandler.swift`**:
   - **`query`:** after decoding `PluginQuery`, if `CalendarProvider.isMonthRequest(query)`,
     return `.encode([CalendarProvider.monthItem()])` before any `operation.service` call. The
     direct route must work with calendar access denied or the service failing.
   - **`activate`:** add a case that decodes `PluginActivation` from `params["input"]`.
     - For `actionID == "month"`, return `.encode(PluginEffects(view: CalendarProvider.monthView()))`
       and call no service.
     - For any other action ID, throw `RPCError("action", "Unknown action: \(activation.actionID)")`
       (the Notes handler's wording).
8. **`Plugins/Calendar/Tests/CalendarProviderTests.swift`**:
   - Give the private `request` helper a `maxResults: Int = 50` parameter.
   - Two existing assertions break by design; update them and nothing else:
     - In `todayIncludesOngoingAllDayAndMultidayButNotEndedOrTomorrow`, the expected ids become
       `["multi", "all-day", "ongoing", "future", "show-month"]`, and the `openApplication` check
       moves from `.last` to `items[3]`.
     - In `blankTitlesBecomeUntitled`, the expected titles become
       `["Untitled event", "Flight", "Show month"]`.
   - Add these tests:
     - **Bare slot reservation:** with 3 future events, cap 50 gives the 3 ids + `"show-month"`;
       cap 2 gives `[first event, "show-month"]`; cap 1 gives `[first event]`. With 60 future
       events at cap 50, there are exactly 50 rows, the last being `"show-month"`.
     - **Status paths:** for `.notDetermined`, `.denied`, `.restricted` and the empty agenda, a
       bare query at cap 8 keeps the same first row as today and ends with `"show-month"`.
     - **Non-bare queries:** `"tomorrow"`, `"week"`, `"12d"` and `"design"` never contain
       `"show-month"`.
     - **Month row and view:** `monthItem().primary == PluginAction(.callback, "month")`.
       `monthView()` has kind `.month`, id `"month"` and title `"Calendar"`, and survives a
       `PluginProtocol` encoder/decoder round trip with that kind.
     - **`isMonthRequest`:** the true/false cases listed in step 6.
9. **`Plugins/Calendar/Tests/CalendarHandlerTests.swift`** (create): build the operation with a
   service closure that counts calls into a small actor and throws `RPCError("test", "unexpected service call")`.
   - `query` with `PluginQuery(query: "month", fullQuery: "cal month", maxResults: 8)` returns
     exactly `[monthItem()]`, with zero service calls.
   - `activate` with `actionID "month"` decodes to `PluginEffects` whose `view?.kind == .month`,
     with zero service calls.
   - `activate` with `actionID "nope"` throws an `RPCError` with code `"action"`.
10. **`Tests/OddFrogCoreTests/MonthGridTests.swift`** (create). Use explicit calendars: Gregorian,
    `locale = Locale(identifier: "en_US")`, UTC unless stated, and dates from `ISO8601DateFormatter`.
    - **September 2026, `firstWeekday = 1`:**
      - heading `"September 2026"`;
      - weekdays start `"Sun"`;
      - 42 days, the first dated 2026-08-30;
      - 30 `inMonth` days;
      - with today 2026-09-14T09:00:00Z, exactly one `isToday` day, labelled
        `"Monday, September 14, 2026"`.
    - **Same month, `firstWeekday = 2`:** weekdays start `"Mon"`, and the first day is 2026-08-31.
    - **February:** February 2026 with `firstWeekday = 1` has its first cell on 2026-02-01 (no
      leading days) and 28 `inMonth` days. February 2028 has 29 `inMonth` days.
    - **`shifted`:**
      - December 2026 +1 gives heading `"January 2027"`.
      - January 2027 −1 gives `"December 2026"`.
      - An anchor of 2027-01-31 +1 gives `"February 2027"`.
    - **Hebrew calendar** (`Calendar(identifier: .hebrew)`, UTC, `en_US`): starting from
      2023-09-16T00:00:00Z, 13 successive `shifted(…, months: 1, …)` steps give the 14 headings
      listed in Context. The last month is 2024-10-03T00:00:00Z, and the Adar I grid has 30
      `inMonth` days.
    - **DST:** in `America/New_York`, the March 2026 grid has every day at local hour 0, and
      `inMonth` day numbers are `"1"` through `"31"` in order.
11. **`Tests/OddFrogCoreTests/PluginTests.swift`**: add one `@MainActor` test modelled on
    `chatViewsAreValidatedAndDeltasAreRouted`, using the existing private `DocumentHandler`.
    - A reply with view `{kind: "month", id: "month", title: "Calendar"}` completes `.success`
      with `effects.view?.kind == .month`.
    - A reply with `{kind: "month", id: "", title: "Calendar"}` fails with `RPCError` code
      `"protocol"`.
12. **Docs:**
    - **`docs/query-plugins.md`, Views section:**
      - Change "`editor` or `chat`" to "`editor`, `chat`, or `month`".
      - Add a `### Month` subsection after Chat. A month view is `{kind: "month", id, title}`, and
        the host opens its single month window titled `title`, showing the current month in the
        user's calendar, first weekday and locale. Navigation is local to the host, and no
        callback runs while browsing. Presenting any month view brings the window forward and
        resets it to the current month. The view reads no data; a plugin that wants more must
        wait for a later view contract.
    - **`docs/api2/exchanges.ndjson`:** append
      `{"apiVersion":2,"id":"month","result":{"refreshCatalog":false,"refreshQuery":false,"view":{"kind":"month","id":"month","title":"Calendar"}}}`.
    - **`docs/calendar-plugin.md`:**
      - Add Scope bullets: "`cal month`: open a month calendar window (plain grid, no events,
        works without Calendar access)" and "Bare `cal` lists a Show month row after the agenda
        when at least two rows fit."
      - Replace the sentence "No custom plugin UI is introduced." with "The only plugin UI is the
        month window, which reads no events."

## Constraints
- Write no code comments of any kind in new or edited code: no `//`, no `///`, no doc comments,
  no `// MARK:`, no TODOs. The two existing comments in `CalendarProvider.swift` stay byte-for-byte.
- Every early return is braced with the `return` on its own line, matching the newer code in
  `ChatWindowController.swift`: `guard let x else {\n    return\n}`. Do not add single-line
  `guard … else { return }` forms in new code.
- One type per file for new top-level types. Private nested helper views inside the window
  controller are fine, as `ChatWindowController` does.
- `OddFrogCore` must not import AppKit, and `MonthGrid` must stay pure: no `Date()`, and no
  `Calendar.current`/`autoupdatingCurrent`. The caller passes in `today` and `calendar`.
- Do not change `CalendarRange`, `CalendarService`, the `calendar.read@1`/`calendar.access@1`
  registrations, the `PluginView` editor/chat inits or decoder, or `LauncherPanel`.
- No new dependencies, no gradients, no custom shadows, and no emoji in UI text.
- Surgical edits. Do not reformat untouched lines.

## Acceptance
- `swift build` from the repo root completes with only the two pre-existing warnings listed in Context.
- `swift test` from the repo root passes, with more tests than the 233 baseline and no existing
  test removed.
- Manual check, after `make run`:
  1. Type `cal`: the agenda (or access/empty status) row is first, and "Show month" is last.
  2. Select "Show month" and press Return: a window titled "Calendar" opens on the current month,
     with today marked and weekdays starting at the system's first weekday.
  3. Press → three times, then ←, and check the heading follows. Press T: the window returns to
     the current month. Press Esc: the window closes.
  4. Type `cal month` and press Return: the window opens on the current month even after
     browsing away earlier. With Calendar access turned off in System Settings, `cal month` still
     shows its row and opens the window.
  5. Change System Settings › General › Language & Region › First day of week while the window
     is open, then click back into the window: the weekday headers follow.

## Out of scope
- Events, event dots, selecting a day, copying a date, week numbers, and any day-detail list.
- Widening the calendar read range or any other host-service change.
- Prefix suggestions (`cal mo` offering Show month). `cal mo` keeps searching event titles.
- Restructuring `PluginView` into per-kind payloads, or fixing the editor init accepting
  `kind: .chat`. Both are known follow-ups, not part of this change.
- Reload handling for the month window: it has no plugin state to invalidate.

## Open questions
none
