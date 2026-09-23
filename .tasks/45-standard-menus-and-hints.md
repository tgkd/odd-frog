# Task: Build the standard main menu, stock status-menu items, and drop typed shortcut hints

## Goal
Odd Frog installs the standard macOS main menu: the app menu, File, Edit with Find, Spelling and
Grammar, Substitutions and Writing Tools, and a Window menu. So the standard shortcuts (⌘Q, ⌘H, ⌘M,
⌘, and the Edit shortcuts) reach the Settings, Note, Chat and Month windows.

The launcher still handles ⌘↩, ⌘1–9, ⌘I and ⌘, before the main menu, and ignores ⌘Q and ⌘H.

The status menu shows the global hotkey in the stock shortcut column. It puts the failure text and
the login note in item subtitles, with no glyphs typed into titles. Reminders and Calendar rows no
longer append "⌘↩ …" to their subtitles. The window-layout commands get per-layout SF Symbols.

## Files
- Sources/OddFrog/AppDelegate.swift                                      (modify)
- Sources/OddFrog/StatusMenu.swift                                       (modify)
- Sources/OddFrog/LauncherPanel.swift                                    (modify)
- Sources/OddFrog/LauncherViewController.swift                           (modify)
- Sources/OddFrog/WindowManager.swift                                    (modify)
- Sources/OddFrogCore/Hotkey.swift                                       (modify)
- Tests/OddFrogCoreTests/ConfigTests.swift                               (modify)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift  (modify)
- Plugins/Reminders/Tests/RemindersProviderTests.swift                   (modify)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarProvider.swift     (modify)
- Plugins/Calendar/Tests/CalendarProviderTests.swift                     (modify)
- Plugins/Windows/plugin.toml                                            (modify)
- Sources/OddFrog/HotKeyManager.swift                                    (read — registers the global hotkey with `RegisterEventHotKey` from `Hotkey.keyCode`/`.modifiers`)
- Sources/OddFrog/HotkeyRecorder.swift                                   (read — overrides `performKeyEquivalent(with:)` and returns `true` while recording; its NSEvent→Carbon modifier mapping is the inverse of the one needed here)
- Sources/OddFrog/LoginItem.swift                                        (read — `SMAppService.mainApp.status` values)
- Sources/OddFrog/DocumentWindowController.swift                         (read — `saveDocument(_:)`, the File › Save action)
- docs/calendar-plugin.md                                                (read — "Command-Return joins a recognized meeting URL" stays true; no doc change)

## Context
- Preconditions:
  - Spec 43 has landed. The deployment target is macOS 26, and the only expected build warning is
    the UnitRegistry `nonisolated(unsafe)` one.
  - Spec 44 has landed. `LauncherPanel` has no custom animation and `LauncherViewController` has
    its stock `.inset` layout. Both left `LauncherPanel.sendEvent(_:)` and
    `LauncherViewController.handleKeyEquivalent(_:)` as they were.
- The app runs with the `.accessory` activation policy (`main.swift`, and `LSUIElement` in
  `Info.plist`). An accessory app never shows a menu bar. Its main menu matters only for key
  equivalents, and items without one, such as About and Show All, cannot be reached. They are
  included only to complete the standard structure.
- `AppDelegate.installMainMenu()` today installs:
  - an app-menu slot that is an empty `NSMenuItem()` with no submenu,
  - a File menu with Save ⌘S (`#selector(DocumentWindowController.saveDocument(_:))`) and Close ⌘W
    (`#selector(NSWindow.performClose(_:))`),
  - an Edit menu with Undo ⌘Z (`Selector(("undo:"))`), Redo ⇧⌘Z (`Selector(("redo:"))`), a
    separator, then Cut, Copy, Paste and Select All (`NSText` selectors).

  It never sets `NSApp.windowsMenu`.
- AppKit already appends AutoFill, Start Dictation… and Emoji & Symbols to a menu titled "Edit".
  It does not add Writing Tools. `NSMenuItem.writingToolsItems` (macOS 15.2) returns one "Writing
  Tools" item with its own submenu. `NSTextFinder.Action` raw values: `showFindInterface` 1,
  `nextMatch` 2, `previousMatch` 3, `setSearchString` 7, `showReplaceInterface` 12. A menu item
  with action `performTextFinderAction(_:)` carries one of these as its `tag`.
- Key-equivalent routing, measured in a scratch accessory app. The setup: a borderless
  `.nonactivatingPanel` that is key, with its text field's field editor as first responder, while
  another app stayed frontmost and owned the menu bar.
  - `NSApplication.sendEvent` offers each ⌘ key-down first to the key window's
    `performKeyEquivalent(with:)`, then to the main menu, and only then to the window's
    `sendEvent(_:)`.
  - Main-menu items for ⌘, ⌘Q and ⌘H fired from the panel even though the app was not frontmost.
    `NSApp.isActive` reads `true` while the panel is key.
  - Today's `LauncherPanel.sendEvent(_:)` would therefore lose ⌘, to a Settings… item. A
    `performKeyEquivalent(with:)` override on the panel received ⌘, ⌘↩ and ⌘1 before the menu,
    and could consume them.
  - Letting ⌘H through is harmful. After `NSApp.hide` while the panel was key, ordering the panel
    front again unhid the app, but in some runs the panel did not become key, or became key and
    then resigned. Here `onResignKey` would dismiss it at once.
  - ⌘F, ⌘M and ⌘W from the panel were taken by those menu items and did nothing visible. That is
    harmless, and the behaviour is the same as today's ⌘W.
- The launcher's ⌘ keys today:
  - `LauncherPanel.sendEvent(_:)` passes key-downs whose device-independent modifiers are exactly
    `.command` to `onKeyEquivalent`.
  - `AppDelegate.wirePanel()` sets that closure to `controller.handleKeyEquivalent(_:)`. That
    function handles ⌘↩ (key codes 36 and 76) as the secondary action, ⌘1–9, ⌘I (reveal in
    Settings) and ⌘, (`onSettings`), and returns `false` otherwise.
  - Today no main-menu item has ⌘Q or ⌘H, so these keys reach the field editor and do nothing.
  - `handleKeyEquivalent` matches letters through `charactersIgnoringModifiers`, which follows the
    current input source. With a non-Latin source such as Russian, the Q key gives `"й"` and the H
    key gives `"р"`. AppKit still matches ⌘-menu key equivalents against an ASCII-capable layout
    in that case, so a main-menu Quit ⌘Q item fires there. The physical key codes are Q = 12 and
    H = 4 (the `q` and `h` entries of `Hotkey.keyCodes`).
- `HotkeyRecorder` overrides `performKeyEquivalent(with:)` and returns `true` while recording. The
  key window's view hierarchy is offered keys before the main menu, so a combination such as ⌘Q
  can still be recorded as the hotkey in Settings.
- `StatusMenu`:
  - `menuNeedsUpdate(_:)` rebuilds the status item's menu on every open. It holds
    `var hotkeyDescription = ""` and adds `action("Show  \(hotkeyDescription)", #selector(show))`,
    with two spaces and a glyph string such as "⌥Space".
  - When `lastFailure` is set, it adds an item titled `"Last failure: " + <first line, cut to 60 characters + "…">`
    that copies the full text, with the full text as `toolTip`.
  - The login item title is "Launch at Login", "Launch at Login (approve in System Settings…)" or
    "Launch at Login (install to ~/Applications first)". The item carries a checkmark `state` when
    `LoginItem.status == .enabled`.
  - In `init`, the status button image comes from `NSImage(systemSymbolName: "bolt.horizontal.fill", …)`,
    followed by `image?.isTemplate = true`. Measured: symbol images are already template images,
    so that line changes nothing.
  - Settings… (⌘,) and Quit Odd Frog (⌘Q) already use the stock key-equivalent column.
- `AppDelegate` sets `status.hotkeyDescription` in four places: `wireStatusMenu()`, the fallback in
  `wireHotkey()`, `reloadConfig(from:source:)` and `setHotkey(_:)`. Each assigns a `Hotkey`'s
  `.description`.
- `Hotkey` in `OddFrogCore` is Foundation only:
  - It stores a Carbon `keyCode` and Carbon `modifiers`, with the masks `cmdKey`, `shiftKey`,
    `optionKey` and `controlKey`.
  - `keyName(for:)` returns the preferred name for a key code. It returns `space`, `enter`, `tab`,
    `esc` and `delete` rather than their aliases, and otherwise a single character (`a`–`z`,
    digits, punctuation), `f1`–`f15`, or `left`/`right`/`up`/`down`.
  - `HotKeyManager` registers the combination with `RegisterEventHotKey`, which the system
    intercepts and delivers as a hot-key event. Pressing it while the status menu is open can only
    toggle the launcher, whether through the hot key or through the Show item. Both do the same
    thing.
- The key-equivalent characters for special keys:
  - space `" "`, return `"\r"`, tab `"\t"`, escape `"\u{1b}"`
  - the Delete (⌫) key: `NSBackspaceCharacter` `"\u{8}"`
  - arrows: `NSUpArrowFunctionKey` 0xF700, down 0xF701, left 0xF702, right 0xF703
  - `NSF1FunctionKey` 0xF704 through F15 0xF712, so Fn is `0xF703 + n`
- `NSMenuItem.subtitle` (macOS 14.4) draws a second, smaller line under a plain title.
- Typed hints:
  - `RemindersProvider.respond` builds each reminder row's subtitle as
    `(details + ["⌘↩ Complete"]).joined(separator: " · ")`. `details` always has at least the date
    label, "No date" when there is none, so it is never empty.
  - `CalendarProvider.agendaRows` builds `details + (meeting == nil ? "" : " · ⌘↩ Join")`.
  - Those are the only "⌘" strings in `Plugins/` and `Sources/` outside `Hotkey.swift`.
  - The test `reminderRowsCompleteOnTheSecondaryAction` expects the suffix `" · ⌘↩ Complete"`. In
    the `mixed` fixture, the first row `overdue` is in the list "Inbox", and its time text depends on
    the locale.
  - Calendar's `onlyRecognizedHTTPSMeetingHostsBecomeJoinActions` builds an event with calendar
    "Work" and location `"Join: https://us02web.zoom.us/j/123"`. The subtitle is time · Work ·
    location. It checks the secondary action but not the subtitle.
  - The secondary actions themselves (complete a reminder, join a meeting) stay unchanged.
- `Plugins/Windows/plugin.toml` gives all ten commands `symbol = "rectangle"`. The SF Symbols
  catalogue in this OS:
  - The per-layout tiles exist with these current names, available since macOS 15:
    `inset.filled.lefthalf.rectangle`, `inset.filled.righthalf.rectangle`,
    `inset.filled.tophalf.rectangle`, `inset.filled.bottomhalf.rectangle` and
    `inset.filled.rectangle`. The older `rectangle.lefthalf.inset.filled`-style names are now
    aliases of these.
  - `macwindow.stack` is available since macOS 26.
  - There is no two-thirds or three-quarters tile.
  - Each name above returns an image from `NSImage(systemSymbolName:accessibilityDescription:)`.
- `WindowManager.openAccessibilitySettings()` is never called. The permission flow uses
  `AXIsProcessTrustedWithOptions` with the prompt option.

## Plan
1. `Sources/OddFrog/LauncherPanel.swift`: replace the `sendEvent(_:)` override with
   `override func performKeyEquivalent(with event: NSEvent) -> Bool`. It keeps today's condition: a
   `.keyDown` whose device-independent modifiers are exactly `.command`, and `onKeyEquivalent`
   returns `true`. When the condition holds it returns `true`, otherwise
   `super.performKeyEquivalent(with: event)`.

   Decision: `performKeyEquivalent` is where AppKit offers key equivalents before the main menu
   (Context). Keeping `sendEvent` was rejected because the new Settings… ⌘, item would take ⌘,
   first, and any later menu item would silently shadow a launcher key. Main-menu items for the
   launcher keys were also rejected: ⌘↩ and ⌘1–9 act on the selected row and have no meaning in the
   other windows.
2. `Sources/OddFrog/LauncherViewController.swift`, `handleKeyEquivalent(_:)`: before the final
   `return false`, add a branch that returns `true` in either of two cases. That consumes ⌘Q and
   ⌘H with no action, which keeps today's behaviour.
   - `charactersIgnoringModifiers` is `"q"` or `"h"`.
   - The characters are not all ASCII (a non-Latin input source) and `event.keyCode` is `12` or
     `4`. `Character.isASCII` is enough for the check.

   The key-code case covers non-Latin input sources, where the characters differ but the menu would
   still quit or hide (Context). It applies only when the characters are not ASCII. On an
   ASCII layout, physical key 12 can be another letter, for example "a" on French AZERTY, and ⌘A
   must still reach Select All. The key-code literals match the existing `36`/`76` check for
   Return in the same function.

   Decision: letting the main menu quit or hide Odd Frog from the launcher was rejected. A slip of
   ⌘Q would kill the global hotkey, and ⌘H would leave the panel unable to stay key on its next
   show (Context). ⌥⌘H (Hide Others) and every other key pass through unchanged.
3. `Sources/OddFrogCore/Hotkey.swift`: add `public var keyEquivalent: String`, built from
   `Hotkey.keyName(for: keyCode)`:
   - `space` → `" "`, `enter` → `"\r"`, `tab` → `"\t"`, `esc` → `"\u{1b}"`, `delete` → `"\u{8}"`
   - `up` → `"\u{F700}"`, `down` → `"\u{F701}"`, `left` → `"\u{F702}"`, `right` → `"\u{F703}"`
   - `f1`–`f15`: a name longer than one character that starts with `f` and parses as `f<n>` becomes
     the character `0xF703 + n`
   - any other name → the name itself
   - no name → `""`

   It stays Foundation-only. The AppKit modifier flags are mapped in `StatusMenu`.
4. `Tests/OddFrogCoreTests/ConfigTests.swift`: add `@Test func hotkeyKeyEquivalentsUseAppKitCharacters() throws`
   next to `hotkeySerializationRoundTrips`. It checks that `try Hotkey.parse(text).keyEquivalent`
   equals the expected value for each of:
   - `alt+space` → `" "`, `cmd+shift+k` → `"k"`, `ctrl+return` → `"\r"`, `alt+tab` → `"\t"`
   - `alt+esc` → `"\u{1b}"`, `alt+delete` → `"\u{8}"`
   - `cmd+up` → `"\u{F700}"`, `cmd+down` → `"\u{F701}"`, `cmd+left` → `"\u{F702}"`,
     `cmd+right` → `"\u{F703}"`
   - `alt+f1` → `"\u{F704}"`, `alt+f15` → `"\u{F712}"`, `alt+,` → `","`
5. `Sources/OddFrog/StatusMenu.swift`:
   - Replace `var hotkeyDescription = ""` with `var hotkey = Hotkey.default`.
   - In `init`, drop the `isTemplate` line and assign the symbol image to `item.button?.image`
     directly.
   - Show item: title `"Show"`, `keyEquivalent = hotkey.keyEquivalent`, and
     `keyEquivalentModifierMask` mapped from `hotkey.modifiers`: `Hotkey.cmdKey` → `.command`,
     `optionKey` → `.option`, `controlKey` → `.control`, `shiftKey` → `.shift`. Use a local name
     other than `show`, so `#selector(show)` stays unambiguous.
   - Failure item: title `"Copy Last Failure"`, with the existing first-line text cut to 60
     characters plus "…" as its `subtitle`. Keep the full text as `toolTip` and the separator after
     it. The subtitle does not truncate by itself, so the 60-character cap stays.
   - Login item: title always `"Launch at Login"`, `state` as today, and `subtitle` from a private
     `loginNote: String?` that replaces `loginTitle`:
     - `.requiresApproval` → `"Approve in System Settings"`
     - `.notFound` → `"Install to ~/Applications first"`
     - otherwise `nil`

   Every other item and its order stay the same.
6. `Sources/OddFrog/AppDelegate.swift`:
   - In the four places that set `status.hotkeyDescription = X.description`, set
     `status.hotkey = X` instead: `config.general.hotkey`, `Hotkey.default`,
     `candidate.general.hotkey` and `hotkey`.
   - Add `@objc private func openSettings(_ sender: Any?) { showSettings() }`.
   - Rewrite `installMainMenu()`. It builds a main `NSMenu` whose items are, in this order, the app
     menu, File, Edit and Window, each an `NSMenuItem` with that menu as its `submenu`, and assigns
     it to `NSApp.mainMenu` as today. Titles, actions and key equivalents (⌘ unless noted):
     - App menu (`NSMenu(title: "Odd Frog")`):
       - About Odd Frog, `#selector(NSApplication.orderFrontStandardAboutPanel(_:))`
       - separator
       - Settings… `,`, action `openSettings(_:)`, `target = self`
       - separator
       - Hide Odd Frog `h`, `#selector(NSApplication.hide(_:))`
       - Hide Others `h` with `[.command, .option]`, `#selector(NSApplication.hideOtherApplications(_:))`
       - Show All, `#selector(NSApplication.unhideAllApplications(_:))`
       - separator
       - Quit Odd Frog `q`, `#selector(NSApplication.terminate(_:))`
     - File: unchanged (Save, Close).
     - Edit:
       - Undo, Redo, separator, Cut, Copy, Paste as today.
       - Delete, `#selector(NSText.delete(_:))`, no key, placed after Paste. Select All as today.
       - separator
       - Find submenu. Every item except the last has action
         `#selector(NSResponder.performTextFinderAction(_:))` and a `tag` from
         `NSTextFinder.Action.….rawValue`:
         - Find… `f` (`.showFindInterface`)
         - Find and Replace… `f` with `[.command, .option]` (`.showReplaceInterface`)
         - Find Next `g` (`.nextMatch`)
         - Find Previous `g` with `[.command, .shift]` (`.previousMatch`)
         - Use Selection for Find `e` (`.setSearchString`)
         - Jump to Selection `j`, `#selector(NSResponder.centerSelectionInVisibleArea(_:))`
       - Spelling and Grammar submenu:
         - Show Spelling and Grammar `:`, `#selector(NSText.showGuessPanel(_:))`
         - Check Document Now `;`, `#selector(NSText.checkSpelling(_:))`
         - separator
         - Check Spelling While Typing, `#selector(NSTextView.toggleContinuousSpellChecking(_:))`
         - Check Grammar With Spelling, `#selector(NSTextView.toggleGrammarChecking(_:))`
         - Correct Spelling Automatically, `#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))`
       - Substitutions submenu:
         - Show Substitutions, `#selector(NSTextView.orderFrontSubstitutionsPanel(_:))`
         - separator
         - Smart Copy/Paste (`toggleSmartInsertDelete(_:)`), Smart Quotes
           (`toggleAutomaticQuoteSubstitution(_:)`), Smart Dashes
           (`toggleAutomaticDashSubstitution(_:)`), Smart Links (`toggleAutomaticLinkDetection(_:)`),
           Data Detectors (`toggleAutomaticDataDetection(_:)`) and Text Replacement
           (`toggleAutomaticTextReplacement(_:)`), all `NSTextView` selectors
       - separator
       - every item of `NSMenuItem.writingToolsItems`

       Do not add AutoFill, Dictation or Emoji & Symbols: AppKit adds them.
     - Window (`NSMenu(title: "Window")`):
       - Minimize `m`, `#selector(NSWindow.performMiniaturize(_:))`
       - Zoom, `#selector(NSWindow.performZoom(_:))`
       - separator
       - Bring All to Front, `#selector(NSApplication.arrangeInFront(_:))`

       Then set `NSApp.windowsMenu` to this menu.

     All items except Settings… are nil-targeted, so the responder chain decides where they apply
     and whether they are enabled. Small private helpers that build an item or a submenu item are
     fine. Keep the function in `AppDelegate`, because spec 52 adds a View menu to it.
   - Decision: build the menu in code in `installMainMenu()`. A nib or a separate menu type was
     rejected: the repository has neither, and the rest of the app is built in code.
7. `Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift`: the reminder row
   subtitle becomes `details.joined(separator: " · ")`. The `secondary` action is unchanged.
8. `Plugins/Reminders/Tests/RemindersProviderTests.swift`: in
   `reminderRowsCompleteOnTheSecondaryAction`, replace the `" · ⌘↩ Complete"` expectation with
   `#expect(response.items[0].subtitle?.hasSuffix(" · Inbox") == true)`. The list name now ends the
   subtitle.
9. `Plugins/Calendar/Sources/CalendarPluginCore/CalendarProvider.swift`: the event row subtitle
   becomes `details`. Leave the existing comment in `agendaRows` as it is.
10. `Plugins/Calendar/Tests/CalendarProviderTests.swift`: in
    `onlyRecognizedHTTPSMeetingHostsBecomeJoinActions`, add
    `#expect(item.subtitle?.hasSuffix("Work · Join: https://us02web.zoom.us/j/123") == true)`. The
    subtitle ends with the location, and nothing is appended.
11. `Plugins/Windows/plugin.toml`: set each command's `symbol`:
    - `place:left:1-2` and `place:left:2-3` → `inset.filled.lefthalf.rectangle`
    - `place:right:1-2` and `place:right:2-3` → `inset.filled.righthalf.rectangle`
    - `place:top:1-2` and `place:top:3-4` → `inset.filled.tophalf.rectangle`
    - `place:bottom:1-2` and `place:bottom:3-4` → `inset.filled.bottomhalf.rectangle`
    - `maximize` → `inset.filled.rectangle`
    - `tidy` → `macwindow.stack`

    Decision: ⅔ and ¾ share their side's half tile, because SF Symbols has no two-thirds or
    three-quarters tile. The arrow variants such as `inset.filled.lefthalf.arrow.left.rectangle`
    were rejected: they exist only for left and right, and they read as "move", not as a size. The
    new names are used instead of the older `rectangle.*.inset.filled` aliases.
12. `Sources/OddFrog/WindowManager.swift`: delete `static func openAccessibilitySettings()`.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners,
  no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and
  `if … { return … }` bodies where neighbouring code uses them, one type per file for new types, and
  no new package dependencies (Apple system frameworks such as SwiftUI and Observation are fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no
  `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font,
  `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or hex
  colours and no custom fills (semantic system colours only), no corner radii, no
  `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced
  `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins,
  system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding.
  Literal numbers are allowed only where AppKit has no system value (initial window content sizes,
  the launcher panel width and its glass corner radius) — the spec must list which literals
  remain.
- This spec adds no UI literals. The remaining numbers are data, not styling:
  - the AppKit function-key code points in `Hotkey.keyEquivalent`,
  - the key codes 12 (Q) and 4 (H) in `handleKeyEquivalent`,
  - the existing 60-character cap on the failure subtitle.
- No key glyphs or shortcut text in menu titles. Shortcuts go only in `keyEquivalent` and
  `keyEquivalentModifierMask`. In result subtitles, remove only the "⌘↩ …" hints listed in Plan.
  The plain-language status rows such as "Press Return to open Reminders." stay.
- Do not add images to menu items, and do not add a row context menu or a title field to
  `PluginAction`.
- Do not change the launcher layout and styling from spec 44, the secondary actions themselves,
  `NSApp.activate(ignoringOtherApps:)` or the activation policy.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (one test added: `hotkeyKeyEquivalentsUseAppKitCharacters`; `reminderRowsCompleteOnTheSecondaryAction` and `onlyRecognizedHTTPSMeetingHostsBecomeJoinActions` changed)
- `grep -rn "⌘↩" Plugins Sources Tests` prints nothing
- `grep -rn "hotkeyDescription\|openAccessibilitySettings\|override func sendEvent\|isTemplate" Sources` prints nothing
- `grep -c 'symbol = "rectangle"' Plugins/Windows/plugin.toml` prints `0`
- `grep -n "windowsMenu\|writingToolsItems\|performTextFinderAction" Sources/OddFrog/AppDelegate.swift` prints at least three lines

## Manual review
1. `make run`. Click the status item:
   - "Show" has the hotkey (for example ⌥Space) right-aligned in the shortcut column, like
     "Settings… ⌘," and "Quit Odd Frog ⌘Q".
   - No title contains a typed key glyph.
2. Break the config on purpose: add a line `[general` to `~/.config/odd-frog/v2/config.toml` and
   choose Reload Config. The status menu shows "Copy Last Failure" with the first line of the error
   as a smaller gray subtitle. Choosing it copies the full message. Remove the line and reload
   again.
3. "Launch at Login" has a checkmark when it is enabled. In the approval-needed or not-installed
   state, the explanation appears as a subtitle, not in parentheses in the title.
4. Open the launcher:
   - ⌘, opens Settings and closes the launcher.
   - ⌘Q and ⌘H do nothing; the app keeps running and the launcher stays open.
   - Switch the input source to a non-Latin layout such as Russian and press ⌘Q and ⌘H again.
     They still do nothing.
   - ⌘↩, ⌘1–9 and ⌘I behave as before.
   - ⌘A, ⌘C, ⌘V and ⌘Z work in the query field.
5. With Settings frontmost:
   - ⌘M minimizes it. Choose Settings… in the status menu to bring it back, then press ⌘W: it
     closes.
   - Reopen Settings with ⌘, from a Note window: type `note`, open a note, press ⌘,.
   - In the note, ⌘: (⇧⌘; on a US keyboard) opens the system Spelling and Grammar panel.
6. With Settings frontmost, press ⌘H. Odd Frog's windows hide. Press the hotkey: the launcher opens
   with the caret in the query field and accepts typing. Settings may reappear behind it. Repeat a
   few times. If the launcher closes right after opening, report it; see Out of scope.
7. With Settings frontmost, press ⌘Q. Odd Frog quits, and the status item disappears.
8. `make run` again:
   - `rem` lists reminders whose subtitles read date · list, plus "High priority" when it applies,
     with no "⌘↩ Complete". ⌘↩ on a reminder still completes it.
   - `cal` rows with a meeting link show no "· ⌘↩ Join", and ⌘↩ still opens the meeting.
9. Enable Windows in Settings › Plugins and type `left`, `right`, `top`, `bottom`, `maximize` and
   `tidy`. Each half and its ⅔/¾ variant shows that side's half tile. Maximize shows a filled tile,
   and Tidy Windows shows stacked windows.

## Out of scope
- A row context menu, or any other place that shows secondary actions and their shortcuts.
- The View menu and the month commands (spec 52), and usesFindBar in the Note editor (spec 51). ⌘F
  shows a find bar only once a text view opts in.
- Changing how the app unhides when the launcher opens after ⌘H from another Odd Frog window. If
  step 6 of Manual review fails, record it as a follow-up.
- `NSApp.activate(ignoringOtherApps:)`, the activation policy, and adding About to the status menu.
- Calendar and Reminders privacy-pane URLs in the providers.
- Localising menu titles.

## Open questions
none
