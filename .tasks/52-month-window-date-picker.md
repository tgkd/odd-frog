# Task: Month window as a stock graphical NSDatePicker, with month navigation in a View menu

## Goal
The month window shows a stock graphical `NSDatePicker` (`.clockAndCalendar`, `.yearMonthDay`). It
follows the user's calendar, locale and time zone, and opens on today. The window is sized to fit
the picker inside the system margins. A new View menu holds Previous Month ⌥⌘←, Next Month ⌥⌘→
and Go to Today ⌘T, and the menu reaches the month window through the responder chain. The
hand-built grid, `MonthGrid` and its tests are deleted. Esc no longer closes the window; ⌘W does.

## Files
- Sources/OddFrog/MonthWindowController.swift                          (modify)
- Sources/OddFrog/AppDelegate.swift                                    (modify — View menu in `installMainMenu`)
- Sources/OddFrogCore/MonthGrid.swift                                  (delete)
- Tests/OddFrogCoreTests/MonthGridTests.swift                          (delete)
- docs/query-plugins.md                                                (modify — Month section)
- docs/calendar-plugin.md                                              (modify — the `cal month` scope line)
- Sources/OddFrogPluginAPI/PluginView.swift                            (read — `PluginView(month:title:)`; the contract stays unchanged)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarProvider.swift   (read — `monthView()` returns `PluginView(month: "month", title: "Calendar")`; stays unchanged)
- Sources/OddFrog/main.swift, Resources/Info.plist                     (read — the app runs as an accessory, so the main menu is never shown)
- Sources/OddFrog/DocumentWindowController.swift                       (read — `saveDocument(_:)` is the precedent for a menu item that reaches a window controller by selector)

## Context
- Preconditions:
  - Specs 43–51 have landed. The package targets macOS 26, and `swift build` has one warning,
    `nonisolated(unsafe)` in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`.
  - After spec 45, `AppDelegate.installMainMenu()` builds these top-level menus in order:
    - the app menu: About, Settings… ⌘,, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q;
    - File: Save ⌘S, Close ⌘W;
    - Edit: Undo, Redo, Cut, Copy, Paste, Delete, Select All, a Find submenu (⌘F, ⌘G, ⇧⌘G, ⌘E
      and friends), Spelling and Grammar, Substitutions, and Writing Tools;
    - Window, assigned to `NSApp.windowsMenu`.

    No View menu exists. No item uses ⌘T, ⌥⌘← or ⌥⌘→.
  - No earlier spec touches `MonthWindowController.swift`.
- `MonthWindowController` today:
  - Window: titled, closable, miniaturizable and not resizable, with content 340×280 and autosave
    name "month".
  - `DayCell` has a layer-backed accent circle for today, white text, and a fixed 40×32 size.
  - A `KeyView` first responder maps ←/→ to the previous and next month, unmodified T to today,
    and Esc to `performClose`.
  - The view also holds a 15 pt semibold heading, small `.rounded` chevron and Today buttons, and
    an `NSGridView` of 7 weekday labels and 42 cells.
  - Everything is fed by `MonthGrid` (`Sources/OddFrogCore/MonthGrid.swift`, used by nothing
    else), with `anchor` and `browsed` state.
  - `init()` observes `.NSCalendarDayChanged`, `.NSSystemTimeZoneDidChange` and
    `NSLocale.currentLocaleDidChangeNotification`, calling `refresh()` on the main actor, and
    `windowDidBecomeKey` calls `refresh()` too. `refresh()` jumps to the current month unless the
    user has browsed.
  - `present(_:)` sets the title from the view, resets to the current month, activates the app,
    and focuses `keyView`.
  - `AppDelegate` owns `private lazy var months = MonthWindowController()` and calls
    `months.present(view)` for `.month` views. That call stays.
- `Tests/OddFrogCoreTests/MonthGridTests.swift` holds five `@Test`s and nothing else. Deleting it
  and `MonthGrid.swift` leaves no reference to `MonthGrid` anywhere. The test target picks up
  files by directory, so `Package.swift` needs no change.
- Measured on this machine for `NSDatePicker` with `datePickerStyle = .clockAndCalendar` and
  `datePickerElements = .yearMonthDay`:
  - Its `fittingSize` is 139×148 pt.
  - Pinned to a titled window content view's `layoutMarginsGuide`, the content `fittingSize` is
    179×178 (20 pt sides and bottom, 10 pt top).
  - Its defaults are `datePickerMode = .single`, `isBezeled = true` and `drawsBackground = false`.
  - It draws its own month heading, weekday row and adjacent-month days, and marks today. It has
    three unlabeled navigation buttons: previous month, a middle button, and next month.
  - Its accessibility help reads "Use arrow keys to navigate the picker…". The arrow keys move
    the selected day.
  - `dateValue` is its only public state. The picker also keeps a displayed month that has no
    API:
    - Its own previous and next buttons page the displayed month and leave `dateValue`
      unchanged. Its middle button returns the display to the month that holds `dateValue`.
    - Assigning a `dateValue` in a different month from the current one moves the display to
      that month.
    - After paging with its own buttons, assigning a `dateValue` in the same month as the old
      one, even the same day, leaves the paged month on screen.
    - Assigning `calendar`, `locale` and `timeZone`, even to the same autoupdating values,
      redisplays the month that holds `dateValue`. Assigning a calendar with a different first
      weekday redraws the weekday row.
  - `Calendar.current.date(byAdding: .month, value: 1, to:)` from 31 January gives
    28 February, so stepping by months never skips a short month.
- Key-equivalent facts, verified in a scratch AppKit app on this machine:
  - A disabled `NSMenuItem` still consumes its key equivalent: `NSMenu.performKeyEquivalent(with:)`
    returns true for a matching item that validation disabled. The item is disabled whenever no
    responder in the key window's chain implements its action.
  - With a main-menu item keyed ⌘← whose action nobody implements, pressing ⌘← in a text view did
    nothing. Without the item, it moved the insertion point to the line start.
  - AppKit's standard key bindings map ⌘← and ⌘→ to `moveToLeftEndOfLine:` and
    `moveToRightEndOfLine:`. ⌥⌘←, ⌥⌘→ and ⌘T have no standard text binding.
- `NSEvent.SpecialKey.leftArrow.unicodeScalar` and `.rightArrow.unicodeScalar` give the key
  equivalent characters (U+F702, U+F703). A menu item's `keyEquivalentModifierMask` defaults to
  `.command`.
- The app's activation policy is `.accessory` (`main.swift`; `LSUIElement` in `Info.plist`). The
  main menu never appears in the menu bar, and its items act only through their key equivalents
  and responder-chain validation.
- Menu items with a nil target go to the first responder that implements the action, searching
  the key window's responder chain and then its delegate. `MonthWindowController` is both the
  month window's controller and its delegate. `DocumentWindowController.saveDocument(_:)` is
  reached the same way, through `#selector(DocumentWindowController.saveDocument(_:))`.
- No size, spacing or styling literals remain in `MonthWindowController.swift` after this task.
  The window starts with `contentRect: .zero` and is sized from `fittingSize`. The only numbers
  left are the -1 and 1 month steps, which are data.

## Plan
1. `Sources/OddFrog/MonthWindowController.swift`:
   - Delete `DayCell`, `KeyView`, `heading`, `keyView`, `weekdayLabels`, `cells`, `anchor`,
     `browsed`, `showPrevious()`, `showNext()`, `showToday()`, the `MonthGrid`-based `move(by:)`
     (rewritten below), `rebuild()`, `button(symbol:description:action:)` and the grid-building
     body of `buildContent()`. Drop
     `import OddFrogCore`, which only `MonthGrid` needed.
   - Add `private let picker = NSDatePicker()` and `private var today = Date()`.
   - `init()`:
     - Create the window with `contentRect: .zero` and the same style mask, and keep
       `isReleasedWhenClosed = false` and the "month" autosave name.
     - Move `window.center()` to after `buildContent()`, so it centres the final size.
     - Keep the three observers exactly as they are.
   - Add `private func show(_ date: Date)`. It sets `picker.dateValue = date`, then assigns
     `picker.calendar = .autoupdatingCurrent`, `picker.locale = .autoupdatingCurrent` and
     `picker.timeZone = .autoupdatingCurrent`, in that order. Every date change in this file
     goes through it.
     - The second half makes the picker show the month that holds `date`, even after the user
       paged away with the picker's own buttons. It also picks up a changed locale, first weekday
       or time zone (Context).
     - Rejected: assigning `dateValue` alone. After paging with the picker's buttons, it leaves
       the paged month on screen whenever the new date falls in the old date's month. Go to Today
       and reopening the window would then not show today.
   - `buildContent()`:
     - Set `datePickerStyle = .clockAndCalendar` and `datePickerElements = .yearMonthDay`, then
       call `show(today)`.
     - Pin all four edges of the picker to `content.layoutMarginsGuide`.
     - Finish with `window?.setContentSize(content.fittingSize)`.
     - Leave every other picker property at its default, and give the picker no target or action.
       Selecting a day only shows it, and nothing else happens.
   - `@objc func showPreviousMonth(_ sender: Any?)` and `@objc func showNextMonth(_ sender: Any?)`
     call a private `move(by months: Int)` with -1 and 1. `move(by:)` guards
     `Calendar.current.date(byAdding: .month, value: months, to: picker.dateValue)`, returns when
     it is nil, and otherwise calls `show` with the result.
   - `@objc func goToToday(_ sender: Any?)` sets `today = Date()` and calls `show(today)`.
   - These three are internal, not private, so `AppDelegate` can name them in `#selector`.
   - `present(_:)`: set the title, call `goToToday(nil)`, activate as today, and
     `window?.makeFirstResponder(picker)`.
   - `refresh()`, still called by the three observers:
     - Let `followed` be whether `picker.dateValue` is on the same day as `today`
       (`Calendar.current.isDate(_:inSameDayAs:)`).
     - Set `today = Date()`, then call `show(followed ? today : picker.dateValue)`.
     - A picker left on today follows the day across midnight. A user who selected another date
       stays on it. This replaces `browsed`.
     - Rejected: tracking browsing through the picker's action. Its own month buttons do not
       change `dateValue`, so the action would never see them.
   - `windowDidBecomeKey(_:)` calls `refresh()` only when `Date()` is no longer on the same day as
     `today`. Otherwise it does nothing, so switching to another window and back keeps a month
     the user paged to with the picker's buttons.
     - Rejected: calling `refresh()` on every key change, as today. `show` would jump the display
       back to the selected month each time the window became key.
2. `Sources/OddFrog/AppDelegate.swift`, `installMainMenu()`:
   - Build `NSMenu(title: "View")` with these items, all with a nil target:
     - "Previous Month": action `#selector(MonthWindowController.showPreviousMonth(_:))`, key
       `String(NSEvent.SpecialKey.leftArrow.unicodeScalar)`, `keyEquivalentModifierMask = [.command, .option]`;
     - "Next Month": the same with `rightArrow` and `showNextMonth(_:)`;
     - a separator;
     - "Go to Today": action `#selector(MonthWindowController.goToToday(_:))`, key `"t"`.
   - Insert its top-level item directly before the Window menu's top-level item, so the order is
     app, File, Edit, View, Window. Change nothing else in the menu.
   - Decision: ⌥⌘← and ⌥⌘→, not ⌘← and ⌘→. Context shows that a disabled item still eats its key
     equivalent. With ⌘←/⌘→ items, line-start and line-end movement would stop working in every
     other window's text: the Notes editor, the chat composer, the Settings fields, and the
     launcher's query field, whose `LauncherPanel.performKeyEquivalent(with:)` (spec 45) passes
     every ⌘ key it does not handle on to the main menu. ⌥⌘← and ⌥⌘→ have no text binding, so
     nothing is lost when these items are disabled.
     - Rejected: an `NSMenuDelegate.menuHasKeyEquivalent(_:for:target:action:)` hook, or toggling
       `isHidden` on the items while the month window is key, to keep ⌘←/⌘→. Both are hand-rolled
       key routing for one window.
   - Go to Today keeps ⌘T: it has no text binding and no other menu item uses it.
3. Delete `Sources/OddFrogCore/MonthGrid.swift` and `Tests/OddFrogCoreTests/MonthGridTests.swift`.
4. `docs/query-plugins.md`, Month section:
   - Replace "showing the current month in the user's calendar, first weekday, and locale." with
     "showing today in the system's graphical date picker, which follows the user's calendar,
     first weekday, and locale."
   - After the sentence that ends "no callback runs while browsing.", add "Besides the picker's
     own buttons and the arrow keys, Option+Cmd+Left Arrow and Option+Cmd+Right Arrow step one
     month back and forward, and Cmd+T returns to today." This follows the `Cmd+S` notation the
     file already uses.
   - Leave the rest of the paragraph.
5. `docs/calendar-plugin.md`: in the `cal month` scope line, replace "(plain grid, no events, works
   without Calendar access)" with "(the system date picker, no events, works without Calendar
   access)".

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners,
  no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and
  `if … { return … }` bodies where neighbouring code uses them, one type per file for new types,
  and no new package dependencies (Apple system frameworks such as SwiftUI and Observation are
  fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no
  `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font,
  `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or
  hex colours and no custom fills (semantic system colours only), no corner radii, no
  `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced
  `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins,
  system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding.
  Literal numbers are allowed only where AppKit has no system value (initial window content sizes,
  the launcher panel width and its glass corner radius) — the spec must list which literals
  remain.
- `MonthWindowController.swift` keeps no size, spacing or styling literals. The -1 and 1 month
  steps are its only numbers, as stated at the end of Context.
- The `PluginView` month contract, the Calendar plugin, and `months.present(view)` in
  `runPluginAction` stay unchanged. In `installMainMenu`, add only the View menu.
- Leave `NSApp.activate(ignoringOtherApps: true)` in `present(_:)` as it is.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (the five `MonthGridTests` tests are removed; nothing is added)
- `grep -rn "MonthGrid" Sources Tests Plugins docs` prints nothing
- `grep -n "DayCell\|KeyView\|NSGridView\|browsed\|systemFont\|cornerRadius\|controlSize\|bezelStyle\|cancelOperation\|NSColor\|import OddFrogCore" Sources/OddFrog/MonthWindowController.swift` prints nothing
- `grep -n "showPreviousMonth\|showNextMonth\|goToToday" Sources/OddFrog/AppDelegate.swift` prints three lines

## Manual review
1. `make run`, type `cal month`, and press Return. A window titled "Calendar" shows the system
   graphical calendar: the current month, today selected and marked, and weekday headers starting
   on your first day of the week. It has system margins and no custom heading or buttons.
2. The picker's own previous and next buttons page the month, and its middle button returns to
   the month of the selected day. ← and → move the selected day.
3. With the month window key, ⌥⌘← shows the previous month, ⌥⌘→ the next, and ⌘T returns to
   today. Click a 31st and press ⌥⌘→ into a shorter month: the selection lands on that month's
   last day, not in the month after.
4. Click today, then page ahead twice with the picker's own next button and press ⌘T. The
   current month is back on screen with today selected. Page ahead again, click another app's
   window, then click back into the month window: the paged month is still showing.
5. Esc leaves the window open, and ⌘W closes it. Page to another month with the picker's
   buttons, close the window, and run `cal month` again: it opens on the current month.
6. Open a note (`note`, then Return on "New note"), type a line, and press ⌘← and ⌘→. The
   insertion point moves to the line's start and end. ⌥⌘← in the note does nothing.
7. With the month window open, change "First day of week" in System Settings › General ›
   Language & Region, then click back into the month window. The weekday row starts on the new
   day.

## Out of scope
- Showing events, making date selection mean anything, or any plugin-contract change.
- The picker's own look, size, and the accessibility labels of its navigation buttons.
- Making the app's menus visible in the menu bar (the activation policy), and any other menu
  change.
- The Calendar plugin and its `cal month` row.

## Open questions
none
