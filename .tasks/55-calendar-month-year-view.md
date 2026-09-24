# Task: Calendar window with its own month and year grids, a Month/Year switch, and a readable default size

## Goal
The month window stops using the stock `NSDatePicker` and draws its own grids in SwiftUI. It shows
either one month, as a large grid that fills the window, or a whole year, as scrollable mini-month
tiles. A Month | Year control in the window toolbar switches between the two, and so do new View
menu items ⌘1 and ⌘2. Clicking a tile opens that month. The window is resizable. It opens at a
readable default size, and it no longer reopens at the tiny frame saved under the old autosave
name. The grid model (`MonthGrid`, restored from git, a new `YearGrid`, and a new
`CalendarBrowser` state struct) lives in `OddFrogCore` and has tests.

## Files
- Sources/OddFrogCore/MonthGrid.swift                                  (create — restored from `a85d07f`, then extended)
- Sources/OddFrogCore/YearGrid.swift                                   (create)
- Sources/OddFrogCore/CalendarBrowser.swift                            (create)
- Tests/OddFrogCoreTests/MonthGridTests.swift                          (create — restored from `a85d07f`, then extended)
- Tests/OddFrogCoreTests/YearGridTests.swift                           (create)
- Tests/OddFrogCoreTests/CalendarBrowserTests.swift                    (create)
- Sources/OddFrog/CalendarWindowModel.swift                            (create)
- Sources/OddFrog/CalendarView.swift                                   (create)
- Sources/OddFrog/MonthView.swift                                      (create)
- Sources/OddFrog/YearView.swift                                       (create)
- Sources/OddFrog/MiniMonthView.swift                                  (create)
- Sources/OddFrog/MonthWindowController.swift                          (modify — rewrite)
- Sources/OddFrog/AppDelegate.swift                                    (modify — the View menu in `installMainMenu`)
- docs/query-plugins.md                                                (modify — the Month section)
- docs/calendar-plugin.md                                              (modify — the `cal month` scope line)
- Sources/OddFrog/ChatWindowController.swift                           (read — `NSToolbarDelegate` pattern: static identifiers, `target = self`, SF Symbol images)
- Sources/OddFrog/LinkManagerController.swift                          (read — `NSHostingController` with `sizingOptions = []` as `contentViewController`, then `setContentSize`)
- Sources/OddFrog/AppearancePaneModel.swift                            (read — `@Observable @MainActor final class` model pattern)
- Sources/OddFrog/LauncherPanel.swift, Sources/OddFrog/LauncherViewController.swift (read — ⌘1–⌘9 in the launcher)
- Sources/OddFrogPluginAPI/PluginView.swift                            (read — `PluginView(month:title:)`; unchanged)

## Context
- Swift tools 6.2, and the package targets macOS 26 (`Package.swift`). The `OddFrog` app target
  depends on `OddFrogCore`. The `OddFrogCoreTests` target picks up files by directory and uses Swift
  Testing (`import Testing`, `@Test`, `#expect`), so `Package.swift` needs no change.
- Baseline on this machine: `swift build` passes with exactly one warning, `'nonisolated(unsafe)'
  is unnecessary` in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`, and `swift test`
  passes.
- **Today's window** (`Sources/OddFrog/MonthWindowController.swift`, spec 52):
  - A stock `NSDatePicker` (`.clockAndCalendar`, `.yearMonthDay`) is pinned to the content
    view's `layoutMarginsGuide`.
  - The window is `[.titled, .closable, .miniaturizable]`, not resizable, with
    `contentRect: .zero`. `buildContent()` sizes it with `setContentSize(content.fittingSize)`,
    which comes to 179×178 pt of content.
  - The autosave name is `"month"`.
  - `@objc` actions `showPreviousMonth(_:)`, `showNextMonth(_:)` and `goToToday(_:)` are
    reached from the View menu with a nil target.
  - Three observers (`.NSCalendarDayChanged`, `.NSSystemTimeZoneDidChange`,
    `NSLocale.currentLocaleDidChangeNotification`) call `refresh()` on the main actor.
  - `present(_ view: PluginView)` sets the title, goes to today, activates, and makes the window
    key.
  - `AppDelegate` owns `private lazy var months = MonthWindowController()` and calls
    `months.present(view)` for `.month` views. That call stays.
- **Why the stock picker has to go:**
  - `NSDatePicker` has no year mode.
  - It has no public API for the month it displays.
  - Its intrinsic size is fixed at 139×148 pt, so it can't become more readable.
- **The saved frame on this machine:** `defaults read com.paveltrofimov.odd-frog "NSWindow Frame
  month"` prints `666 554 179 210 0 0 1512 949`.
- **Measured in a scratch AppKit script on this machine:**
  - `setFrameAutosaveName(_:)` restores a saved frame immediately when one exists, and grows it
    to `contentMinSize`, keeping the top edge. Under the name `"month"`, the old frame would come
    back at the minimum size. A new name ignores it and opens at the default size.
  - `NSToolbarItemGroup(itemIdentifier:titles:selectionMode:labels:target:action:)` with
    `.selectOne` builds a two-segment group whose `selectedIndex` can be both read and set.
  - A new `NSHostingController`'s `sizingOptions` is not empty by default. Unless it is set to
    `[]`, the hosting controller constrains the window to the SwiftUI content's min, ideal and
    max sizes.
  - Natural sizes at the macOS text styles (largeTitle 26 pt, title 22, title2 17, headline 13,
    body 13, caption 10), using SwiftUI `Grid` default spacing and `.padding()`:
    - one mini-month tile (headline name, caption weekday initials, 6 rows of body digits) is
      167×156;
    - a 4×3 year of tiles under a largeTitle heading is 756×596;
    - a month grid (largeTitle heading, headline weekdays, 6 rows of title2 digits) is 283×258.
- **Calendar facts measured with Foundation on this machine:**
  - `Calendar.autoupdatingCurrent == Calendar.current` is **false**, and `Calendar.current ==
    Calendar.current` is true. Any "has the calendar changed" comparison must snapshot
    `Calendar.current`, never `.autoupdatingCurrent`.
  - Two calendars compare unequal when only `firstWeekday`, only `locale` or only `timeZone`
    differs.
  - In the Hebrew calendar, enumerating from `dateInterval(of: .year, for:)` by `.month` while
    `< end` gives 13 months for 5784 (Tishri … Adar I, Adar II … Elul) and 12 for 5785. The
    current Hebrew year, 5787, has 13. The template `"y"` formats as `5784`.
  - `veryShortStandaloneWeekdaySymbols` in `en_US` is `S M T W T F S`.
  - `Calendar.date(byAdding: .month, value: 1, to:)` from 31 January gives 28 February.
- **`MonthGrid` at `a85d07f`:**
  - `git show a85d07f:Sources/OddFrogCore/MonthGrid.swift` and
    `git show a85d07f:Tests/OddFrogCoreTests/MonthGridTests.swift` hold the model and its five
    tests. Spec 52 deleted both unchanged.
  - The model has `month` (month start), `heading` (template `"MMMMy"`), `weekdays` (short
    standalone symbols rotated to `firstWeekday`) and 42 `days`. Each day has `date`, `number`,
    `inMonth`, `isToday` and `label` (full date style).
  - It also has `static func shifted(_:months:calendar:)` and
    `private static func formatter(_:template:)`. All of it is driven by an injected `Calendar`.
- **Key equivalents:**
  - ⌥⌘← / ⌥⌘→ were chosen in spec 52 because a disabled menu item still consumes its key
    equivalent. Those keys have no text binding. ⌘← / ⌘→ do (line start and line end).
  - ⌘1–⌘9 belong to the launcher. `LauncherPanel.performKeyEquivalent(with:)` hands ⌘-keys to
    `LauncherViewController.handleKeyEquivalent`, which returns `true` for every ⌘digit before
    the main menu sees it (measured in spec 45). So while the launcher is key it always wins. In
    any other window, a disabled Month/Year item swallows ⌘1/⌘2, which have no text binding.
- The app runs as an accessory (`.accessory`, `LSUIElement`), so the main menu is never
  visible. The toolbar control is the only visible way to switch modes, and the menu items are
  keyboard accelerators.
- `NSWindowController` is its window's next responder, and `MonthWindowController` is also the
  window's delegate. So nil-target menu actions reach it while the month window is key, even with
  no focusable view inside.
- **Decisions reached while designing this change:**
  - **Year layout.** One window size serves both modes. The year view scrolls vertically, and
    its column count comes from `ViewThatFits` over 4, 3, 2 and 1 columns of tiles at their
    natural size. So a 13-month year, or a narrow window, adds rows instead of shrinking the
    text.
    - Rejected: remembering a separate size per mode, where the window resizes itself on every
      switch.
    - Rejected: a custom `Layout`, or a `LazyVGrid` with a literal minimum tile width.
  - **Saved frame.** The autosave name changes from `"month"` to `"calendar"`. The old key is
    left orphaned: it's a one-time loss of the old position in exchange for the new default size.
  - **Browsed period and refresh rules:**
    - Previous, Next and clicking a tile mark the view as browsed.
    - Go to Today and presenting (running `cal month` again) clear it.
    - Switching mode leaves it as it is.
    - On any refresh, `today` updates, and the anchor moves to today only while the view is not
      browsed. An untouched month view therefore moves to January on 1 January, and an untouched
      year view moves to the new year.
    - A change of time zone or calendar identifier resets to today in the current mode.
    - A change of locale or first weekday redraws the browsed period in place.
  - **No day selection, no bare-arrow keys, and no focusable SwiftUI view.** Every command goes
    through the controller: menu items and toolbar items.
  - **Today's marker** is the day number in the accent colour, bold. It follows the stock
    date-picker convention for an unselected today.
    - Rejected: a filled circle. It needs a literal diameter, or a padding that doesn't fit
      small cells.
  - `ContentFont` (the Appearance pane's font and size) stays out of the calendar, as spec 53
    scoped it. Readability comes from larger text styles and a larger default window.

## Plan
1. **Restore `MonthGrid`.** Recreate `Sources/OddFrogCore/MonthGrid.swift` with the exact content
   of `git show a85d07f:Sources/OddFrogCore/MonthGrid.swift`, then extend it:
   - Add `public let name: String`: the month name alone, from `formatter(calendar, template:
     "MMMM")`.
   - Add `public let narrowWeekdays: [String]`: `calendar.veryShortStandaloneWeekdaySymbols`,
     rotated to `firstWeekday` exactly as `weekdays` is.
   - Change `private static func formatter` to `static func formatter`, internal, so that
     `YearGrid` can reuse it.
   - Keep `shifted(_:months:calendar:)`. `CalendarBrowser` doesn't need it, but its tests still
     pin the month arithmetic.
2. **Restore the `MonthGrid` tests.** Recreate `Tests/OddFrogCoreTests/MonthGridTests.swift` from
   `git show a85d07f:Tests/OddFrogCoreTests/MonthGridTests.swift`, then extend it:
   - in `septemberStartsOnTheUsersFirstWeekdayAndMarksToday`, expect `grid.name == "September"`
     and `grid.narrowWeekdays == ["S", "M", "T", "W", "T", "F", "S"]`;
   - in `hebrewNavigationStepsThroughLeapMonths`, expect the Adar I grid's `name == "Adar I"`.
3. **Create `YearGrid`.** `Sources/OddFrogCore/YearGrid.swift` holds `public struct YearGrid:
   Equatable, Sendable` with:
   - `public let year: Date`: the year start;
   - `public let heading: String`: `MonthGrid.formatter(calendar, template: "y")`;
   - `public let months: [MonthGrid]`.

   `public init(year anchor: Date, today: Date, calendar: Calendar)`:
   - Take `calendar.dateInterval(of: .year, for: anchor)` (force-unwrapped, like `MonthGrid`).
   - Walk month starts from `interval.start` with `calendar.date(byAdding: .month, value: 1,
     to:)` while the date is `< interval.end`.
   - Build `MonthGrid(month:today:calendar:)` for each month.
   - Stop if a step fails to advance (returns nil or a date not later than the current one).
   - Never assume 12 months.
4. **Create `YearGrid` tests.** `Tests/OddFrogCoreTests/YearGridTests.swift`, with the calendar
   helper built the same way as in `MonthGridTests`:
   - Gregorian 2026 (UTC, en_US): the heading is `"2026"`, there are 12 months, the first
     month's `heading` is `"January 2026"`, and exactly one in-month day across all months has
     `isToday` for a `today` of 2026-09-14.
   - Hebrew, anchored on 2024-01-15: the heading is `"5784"`, there are 13 months, and the
     `name`s include `"Adar I"` and `"Adar II"` in that order.
   - Hebrew, anchored on 2025-01-15: 12 months.
5. **Create `CalendarBrowser`.** `Sources/OddFrogCore/CalendarBrowser.swift` holds `public struct
   CalendarBrowser: Equatable, Sendable`.
   - Nested `public enum Mode: Equatable, Sendable { case month, year }`.
   - `public private(set) var` properties: `mode`, `anchor: Date`, `today: Date`,
     `calendar: Calendar` and `browsed: Bool`.
   - `public init(now: Date, calendar: Calendar)` sets mode `.month`, anchor and today to `now`,
     and browsed to false.
   - `public var monthGrid: MonthGrid` is `MonthGrid(month: anchor, today: today, calendar:
     calendar)`. `public var yearGrid: YearGrid` works the same way.
   - `public mutating func present(now: Date, calendar: Calendar)` sets the mode to `.month`,
     then calls `goToToday(now:calendar:)`.
   - `public mutating func goToToday(now: Date, calendar: Calendar)` sets `calendar`, `today =
     now`, `anchor = now` and `browsed = false`, and keeps the mode.
   - `public mutating func show(_ mode: Mode)` sets the mode only.
   - `public mutating func step(by count: Int)`:
     - The component is `.month` in month mode and `.year` in year mode.
     - Take the start of `calendar.dateInterval(of: component, for: anchor)`, then
       `calendar.date(byAdding: component, value: count, to: start)`.
     - Return if either is nil. Otherwise set `anchor` to the result and `browsed = true`.
     - Stepping from the period start means a 31st never skips a short month.
   - `public mutating func open(month: Date)` sets the mode to `.month`, `anchor = month` and
     `browsed = true`.
   - `public mutating func refresh(now: Date, calendar: Calendar)`:
     - If `calendar.identifier` or `calendar.timeZone` differs from the stored calendar's, set
       `browsed = false`.
     - Then store `calendar`, set `today = now`, and set `anchor = now` when `!browsed`.
6. **Create `CalendarBrowser` tests.** `Tests/OddFrogCoreTests/CalendarBrowserTests.swift`, using
   UTC en_US Gregorian calendars unless stated otherwise:
   - **An untouched view follows the day.** From 2026-12-31T23:00Z, `refresh(now:
     2027-01-01T00:30Z)` gives `monthGrid.heading == "January 2027"`. The same in year mode
     (after `show(.year)`) gives `yearGrid.heading == "2027"`.
   - **A browsed view stays.** `step(by: 1)` from September 2026, then `refresh` on the next day,
     still gives `"October 2026"`, with `today` updated.
   - **Year mode steps by years.** `show(.year)`, then `step(by: -1)`, gives
     `yearGrid.heading == "2025"`. In Hebrew, starting in 5784 and stepping +1 gives `"5785"`
     with 12 months.
   - **A 31st doesn't skip a month.** Anchored on 2027-01-31, `step(by: 1)` gives
     `"February 2027"`.
   - **Zone and identifier changes reset.** After browsing, `refresh` with a calendar whose
     `timeZone` differs resets: browsed is false and the anchor is `now`. The same happens with a
     Hebrew calendar in place of the Gregorian one.
   - **Presentation changes keep the period.** After browsing, `refresh` with a calendar whose
     `firstWeekday` differs keeps the browsed month, and `monthGrid.weekdays.first` changes.
   - **Present and Today.** `present` from year mode gives month mode and browsed false.
     `goToToday` from year mode keeps year mode.
   - **Opening a tile.** `open(month:)` gives month mode, the given month, and browsed true.
     `show(.year)` leaves `browsed` and `anchor` unchanged.
7. **Create the window model.** `Sources/OddFrog/CalendarWindowModel.swift` holds `@Observable
   @MainActor final class CalendarWindowModel` with one stored property, `var browser:
   CalendarBrowser`, and `init(browser:)`. It follows `AppearancePaneModel`'s pattern.
8. **Create `CalendarView`.** `Sources/OddFrog/CalendarView.swift` is `struct CalendarView: View`,
   taking `let model: CalendarWindowModel` and `let open: (Date) -> Void`.
   - A leading-aligned `VStack` with `.padding()`, and `.frame(maxWidth: .infinity, maxHeight:
     .infinity, alignment: .topLeading)`.
   - It switches on `model.browser.mode`:
     - Month mode: take `monthGrid` once, show `Text(grid.heading)` in `.largeTitle` with
       `.accessibilityAddTraits(.isHeader)`, then `MonthView(grid:)`.
     - Year mode: the same with `yearGrid`, then `YearView(grid:open:)`.
9. **Create `MonthView`.** `Sources/OddFrog/MonthView.swift` is `struct MonthView: View`, taking
   `let grid: MonthGrid`.
   - It is a SwiftUI `Grid`. The first `GridRow` holds `grid.weekdays` in `.headline`,
     `.secondary`.
   - Then there's one `GridRow` per week: chunk `grid.days` by `grid.weekdays.count`, so the grid
     has no literal row or column count.
   - Each day is `Text(day.number)` in `.title` with `.monospacedDigit()` and `.frame(maxWidth:
     .infinity, maxHeight: .infinity)`, so the cells fill the window.
   - Foreground:
     - `.tint` with `.bold()` when `day.isToday && day.inMonth`;
     - `.primary` when `day.inMonth`;
     - `.tertiary` otherwise.

     Wrap the styles in `AnyShapeStyle` where the types differ.
   - `.accessibilityLabel` is `"Today, " + day.label` for today and `day.label` otherwise.
10. **Create `MiniMonthView`.** `Sources/OddFrog/MiniMonthView.swift` is `struct MiniMonthView:
    View`, taking `let grid: MonthGrid` and `let open: (Date) -> Void`.
    - A `Button` whose action is `open(grid.month)`. Its label is a leading-aligned `VStack`:
      - `Text(grid.name)` in `.headline`;
      - a `Grid` whose first row is `grid.narrowWeekdays` in `.caption`, `.secondary`;
      - one row per week (chunked as in `MonthView`) of `Text(day.number)` in `.body` with
        `.monospacedDigit()`.
    - Days outside the month keep their cell but are `.hidden()`, so every tile has the same
      rows.
    - Today in-month uses `.tint` and `.bold()`, as in `MonthView`.
    - Apply `.contentShape(.rect)` to the label so the gaps are clickable, then
      `.buttonStyle(.plain)`, `.accessibilityLabel(grid.heading)` and
      `.accessibilityHint("Shows this month")`.
11. **Create `YearView`.** `Sources/OddFrog/YearView.swift` is `struct YearView: View`, taking
    `let grid: YearGrid` and `let open: (Date) -> Void`.
    - The body is `ScrollView(.vertical)` containing `ViewThatFits(in: .horizontal)`, over a
      private helper `columns(_ count: Int)` called with 4, 3, 2 and 1 in that order.
    - `columns(_:)` returns a `Grid(alignment: .topLeading)`: `grid.months` chunked by `count`,
      one `GridRow` of `MiniMonthView(grid:open:)` per chunk, with `ForEach` identified by each
      grid's `month`.
    - Leave tile sizes natural, with no frames.
12. **Rewrite `MonthWindowController.swift`.** Keep the class name, the file, the three observers
    and `present(_:)`'s signature. It imports `AppKit`, `OddFrogCore`, `OddFrogPluginAPI` and
    `SwiftUI`, and conforms to `NSWindowDelegate` and `NSToolbarDelegate`.
    - **Constants:**
      - `private static let contentSize = NSSize(width: 780, height: 620)`. This fits the
        measured 756×596 4×3 year without scrolling.
      - `private static let minimumSize = NSSize(width: 400, height: 360)`. This fits the
        measured 283×258 month and a 2-column year.
      - Toolbar identifiers `mode`, `previous`, `today` and `next`, as static
        `NSToolbarItem.Identifier`s like `ChatWindowController.stopItem`.
    - **State:**
      - `private let model = CalendarWindowModel(browser: CalendarBrowser(now: Date(), calendar:
        .current))`;
      - `private var modeGroup: NSToolbarItemGroup?`;
      - `observers`.
    - **`init()`, in this order:**
      1. Create the window with `contentRect: NSRect(origin: .zero, size: Self.contentSize)` and
         style `[.titled, .closable, .miniaturizable, .resizable]`.
      2. Set `contentMinSize = Self.minimumSize` and `isReleasedWhenClosed = false`.
      3. Call `super.init(window:)`, then set `window.delegate = self`.
      4. Install `NSToolbar(identifier: "calendar")` with `self` as its delegate.
      5. Set `window.contentViewController` to an `NSHostingController(rootView:
         CalendarView(model: model, open: { [weak self] month in self?.update { $0.open(month:
         month) } }))` whose `sizingOptions = []`.
      6. Call `window.setContentSize(Self.contentSize)`, then `window.center()`.
      7. **Last**, call `window.setFrameAutosaveName("calendar")`, so a frame saved under the new
         name wins over the default.
      8. Add the three observers, unchanged, each calling `refresh()`.
    - **`private func update(_ change: (inout CalendarBrowser) -> Void)`** applies `change` to
      `model.browser`, then sets `modeGroup?.selectedIndex` to 0 for `.month` and 1 for `.year`.
      Every state change goes through it.
    - **`@objc` actions**, internal, not private, so `AppDelegate` can name them in `#selector`:
      - `showMonthView(_:)` calls `update { $0.show(.month) }`;
      - `showYearView(_:)` calls `update { $0.show(.year) }`;
      - `showPrevious(_:)` calls `update { $0.step(by: -1) }`;
      - `showNext(_:)` calls `update { $0.step(by: 1) }`;
      - `goToToday(_:)` calls `update { $0.goToToday(now: Date(), calendar: .current) }`.

      Delete `showPreviousMonth(_:)` and `showNextMonth(_:)`.
    - **`@objc private func modeChanged(_ sender: Any?)`** reads `modeGroup?.selectedIndex`,
      not `sender`, and calls `show(.month)` for 0 and `show(.year)` for 1 through `update`.
    - **`present(_:)`:**
      - Set the title from the view.
      - Call `update { $0.present(now: Date(), calendar: .current) }`.
      - Then run `NSApp.activate(ignoringOtherApps: true)`, `showWindow(nil)` and
        `window?.makeKeyAndOrderFront(nil)`, unchanged.
      - Make no `makeFirstResponder` call.
    - **Refresh:** `private func refresh()` calls `update { $0.refresh(now: Date(), calendar:
      .current) }`. `windowDidBecomeKey(_:)` calls `refresh()` unconditionally, which is safe
      now because `refresh` keeps a browsed period.
      - Always pass `Calendar.current` (spelled `.current`), never `.autoupdatingCurrent`: they
        never compare equal (Context).
    - **Toolbar delegate:**
      - Default and allowed identifiers are `[mode, .flexibleSpace, previous, today, next]`.
      - `mode` is `NSToolbarItemGroup(itemIdentifier:titles: ["Month", "Year"], selectionMode:
        .selectOne, labels: ["Month", "Year"], target: self, action:
        #selector(modeChanged(_:)))`. Set its `selectedIndex` from the current mode, store it in
        `modeGroup`, and return it.
      - `previous` and `next` are `NSToolbarItem`s with label and tool tip "Previous"/"Next",
        images `chevron.left` and `chevron.right` (`accessibilityDescription` "Previous" and
        "Next"), `target = self`, and actions `showPrevious(_:)` and `showNext(_:)`.
      - `today` is an `NSToolbarItem` with `title` and `label` "Today", `target = self` and
        action `goToToday(_:)`.
    - **Delete** the picker, `show(_:)`, `move(by:)`, `today` and `buildContent()`.
13. **Update the View menu.** In `Sources/OddFrog/AppDelegate.swift`, `installMainMenu()`, replace
    the View menu's items with, all with a nil target:
    - "Month" ⌘1 → `#selector(MonthWindowController.showMonthView(_:))`;
    - "Year" ⌘2 → `showYearView(_:)`;
    - a separator;
    - "Previous" ⌥⌘← → `showPrevious(_:)`, with the same key and modifier construction as
      today's Previous Month;
    - "Next" ⌥⌘→ → `showNext(_:)`;
    - a separator;
    - "Go to Today" ⌘T → `goToToday(_:)`.

    Change nothing else in the menu. The generic titles avoid retitling per mode.
14. **Update `docs/query-plugins.md`.** Replace the Month section's paragraph with:

    > A month view is `{kind: "month", id, title}`. The host opens its single calendar window
    > titled `title`, showing the current month in the user's calendar, first weekday, and
    > locale, with today marked. A Month/Year control in the window's toolbar switches to the
    > whole year as month tiles, and clicking a tile opens that month. Navigation is local to the
    > host, and no callback runs while browsing. The toolbar's previous and next buttons, and
    > Option+Cmd+Left Arrow and Option+Cmd+Right Arrow, step one month or one year back and
    > forward; Cmd+1 and Cmd+2 choose Month or Year, and Cmd+T returns to today. Presenting any
    > month view brings the window forward and resets it to the current month. The view carries
    > no data; a plugin that wants more must wait for a later view contract.
15. **Update `docs/calendar-plugin.md`.** In the `cal month` line, replace "(the system date
    picker, no events, works without Calendar access)" with "(month and year grids, no events,
    works without Calendar access)".

## Constraints
- **No comments.** Write no code comments of any kind: no `//` or `///` lines, no doc comments,
  no MARK banners, no TODOs. The restored `MonthGrid.swift` and `MonthGridTests.swift` have none.
- **Style:**
  - Match the surrounding Swift: dense single-line `guard … else { return }` bodies where
    neighbouring code uses them.
  - One type per file for new types. Private helper functions inside a view are fine.
  - Function components only in SwiftUI.
  - No new package dependencies.
- **Deployment target.** It is macOS 26: call APIs directly, add no `#available`/`@available`
  checks, and use nothing that needs macOS 27.
- **Styling bounds for the custom renderer:**
  - Text styles only: `.largeTitle`, `.title`, `.headline`, `.body`, `.caption`. No
    `.system(size:)` or other literal font size.
  - Semantic styles only: `.primary`, `.secondary`, `.tertiary`, `.tint`. No literal or hex
    colours, `Color(red:…)` or `NSColor(…)` constructors.
  - No shapes drawn for decoration, no corner radii, no `draw(_:)` overrides or layer styling,
    no forced `controlSize`, no bezel or border overrides, and no hover effects.
  - Spacing comes from `.padding()` with no argument and from `Grid`/`VStack` defaults. No
    literal padding or spacing.
  - The only literals are `contentSize` (780×620) and `minimumSize` (400×360) in
    `MonthWindowController`, and the column counts 4, 3, 2 and 1 in `YearView`. The ±1 steps
    are data.
- **Unchanged:** the `PluginView` month contract, the Calendar plugin, and
  `months.present(view)` in `AppDelegate.runPluginAction`. In `installMainMenu`, change only the
  View menu.
- **Surgical changes only.** Do not touch anything outside Files without saying why.
- **Scope of the work.** The work is writing the code in Plan and running the commands in
  Acceptance. Nothing else: do not start the app or a dev server, do not open a browser, do not
  take screenshots, do not write or run tests or scripts that are not listed in Plan, do not mock
  or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes
- `grep -n "NSDatePicker\|picker\|autoupdatingCurrent\|showPreviousMonth\|showNextMonth\|makeFirstResponder" Sources/OddFrog/MonthWindowController.swift` prints nothing
- `grep -n 'setFrameAutosaveName("calendar")' Sources/OddFrog/MonthWindowController.swift` prints one line
- `grep -n "showMonthView\|showYearView\|showPrevious\|showNext\|goToToday" Sources/OddFrog/AppDelegate.swift` prints five lines
- `grep -nE "cornerRadius|system\(size|Color\(red|NSColor\(|\.padding\([0-9.]|spacing: [0-9]|controlSize|onKeyPress|focusable" Sources/OddFrog/CalendarView.swift Sources/OddFrog/MonthView.swift Sources/OddFrog/YearView.swift Sources/OddFrog/MiniMonthView.swift` prints nothing
- `grep -nE "^\s*//" Sources/OddFrogCore/MonthGrid.swift Sources/OddFrogCore/YearGrid.swift Sources/OddFrogCore/CalendarBrowser.swift Sources/OddFrog/CalendarWindowModel.swift Sources/OddFrog/CalendarView.swift Sources/OddFrog/MonthView.swift Sources/OddFrog/YearView.swift Sources/OddFrog/MiniMonthView.swift Sources/OddFrog/MonthWindowController.swift Tests/OddFrogCoreTests/MonthGridTests.swift Tests/OddFrogCoreTests/YearGridTests.swift Tests/OddFrogCoreTests/CalendarBrowserTests.swift` prints nothing

## Manual review
1. **Old frame ignored, readable month.** Before launching, `defaults read com.paveltrofimov.odd-frog
   "NSWindow Frame month"` still shows the old 179-wide frame. Run `make run`, type `cal month`
   and press Return.
   - The window opens at the new default size, about 780×620 of content, centred.
   - It shows a large month heading, a weekday row starting on your first weekday, and large
     day numbers that fill the window.
   - Today is bold in the accent colour, and days from adjacent months are dimmed.
2. **Resizing and reopening.** Resize the window: the cells grow and shrink with it, and it won't
   go below the minimum size. Close it with ⌘W and run `cal month` again. It reopens at the size
   and position you left, on the current month.
3. **Year mode and tiles.** Click Year in the toolbar. The current year shows 12 tiles in 4
   columns × 3 rows, with no scrolling at the default size. Today is marked in the current
   month's tile, and no month name is clipped. Click a tile: that month opens in month mode, and
   the toolbar control shows Month.
4. **Narrow window.** Shrink the window to its minimum in year mode. The tiles re-flow to fewer
   columns and the view scrolls, the text keeps its size, and every tile can be scrolled to and
   clicked.
5. **Navigation keys.**
   - In month mode, ⌥⌘← and ⌥⌘→ and the toolbar chevrons step one month. In year mode they step
     one year.
   - ⌘1 and ⌘2 switch modes, and the toolbar control follows.
   - ⌘T returns to today and keeps the mode.
   - With today on screen, page ahead, switch to another app, and come back: the paged period is
     still showing.
6. **Hebrew year.** Switch System Settings › General › Language & Region › Calendar to Hebrew and
   click back into the window. It resets to today. The year view shows 5787 with 13 tiles
   including Adar I and Adar II, and the 13th starts a new row reachable by scrolling. Switch the
   calendar back.
7. **First weekday.** Browse to another month, change "First day of week" in Language & Region,
   and click back into the window. The weekday row changes and the browsed month stays.
8. **Launcher keys unaffected.** Open the launcher, type a query with several results, and press
   ⌘1: the first result runs and the calendar's mode does not change. In a note, ⌘← and ⌘→
   still move to the line start and end, and ⌘1 does nothing.
9. **VoiceOver.** Today's cell reads "Today, " followed by the full date. A year tile reads as a
   button named after its month and year.
10. **Appearance.** Switch Settings › Appearance between Light and Dark: every text colour stays
    legible in both.

## Out of scope
- Events, event dots, Calendar access, and any change to the Calendar plugin or `cal` commands
  (including a `cal year` command).
- The `PluginView` contract. It stays `{kind: "month", id, title}`.
- Applying `ContentFont` to the calendar, week numbers, day selection, and keyboard navigation
  inside the grid.
- Renaming `MonthWindowController` or the `months` property.
- Clearing the orphaned `"NSWindow Frame month"` default.
- Any other main-menu change.

## Open questions
none
