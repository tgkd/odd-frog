# Task: Settings window becomes a stock split view with a source-list sidebar, and the General pane becomes a SwiftUI grouped form

## Goal
Settings opens as a stock titled window whose content is an `NSSplitViewController`: a system
sidebar with a source-list table (General, Items, Plugins, each with an outline SF Symbol) and a
detail area that shows the selected pane. The window title is the pane name. The General pane is a
SwiftUI `Form` in the grouped style, and the keyboard-shortcut control is a stock push-on/push-off
`NSButton`. It keeps today's key capture, conflict reporting and Launch at Login behaviour. The
Items and Plugins panes look as they do today; specs 47 and 48 restyle them.

## Files
- Sources/OddFrog/SettingsWindowController.swift     (modify)
- Sources/OddFrog/HotkeyRecorder.swift                (modify)
- Sources/OddFrog/SettingsLayout.swift                (modify — `hairline()` only)
- Sources/OddFrog/SettingsPane.swift                  (create)
- Sources/OddFrog/SettingsSidebarController.swift     (create)
- Sources/OddFrog/GeneralPaneModel.swift              (create)
- Sources/OddFrog/GeneralPaneView.swift               (create)
- Sources/OddFrog/HotkeyRecorderView.swift            (create)
- Sources/OddFrog/SettingsSidebar.swift               (delete)
- Sources/OddFrog/IconTile.swift                      (delete)
- Sources/OddFrog/AppDelegate.swift                   (read — every caller of the settings window; stays unchanged)
- Sources/OddFrog/LoginItem.swift                     (read — `status` and `toggle()`)
- Sources/OddFrog/PluginsPane.swift                   (read — hosted unchanged; calls `SettingsLayout.hairline()`)
- Sources/OddFrogCore/Hotkey.swift                    (read — `Hotkey(keyCode:modifiers:)`, `description`, modifier bits)

## Context
- Precondition: specs 43–45 have landed.
  - Spec 43: `Package.swift` is `swift-tools-version: 6.2` with `.macOS(.v26)`. The line
    `toolbar.showsBaselineSeparator = false` is gone from `SettingsWindowController.init`. The
    SIGUSR2 debug hook's `@settings <pane>` path still calls `showSettings()` and then
    `settingsWindow.select(pane)`, where `pane` is
    `SettingsPane.allCases.first { $0.title.lowercased() == name }`.
  - Specs 44 and 45 changed the launcher and the menus. They did not touch any Settings file.
- The `OddFrog` target is an executable target in Swift 6 language mode, and no file imports
  SwiftUI yet. No test target depends on `OddFrog`.
- `SettingsWindowController.init(icons:)` today:
  - It builds an `NSWindow` with content rect 760×560 and style mask
    `[.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]`.
  - It sets `title = "Odd Frog Settings"`, `minSize` 760×560, `isReleasedWhenClosed = false` and
    `backgroundColor = .windowBackgroundColor`.
  - It sets `titlebarAppearsTransparent = true`, `titleVisibility = .hidden` and
    `titlebarSeparatorStyle = .none`.
  - It adds an empty `NSToolbar(identifier: "settings")` with `toolbarStyle = .unified`, then
    calls `center()`.
  - `buildContent()` pins a `SettingsSidebar` (200pt wide) and a host view by hand. The host holds
    a 15pt semibold `paneTitle` label and a container with the three pane views. `showPane(_:)`
    toggles `isHidden` on those views.
- `Sources/OddFrog/SettingsSidebar.swift` holds five types:
  - `SettingsPane`: `Int`, `CaseIterable`, cases `general, items, plugins`, with `title`,
    `symbol` (`gearshape.fill`, `square.grid.2x2.fill`, `puzzlepiece.extension`) and `tint`.
  - `Hairline`, an `NSView` whose `draw(_:)` fills with `separatorColor`. Its only other user is
    `SettingsLayout.hairline()`, which `PluginsPane` calls between rows.
  - `SettingsSidebar`, `SidebarRowView` and `SidebarCellView`. These hand-build a vibrancy view,
    a divider, a rounded selection drawn with `SelectionPalette`, and `IconTile` squares.

  `IconTile` (in `IconTile.swift`) has no other user.
- What `AppDelegate` uses on `settingsWindow`. All of it must keep compiling unchanged:
  - `present(settings:items:hotkey:focusing:)`, `update(items:)` and `update(pluginSettings:)`;
  - `showHotkey(_:note:)`, `select(_:)` and `manageLinks()`;
  - `pluginsPane` (the `PluginsPane` view and its callbacks);
  - `onChange`, `onApplyLink`, `onHotkey` and `links`;
  - `window?.isVisible`.
- `AppDelegate.setHotkey(_:)` applies the hotkey. On failure it calls
  `settingsWindow.showHotkey(hotkeys.current ?? config.general.hotkey, note: "\(error)")`. On
  success it calls `settingsWindow.showHotkey(hotkey)`. `present` is always given
  `hotkeys.current ?? config.general.hotkey`.
- General pane behaviour today. Every item needs a home in the new pane:
  - The "Keyboard shortcut" row has a helper line. The helper reads
    "Click, then press a new combination." when idle and "Press the keys you want to use." while
    recording. After a failed apply it reads `note + " Try another combination."` in red.
  - While there is a conflict, the recorder shows the rejected combination instead of the
    current one.
  - Starting a new recording clears the conflict. `showHotkey` without a note also clears it.
  - `HotkeyRecorder` today is an `NSControl` that draws itself: `draw(_:)`, `drawFocusRingMask`,
    `focusRingMaskBounds`, a forced `.exterior` focus ring, and a 120×22 `intrinsicContentSize`.
    Its key capture:
    - A click, or Space (key code 49) or Return (36) while focused, starts recording.
    - While recording, `performKeyEquivalent` routes into `keyDown`.
    - Esc (53), Delete (51) and Forward Delete (117) with no modifiers cancel the recording.
    - Other keys map ⌘⇧⌥⌃ to `Hotkey.cmdKey/shiftKey/optionKey/controlKey`.
      `Hotkey(keyCode:modifiers:)` returning `nil` beeps.
    - A valid combination ends recording, resigns first responder and calls `onRecord`.
    - Losing first responder ends recording.
    - `onRecordingChanged` reports every change of the recording state.
  - The "Launch at login" row has a switch and a status line. `LoginItem.status`
    (`SMAppService.Status`) drives both:
    - `.enabled`: switch on, "Odd Frog opens when you log in.".
    - `.requiresApproval`: switch on, "Waiting for approval in System Settings › Login Items." in
      orange, and an "Open Login Items…" button, which calls
      `SMAppService.openSystemSettingsLoginItems()`.
    - `.notFound`: switch off and disabled, "Move Odd Frog to your Applications folder to enable
      this.".
    - Anything else: switch off, no text.

    Flipping the switch calls `LoginItem.toggle()`, refreshes the status at once and again 0.3s
    later. A thrown error is written to the status line in red, but the immediate refresh
    overwrites it, so today it never shows.
  - `present` calls `showHotkey(hotkey)` and `refreshLogin()` each time the window is shown.
    Nothing else calls `refreshLogin()`.
- Facts about the stock pieces used below:
  - Assigning `window.contentViewController` shrinks the window to the controller's current size,
    so the content size has to be set again afterwards.
  - An `NSSplitViewItem(sidebarWithViewController:)` gives the system sidebar material, divider
    and standard thickness (a 144pt minimum), and `canCollapse` defaults to `true`. With
    `.fullSizeContentView` the sidebar runs the full window height.
  - Views in the detail item get a top safe-area inset equal to the titlebar height.
    `layoutMarginsGuide` sits inside the safe area with the system margins.
  - `NSTabViewController` with `tabStyle = .unspecified` draws no tab UI. Setting
    `selectedTabViewItemIndex` swaps the child view synchronously: the new child's view is in the
    window when the setter returns. Its default `transitionOptions` is `.allowUserInteraction`
    only, with no crossfade (measured; the header comment claims a crossfade default).
  - An `NSTableView` with `style = .sourceList` turns off its scroll view's background drawing
    when it becomes the document view. When `imageView` and `textField` are added to an
    `NSTableCellView` without constraints, the cell positions and sizes them, and applies the
    fonts for the table's `rowSizeStyle` (measured with `.default`: rows follow the system sidebar
    size, symbols about 18pt, 15pt text). Its single column fills the sidebar width by itself.
  - A source-list table draws its selected row emphasized (accent colour) only while the table is
    first responder in the key window, and grey otherwise. A click on a row makes the table first
    responder.
  - `NSButton(frame:)` defaults to the automatic bezel and is bordered.
  - Measured: `NSWindow.performKeyEquivalent(with:)` reaches an `NSButton` subclass that sits in a
    `LabeledContent` of a grouped `Form` inside an `NSHostingController`. So a recorder that is
    first responder still sees ⌘ combinations such as ⌘Q before the main menu that spec 45
    installed, and plain key-downs go to its `keyDown`.
  - In a SwiftUI `Form` with `.formStyle(.grouped)`, a control label built from two `Text` views
    renders as a title plus a secondary subtitle. A `Text` with `.foregroundStyle(.red)` or
    `.orange` keeps that colour in the subtitle position, and `Toggle` renders as a switch.
    An `NSViewRepresentable` button stretches to the full row width unless `.fixedSize()` is
    applied.

## Plan
1. Create `Sources/OddFrog/SettingsPane.swift` with `enum SettingsPane: Int, CaseIterable`, moved
   from `SettingsSidebar.swift`. Keep the cases in the order `general, items, plugins` and keep
   `title`. The raw value is both the sidebar row and the tab index.
   - Delete `tint`.
   - `symbol` becomes the outline set: `"gearshape"`, `"square.grid.2x2"` and
     `"puzzlepiece.extension"`.
2. Create `Sources/OddFrog/SettingsSidebarController.swift`:
   `@MainActor final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate`.
   - `init()` calls `super.init(nibName: nil, bundle: nil)` and configures a private
     `NSTableView`: one column, `headerView = nil`, `style = .sourceList`,
     `rowSizeStyle = .default` and `allowsEmptySelection = false`, with data source and delegate
     set to `self`. `required init?(coder:)` returns `nil`. The table is configured in `init`, not
     in `loadView`, so that `selected` works before the view loads.
   - `loadView()` creates an `NSScrollView` with the table as its document view and assigns it to
     `view`. Set no background, scroller or inset properties.
   - Keep today's API from `SettingsSidebar`:
     - `var onSelect: ((SettingsPane) -> Void)?`;
     - `var selected: SettingsPane`, whose setter selects the row with the callback suppressed;
     - `numberOfRows(in:)`, which returns `SettingsPane.allCases.count`;
     - `tableViewSelectionDidChange`, which calls `onSelect` unless the change was suppressed.
   - Add `func focus()`, which calls `table.window?.makeFirstResponder(table)`. Step 8 uses it.
   - `tableView(_:viewFor:row:)` reuses a cell through `makeView(withIdentifier:owner:)`.
     Otherwise it creates an `NSTableCellView`, adds an `NSImageView` and an
     `NSTextField(labelWithString:)` as subviews without constraints, assigns them to the cell's
     `imageView` and `textField`, and sets the cell's identifier. Configure the cell with
     `NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)` and
     `pane.title`. Set no fonts, colours, sizes or row views. The source-list style draws the
     selection and tints the template symbols.
3. `Sources/OddFrog/HotkeyRecorder.swift`: make it `final class HotkeyRecorder: NSButton`.
   - Delete `hotkey`, `conflict`, `rejected`, `intrinsicContentSize`, `focusRingMaskBounds`, the
     `focusRingType` override, `drawFocusRingMask`, `draw(_:)`, `becomeFirstResponder` and the
     `mouseDown` override.
   - Keep `onRecord`, `onRecordingChanged` and the private `recording` flag. Its `didSet` first
     sets `state = recording ? .on : .off`, before today's `guard recording != oldValue`, so the
     pressed look always matches the flag. Then it calls `onRecordingChanged` as today. The
     `needsDisplay` line goes.
   - `override init(frame:)` calls `super.init(frame:)`, `setButtonType(.pushOnPushOff)`, and
     sets `target = self` and `action = #selector(toggleRecording)`. `required init?(coder:)`
     returns `nil`.
   - Keep the `acceptsFirstResponder` override (`true`). A button otherwise takes focus only with
     Full Keyboard Access on.
   - `resignFirstResponder` sets `recording = false` and returns `super.resignFirstResponder()`.
   - `@objc private func toggleRecording()`: the stock click has already flipped `state`.
     - When `state == .on`: `window?.makeFirstResponder(self)`, then `recording = true`.
     - Otherwise: `cancelRecording()`.
   - `keyDown`: when not recording, Space (49) and Return (36) call `performClick(nil)`, which
     goes through the same toggle. Other keys go to `super`. The recording branch stays exactly
     as today, minus the `rejected = recorded` line.
   - `performKeyEquivalent` and `cancelRecording` keep their logic. `toggleRecording` replaces
     `startRecording`.

   The button's title is set from outside (step 4). Decision: the rejected-combination display
   moves into the model (step 5). Rejected alternative: keep `conflict`/`rejected` in the control
   and push them through the representable. That depends on the order in which SwiftUI delivers
   updates relative to the synchronous `onRecord` → `showHotkey` round trip.
4. Create `Sources/OddFrog/HotkeyRecorderView.swift`:
   `struct HotkeyRecorderView: NSViewRepresentable` with `let title: String`,
   `let onRecord: (Hotkey) -> Void` and `let onRecordingChanged: (Bool) -> Void`.
   - `makeNSView` returns `HotkeyRecorder()`.
   - `updateNSView` assigns both closures and sets `recorder.title = title` only when it differs.
5. Create `Sources/OddFrog/GeneralPaneModel.swift`:
   `@Observable @MainActor final class GeneralPaneModel`, importing `Foundation`,
   `Observation`, `OddFrogCore` and `ServiceManagement`.
   - State, each with `private(set)`:
     - `hotkey: Hotkey?`, `rejected: Hotkey?`, `hotkeyNote: String?`, `isRecording = false`;
     - `loginStatus = LoginItem.status` and `loginError: String?`.
   - `@ObservationIgnored private var lastRecorded: Hotkey?` and
     `@ObservationIgnored var onHotkey: ((Hotkey) -> Void)?`.
   - `var recorderTitle: String`: `"Type shortcut…"` while recording, otherwise
     `(rejected ?? hotkey)?.description ?? ""`.
   - `var isLoginOn: Bool`: `loginStatus` is `.enabled` or `.requiresApproval`.
   - `func show(_ hotkey: Hotkey, note: String?)` sets `hotkey`.
     - A non-empty `note` sets `hotkeyNote = note` and `rejected = lastRecorded`.
     - Otherwise it clears both.
   - `func record(_ hotkey: Hotkey)` stores `lastRecorded`, then calls `onHotkey`.
   - `func recordingChanged(_ recording: Bool)` sets `isRecording`. When recording starts it also
     clears `hotkeyNote` and `rejected`.
   - `func refreshLogin()` sets `loginStatus = LoginItem.status`.
   - `func toggleLogin()`:
     - Set `loginError = nil`, then call `try LoginItem.toggle()`. On a throw, set
       `loginError = error.localizedDescription`.
     - Call `refreshLogin()` now, and again after 0.3s through
       `DispatchQueue.main.asyncAfter` with `[weak self]` and `MainActor.assumeIsolated`, the
       same pattern as today.

     The error now stays visible until the next toggle.
   - `func openLoginItems()` calls `SMAppService.openSystemSettingsLoginItems()`.
6. Create `Sources/OddFrog/GeneralPaneView.swift`: `struct GeneralPaneView: View` with
   `let model: GeneralPaneModel`. The body is `Form { Section { … } }.formStyle(.grouped)`
   with three rows:
   - The keyboard shortcut row is a `LabeledContent`.
     - Content: `HotkeyRecorderView(title: model.recorderTitle, onRecord: { model.record($0) }, onRecordingChanged: { model.recordingChanged($0) })`
       with `.fixedSize()`.
     - Label: `Text("Keyboard shortcut")`, then one of three texts:
       - while recording: `Text("Press the keys you want to use.")`;
       - with a note: `Text(note + " Try another combination.").foregroundStyle(.red)`;
       - otherwise: `Text("Click, then press a new combination.")`.
   - The login row is a
     `Toggle(isOn: Binding(get: { model.isLoginOn }, set: { _ in model.toggleLogin() }))`.
     - Its label is `Text("Launch at login")`, then:
       - with a login error: `Text(error).foregroundStyle(.red)`;
       - otherwise, by `loginStatus`: the `.enabled` text; the `.requiresApproval` text with
         `.foregroundStyle(.orange)`; the `.notFound` text; nothing for the other states (a
         `switch` with `default: EmptyView()`).
     - Apply `.disabled(model.loginStatus == .notFound)`.
   - When `loginStatus == .requiresApproval`, add a third row:
     `Button("Open Login Items…") { model.openLoginItems() }`.

   Set no fonts, sizes, paddings or frames. Decision: SwiftUI's two-`Text` label supplies the
   System Settings title-plus-subtitle row that `SettingsLayout.settingRow` drew by hand.
7. `Sources/OddFrog/SettingsLayout.swift`: replace the body of `hairline()` so it returns an
   `NSBox` with `boxType = .separator` and `translatesAutoresizingMaskIntoConstraints = false`.
   Delete the 0.5pt container and its insets. Nothing else in the file changes. `Hairline` is
   deleted with `SettingsSidebar.swift`, and `PluginsPane` still calls `hairline()` until spec 47
   deletes the pane.
8. `Sources/OddFrog/SettingsWindowController.swift`:
   - Imports: add `SwiftUI` and remove `ServiceManagement`.
   - Delete these properties:
     - `sidebar: SettingsSidebar` and `paneTitle`;
     - `hotkeyRecorder`, `hotkeyHelper`, `loginSwitch`, `loginStatus`, `loginButton`;
     - `panes: [SettingsPane: NSView]`.

     Add these, each `private let`:
     - `splitController = NSSplitViewController()` and `sidebar = SettingsSidebarController()`;
     - `paneController = NSTabViewController()` and `general = GeneralPaneModel()`.
   - `init(icons:)`:
     - Build the window with the same content rect and style mask (keep `.fullSizeContentView`)
       and `isReleasedWhenClosed = false`.
     - Delete the `title`, `backgroundColor`, `titlebarAppearsTransparent`, `titleVisibility`,
       `titlebarSeparatorStyle`, toolbar and `toolbarStyle` lines.
     - `minSize` and `center()` move into `buildContent()`, after the content controller is set.
     - The `icons.observeLoads` block stays.
   - Rewrite `buildContent()`:
     - Start with `guard let window else { return }` instead of reading `contentView`.
     - Set `window.delegate = self`, which `windowDidResize` still needs.
     - Set `sidebar.onSelect = { [weak self] pane in self?.showPane(pane) }` and
       `general.onHotkey = { [weak self] hotkey in self?.onHotkey?(hotkey) }`.
     - Set `paneController.tabStyle = .unspecified`.
     - Add three children to `paneController` in `SettingsPane` order:
       1. an `NSHostingController(rootView: GeneralPaneView(model: general))` with
          `sizingOptions = []`;
       2. `hosted(makeItemsPane())`;
       3. `hosted(pluginsPane)`.
     - Create the sidebar item with `NSSplitViewItem(sidebarWithViewController: sidebar)` and set
       `canCollapse = false`. Add it, then add `NSSplitViewItem(viewController: paneController)`.
     - Set `window.contentViewController = splitController`.
     - Then call `window.setContentSize(NSSize(width: 760, height: 560))`, set
       `window.minSize = NSSize(width: 760, height: 560)`, call `window.center()`, and finally
       `showPane(.general)`.
   - Add `private func hosted(_ content: NSView) -> NSViewController`:
     - Create an `NSViewController` and give it a plain `NSView` as its view.
     - Add `content` with `translatesAutoresizingMaskIntoConstraints = false`, pinned on all four
       edges to that view's `layoutMarginsGuide`.

     The margins replace today's hand-set 20/52pt insets and keep the Items and Plugins views
     clear of the titlebar.
   - `showPane(_:)`, in this order:
     1. Keep the end-alias-edit line (`if currentPane == .items, pane != .items { endAliasEdit(commit: true) }`).
     2. Call `sidebar.focus()`. This ends any edit still open in the pane being left while that
        pane is still in the window: the recorder stops recording, and in spec 47 the Plugins text
        fields commit on focus loss. It also leaves the keyboard in the sidebar, which is where a
        stock sidebar keeps it after a click, so the selection stays accent-coloured and the arrow
        keys move between panes.
     3. Set `currentPane = pane`, `sidebar.selected = pane`,
        `paneController.selectedTabViewItemIndex = pane.rawValue` and `window?.title = pane.title`.
     4. Delete the `paneTitle` and `isHidden` lines. The tail becomes
        `guard pane == .items else { return }`, then `layoutColumns()` and
        `window?.makeFirstResponder(filterField)` as today. The old `makeFirstResponder(nil)` for
        the other panes goes away, because step 2 already placed the focus.
   - `showHotkey(_:note:)` becomes `general.show(hotkey, note: note)`.
   - In `present`, `refreshLogin()` becomes `general.refreshLogin()`. In its `else` branch, replace
     `window?.makeFirstResponder(currentPane == .items ? filterField : nil)` with
     `if currentPane == .items { window?.makeFirstResponder(filterField) } else { sidebar.focus() }`.
     The other lines of `present` stay.
   - Delete `refreshLogin()`, `makeGeneralPane()`, `toggleLogin()` and `openLoginItems()`.
   - Everything for the Items pane stays as it is: `makeItemsPane`, the table code,
     `layoutColumns`, `windowDidResize`, the alias editing and `ItemTable`.
9. Delete `Sources/OddFrog/SettingsSidebar.swift` and `Sources/OddFrog/IconTile.swift`.

Decisions recorded:
- Stock split view with a sidebar, not `NSTabViewController` toolbar tabs, because the app already
  uses a sidebar. Not a SwiftUI `NavigationSplitView` root either, because the Items table (⌘I
  jump, Return-to-edit, Esc-revert) and this controller's imperative API stay simpler in AppKit.
- `NSTabViewController(.unspecified)` swaps the detail content. Rejected alternatives: replacing
  the split item's view controller, which throws while the item is attached, and hand-toggling
  `isHidden`, which is today's approach.
- `canCollapse = false` on the sidebar. The window has no toolbar and no View-menu toggle, so a
  collapsed sidebar could only come back by dragging.
- Switching panes focuses the sidebar (except Items, which focuses its filter as today).
  Rejected alternative: today's `makeFirstResponder(nil)`, which would leave the stock sidebar
  selection grey right after a click, stop the arrow keys from moving between panes, and let a
  programmatic switch remove a pane while one of its fields is still being edited.
- `.fullSizeContentView` stays, so the sidebar gets the macOS 26 full-height layout
  (`allowsFullHeightLayout` applies only with it). The window has no toolbar, because the
  titlebar carries no items.
- The pane's model and view are named `GeneralPaneModel` and `GeneralPaneView`, so every pane
  follows one pattern: specs 47 and 48 add `PluginsPaneModel`, `PluginsPaneView` and
  `ItemsPaneController`.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners, no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and `if … { return … }` bodies where neighbouring code uses them, one type per file for new types, and no new package dependencies (Apple system frameworks such as SwiftUI and Observation are fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font, `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or hex colours and no custom fills (semantic system colours only), no corner radii, no `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins, system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding. Literal numbers are allowed only where AppKit has no system value (initial window content sizes, the launcher panel width and its glass corner radius) — the spec must list which literals remain.
- Literals that remain in the code this spec writes (the Items pane code and `PluginsPane.swift`,
  hosted unchanged, keep theirs until specs 48 and 47 replace them):
  - the window's initial content size and minimum size, 760×560 (as today);
  - the 0.3s login-status recheck delay;
  - the key codes in `HotkeyRecorder`.

  The only colours are SwiftUI `.red` for errors and `.orange` for the approval wait. They are the
  system red and orange that today's `systemRed`/`systemOrange` labels use.
- `AppDelegate.swift` does not change. Every member it uses on `settingsWindow` (listed in Context)
  keeps its name and signature.
- The Items pane (`makeItemsPane` and everything it uses) and `PluginsPane.swift` are hosted
  unchanged. Specs 47 and 48 restyle them.
- State lives in the `@Observable` model owned by the AppKit controller. No Combine, no
  `ObservableObject`, and no SwiftUI `@State` for anything AppKit pushes in.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
    else: do not start the app or a dev server, do not open a browser, do not take
    screenshots, do not write or run tests or scripts that are not listed in Plan, do not
    mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed)
- `ls Sources/OddFrog/SettingsSidebar.swift Sources/OddFrog/IconTile.swift 2>/dev/null` prints nothing
- `grep -rnw "SettingsSidebar\|SidebarRowView\|SidebarCellView\|IconTile\|Hairline" Sources` prints nothing
- `grep -n "titlebarAppearsTransparent\|titleVisibility\|titlebarSeparatorStyle\|NSToolbar\|toolbarStyle\|paneTitle\|window.backgroundColor\|loginSwitch\|hotkeyHelper" Sources/OddFrog/SettingsWindowController.swift` prints nothing
- `grep -n "draw\|focusRing\|intrinsicContentSize\|NSBezierPath\|NSShadow" Sources/OddFrog/HotkeyRecorder.swift` prints nothing

## Manual review
1. `make run`, then choose Settings… from the menu bar icon. The window has a normal titlebar that
   reads "General", with no toolbar and no heading inside the content.
2. The system sidebar lists General, Items and Plugins with outline gear, grid and puzzle-piece
   symbols. The selection is the stock accent sidebar highlight, and it turns grey when the window
   is inactive. Dragging the divider resizes the sidebar within the system range, and it cannot be
   collapsed.
3. Click Plugins: its highlight is accent-coloured. Press ↑: Items is selected, the filter field
   has focus, and the sidebar highlight turns grey. Click Plugins again. The title follows the
   selection each time. Both panes look as they did before this change and sit below the
   titlebar.
4. General is a grouped form with two rows:
   - "Keyboard shortcut", with the current shortcut on a standard button and the grey helper
     "Click, then press a new combination.";
   - "Launch at login", with a switch and its status line.
5. Click the shortcut button. It stays pressed and reads "Type shortcut…", and the helper reads
   "Press the keys you want to use.". Press ⌃⌥K. The button shows ⌃⌥K, the helper returns to
   grey, and the launcher now opens with ⌃⌥K.
6. Record a combination that is already taken. The button shows the rejected combination and the
   helper shows the error plus " Try another combination." in red. Click the button again: the
   red text disappears. Press Esc: the recording is cancelled and the previous shortcut shows.
7. Restore the original shortcut the same way.
8. With the app installed through `make install`, flip Launch at Login. The switch and the status
   text follow the state: "Odd Frog opens when you log in.", or the orange approval text plus an
   "Open Login Items…" button, which opens System Settings › Login Items.
9. From the launcher, press ⌘I on any item. Settings opens on Items with that row selected and its
   alias editor active, as before.
10. Run `printf '@settings plugins' > ~/Library/Logs/odd-frog-query.txt && pkill -USR2 -x OddFrog`.
    Settings switches to Plugins, and `~/Library/Logs/odd-frog-settings.window` holds a window
    number.

## Out of scope
- The Items pane and the Plugins pane: specs 48 and 47. The Manage Links sheet: spec 49.
  `GroupBox`, `SettingsLayout` (apart from `hairline()`), `AliasCellView`, `HoverRowView` and
  `SelectionPalette` stay for now.
- `NSApp.activate(ignoringOtherApps:)` in `present`.
- The status-menu Launch at Login item. It does not refresh an open Settings window, which is also
  true today.
- A View-menu "Show Sidebar" item, a window frame autosave, or a subtitle.
- The Items table's column widths. `layoutColumns()` still runs only on window resizes and pane
  switches, so a divider drag does not refit them until the next resize. Spec 48 replaces it with
  stock column autoresizing.
- `AppDelegate.swift`, `LoginItem.swift` and the menus.

## Open questions
none
