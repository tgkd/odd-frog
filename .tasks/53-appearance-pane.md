# Task: Add an Appearance settings pane: Light/Dark override and a content font family + size

## Goal
Settings gets a new **Appearance** pane, placed between General and Items. It has three controls:
- **Appearance:** System / Light / Dark, applied to every Odd Frog window.
- **Font:** "System" or any installed font family.
- **Size:** a base text size from 10 to 24 pt, with a preview line.

The font and size apply to the text you search, read and write: the launcher query field, the
launcher result rows and empty-state line, the Notes document editor, and the chat transcript and
chat composer. They do not apply to the Settings window, the Items table or the month calendar.
Changes apply live, with no relaunch. They are stored in `settings.toml` under `[appearance]`.

## Files
- Sources/OddFrogCore/Settings.swift                    (modify)
- Tests/OddFrogCoreTests/AppearanceSettingsTests.swift  (create)
- Sources/OddFrog/ContentFont.swift                     (create)
- Sources/OddFrog/AppearancePaneModel.swift             (create)
- Sources/OddFrog/AppearancePaneView.swift              (create)
- Sources/OddFrog/SettingsPane.swift                    (modify)
- Sources/OddFrog/SettingsWindowController.swift        (modify)
- Sources/OddFrog/AppDelegate.swift                     (modify)
- Sources/OddFrog/SearchField.swift                     (modify)
- Sources/OddFrog/ResultRowView.swift                   (modify)
- Sources/OddFrog/LauncherViewController.swift          (modify)
- Sources/OddFrog/ChatMessageCell.swift                 (modify)
- Sources/OddFrog/ChatTranscriptView.swift              (modify)
- Sources/OddFrog/ChatWindowController.swift            (modify)
- Sources/OddFrog/DocumentWindowController.swift        (modify)
- Sources/OddFrog/GeneralPaneModel.swift                (read — `@Observable @MainActor` pane model pattern to mirror)
- Sources/OddFrog/GeneralPaneView.swift                 (read — grouped `Form` with two-line labels to mirror)
- Sources/OddFrog/PluginsPaneView.swift                 (read — `Picker` with a `Binding(get:set:)` pattern)
- Sources/OddFrog/ItemsPaneController.swift             (read — holds its own copy of `Settings`, see Context)
- Tests/OddFrogCoreTests/TerminalChoiceTests.swift      (read — Swift Testing file header to mirror)

## Context
- Swift 6.2 tools, macOS 26 deployment target, SwiftPM only (`Package.swift`). No Xcode project.
  The app target is `OddFrog` (`Sources/OddFrog`), the model target is `OddFrogCore`, and tests use
  Swift Testing (`import Testing`, `@Test`, `#expect`) with `@testable import OddFrogCore`.
- `OddFrogCore` imports no AppKit or SwiftUI. Keep it that way: the settings model lives in Core,
  and everything that touches `NSFont` or `NSApp` lives in the app target.
- **Settings model.** `Settings` (`Sources/OddFrogCore/Settings.swift`) is `Codable` and is decoded
  from TOML by TOMLKit. Each section is a nested struct with a hand-written `init(from:)` that
  falls back to defaults for missing keys. See `Settings.Window`: its `cascade_step` decodes as
  `Int` first, then as `Double`, because TOML `32` is an integer. `Settings` has a memberwise
  `init` with a default for every parameter. `MigrationTests.swift` calls it with labels, so a new
  parameter must go at the end with a default. Encoding uses the synthesized `encode(to:)` through
  `serialized()`. Synthesized encoding omits a `nil` optional.
- **Settings flow.** `AppDelegate.settings` has a `didSet` (`AppDelegate.swift`, near the top).
  `loadInitialSettings()` assigns it at launch, and `applySettings(_:persist:)` assigns it on every
  change. `applySettings` also saves the file when `persist` is true and marks it applied on
  `settingsWatcher`. A hand edit of `settings.toml` arrives through `reloadSettings(from:)` →
  `applySettings(_, persist: false)`. So the `didSet` sees every change, from launch, from the UI
  and from the file.
- **Stale-copy trap.** `ItemsPaneController` keeps its own `var settings: Settings`. Its
  `onChange` sends that whole copy back, and `AppDelegate` saves it. `SettingsWindowController`
  already has `update(pluginSettings:)` to keep the `plugins` field of that copy current. If the
  copy is not updated when appearance changes, editing an item alias afterwards writes the old
  `[appearance]` back and undoes the user's font change. `itemsPane.settings` is set in
  `SettingsWindowController.present(...)`.
- **Name clash.** Files that `import SwiftUI` must write `OddFrogCore.Settings`, because SwiftUI
  also declares a `Settings` type. `SettingsWindowController.swift` already does this.
- **Settings window.** `SettingsPane` is an `Int` enum. Its `rawValue` is both the sidebar row and
  the tab index (`paneController.selectedTabViewItemIndex = pane.rawValue`), so the order of the
  `case`s must match the order of `paneController.addChild(...)` in
  `SettingsWindowController.buildContent()`. Nothing persists a raw value. `AppDelegate.snapshotPanel()`
  finds panes by lowercased `title`. SwiftUI panes are hosted with
  `NSHostingController(rootView:)` and `sizingOptions = []`.
- **Current fonts on the in-scope surfaces:**
  - `SearchField.init`: `NSFont.preferredFont(forTextStyle: .title2)`.
  - `ResultRowView.init`: `titleLabel` `.body`; `subtitleLabel`, `valueLabel`,
    `requirementLabel` and `kindLabel` `.subheadline`. `configure(title:detail:value:tooltip:kind:requirement:icon:)`
    only sets strings, images and visibility. The icon (`iconSide`, symbol configuration) stays as is.
  - `LauncherViewController.emptyLabel`: no font set, so it is the default system 13 pt.
  - `ChatMessageCell.init`: `speaker` `.headline`; `body` (a wrapping label) has no font set.
    `show(_:speaker:waiting:)` only sets strings and visibility.
  - `ChatWindowController.input`: an `NSTextField(string:)` with no font set.
  - `DocumentWindowController.buildContent()`: `textView.font = NSFont.preferredFont(forTextStyle: .body)`.
    The text view comes from `NSTextView.scrollablePlainDocumentContentTextView()` and is plain
    text. Measured on this SDK: setting `font` on it restyles all existing text, does not post
    `textDidChange` (so it does not mark the document dirty or trigger autosave) and registers no undo.
- **Measured text-style sizes on this SDK:** body 13, title2 17, subheadline 11, headline 13
  (bold). `NSFont(descriptor: f.fontDescriptor, size: s)` resizes a text-style font and keeps its
  weight. `NSFontManager.shared.convert(font, toFamily: name)` keeps bold for families that have
  it (`Menlo-Bold`, `Georgia-Bold`). For an unknown family it returns the font unchanged, which
  gives a free fallback to the system font. `NSFontManager.shared.availableFontFamilies` lists
  about 300 families, none starting with `.`.
- **Row heights.** The launcher table measures rows with `heightOfRow`: it runs
  `configure(prototype, …)` and returns `prototype.fittingSize.height`. `refresh(keepSelection:)`
  calls `tableView.reloadData()`, which asks for every row height again, and then
  `onHeightChange`. `preferredHeight` is `contentStack.fittingSize.height`, so it follows the query
  field's font. `prepareForShow()` calls `refresh()` every time the panel opens.
- **Chat reloads.** The chat transcript uses `usesAutomaticRowHeights = true`.
  `ChatTranscriptView.render(...)` reloads only rows whose text changed, so a font change needs its
  own full reload. `isNearBottom()` and `scrollToBottom()` already exist there. The table is
  flipped, so `rect(ofRow:).minY` is a row's top edge.
- **Cell reuse.** `NSTableView` reuses cells through `makeView(withIdentifier:owner:)`, and there
  is no API to empty its reuse pool. A cell must therefore check the current content font when it
  is configured, not only when it is created.
- `NSApp.appearance = nil` follows the system. `NSAppearance(named: .aqua)` and `.darkAqua` force
  Light and Dark. The launcher's `NSGlassEffectView` and every other window follow `NSApp.appearance`.
- `NSImage(systemSymbolName: "circle.lefthalf.filled", …)` exists on this SDK.
- `Text(...).font(Font(nsFont as CTFont))` compiles on this SDK.

## Plan
1. **`Settings.Appearance` in `Sources/OddFrogCore/Settings.swift`.** Add a nested
   `public struct Appearance: Codable, Sendable, Equatable` next to `Window`, with:
   - `public enum Theme: String, Codable, Sendable, CaseIterable { case system, light, dark }`
   - `public static let defaultSize: Double = 13` and `public static let sizeRange: ClosedRange<Double> = 10...24`
   - `public var theme: Theme`, `public var fontFamily: String?` (`nil` means the system font),
     `public var fontSize: Double`
   - `public init(theme: Theme = .system, fontFamily: String? = nil, fontSize: Double = Appearance.defaultSize)`.
     It stores `fontFamily` trimmed of whitespace, with an empty result becoming `nil`, and
     `fontSize` clamped into `sizeRange`.
   - `CodingKeys`: `theme`, `fontFamily = "font_family"`, `fontSize = "font_size"`.
   - `init(from:)`: decode `theme` as an optional `String` and map it with `Theme(rawValue:)`.
     A missing or unknown value becomes `.system`. An unknown value must not fail the whole
     settings file, because the user may be editing it by hand. Decode `font_family` as an
     optional `String`. Decode `font_size` like `cascade_step`: `Int` first, then `Double`,
     defaulting to `defaultSize`. Then call the memberwise `init` so trimming and clamping apply
     in both paths.
   Add `public var appearance: Appearance` to `Settings`, with `case appearance` in its
   `CodingKeys`, `decodeIfPresent(...) ?? Appearance()` in `init(from:)`, and an
   `appearance: Appearance = Appearance()` parameter at the end of the memberwise `init`.
2. **`Tests/OddFrogCoreTests/AppearanceSettingsTests.swift`.** Use the same header as
   `TerminalChoiceTests.swift`. Add `@Test`s for:
   - a file with no `[appearance]` table gives `Appearance()`
   - `theme = "dark"`, `font_family = "Menlo"`, `font_size = 15` parse into those values
   - `font_size = 30` clamps to 24 and `font_size = 4` clamps to 10
   - `font_size = 14.5` is accepted
   - `theme = "neon"` gives `.system` without throwing
   - `font_family = "  "` gives `nil`
   - a `Settings` with a non-default `Appearance` survives `Settings.parse(settings.serialized())`
     unchanged
   - a default `Appearance` round-trips with no `font_family` key in the serialized text
3. **`Sources/OddFrog/ContentFont.swift`.** Add a `@MainActor struct ContentFont: Equatable` with
   `var family: String?` and `var size: CGFloat`, and:
   - `static var current = ContentFont(family: nil, size: CGFloat(Settings.Appearance.defaultSize))`
   - `init(family:size:)`, and `init(_ appearance: Settings.Appearance)`
   - `func font(_ style: NSFont.TextStyle) -> NSFont`. Take the preferred font for `style`. Scale
     its point size by `size / NSFont.preferredFont(forTextStyle: .body).pointSize` and round to a
     whole point. Build the resized font with `NSFont(descriptor:size:)`. If `family` is set, pass
     the result through `NSFontManager.shared.convert(_:toFamily:)`.

   The result is that the default settings reproduce today's fonts exactly, and the title / detail
   / headline hierarchy and weights survive any family or size.
4. **Launcher surfaces.**
   - `SearchField.init`: use `ContentFont.current.font(.title2)`.
   - `ResultRowView`: move the five label font assignments out of `init` into a private
     `applyFonts()`. It records the `ContentFont` it applied in a private stored property and does
     nothing when that equals `ContentFont.current`. Call it from `init` and at the start of
     `configure(...)`. Every reused cell and the height prototype then pick up a new font the next
     time they are configured.
   - `LauncherViewController`: set `emptyLabel.font = ContentFont.current.font(.body)` in
     `loadView()`. Add `func applyContentFont()`. It sets `searchField.font` (`.title2`) and
     `emptyLabel.font` (`.body`) from `ContentFont.current`, then calls
     `refresh(keepSelection: true)`, which already guards `isViewLoaded`, reloads, re-measures
     rows and reports the new height.
5. **Chat surfaces.**
   - `ChatMessageCell`: set `body.font` as well as `speaker.font` (`.headline` / `.body` from
     `ContentFont.current`). Use the same record-and-skip `applyFonts()` as `ResultRowView`, called
     from `init` and at the start of `show(...)`.
   - `ChatTranscriptView`: add `func reloadAll()`. Record `isNearBottom()`, and record the row at
     the top of `scroll.contentView.documentVisibleRect`. Call `table.reloadData()`, then
     `noteHeightOfRows(withIndexesChanged:)` for all rows, then `layoutSubtreeIfNeeded()`. If it
     was near the bottom, call `scrollToBottom()`. Otherwise scroll the clip view so the recorded
     row's `rect(ofRow:).minY` is at the top again, then call `reflectScrolledClipView`. Do nothing
     beyond the reload when there are no rows.
   - `ChatWindowController`: in `buildContent()` set `input.font = ContentFont.current.font(.body)`.
     Add `func applyContentFont()`, which sets `input.font` the same way and calls
     `transcript.reloadAll()`.
6. **Document editor.** In `DocumentWindowController.buildContent()` use
   `ContentFont.current.font(.body)`. Add `func applyContentFont()`, which sets `textView.font` the
   same way.
7. **`AppearancePaneModel.swift`.** An `@Observable @MainActor final class` that mirrors
   `GeneralPaneModel`. It has:
   - `private(set) var appearance = OddFrogCore.Settings.Appearance()` and
     `@ObservationIgnored var onChange: ((OddFrogCore.Settings.Appearance) -> Void)?`
   - `let families: [String]`, filled once in `init` from
     `NSFontManager.shared.availableFontFamilies`, sorted with `localizedStandardCompare`
   - `func show(_ appearance:)`, which assigns only when the value differs
   - `var selectedFamily: String?`, which returns `appearance.fontFamily` only when it is in
     `families`, and `nil` otherwise. A family that is no longer installed then shows as "System",
     which is what actually renders.
   - `setTheme(_:)`, `setFamily(_:)` and `setSize(_:)`. Each builds a new `Appearance` through its
     memberwise `init`, so size clamping applies. If the result differs, it assigns it and calls
     `onChange`.
   - `var previewFont: NSFont`, which returns `ContentFont(appearance).font(.body)`
8. **`AppearancePaneView.swift`.** A SwiftUI `Form` with `.formStyle(.grouped)`, mirroring
   `GeneralPaneView`:
   - Section 1: `Picker` labelled "Appearance" with System / Light / Dark tagged by `Theme`, bound
     with `Binding(get:set:)` to the model.
   - Section 2, row 1: `Picker` whose label is `Text("Font")` over `Text("Used in the launcher,
     notes and chat.")`. Its first item is `Text("System").tag(String?.none)`, then a `Divider()`,
     then `ForEach(model.families)` with `Text(family).tag(Optional(family))`, bound to
     `model.selectedFamily` / `setFamily`.
   - Section 2, row 2: `LabeledContent("Size")` containing an `HStack` with `Text("\(size) pt")`
     (whole number when integral, `.monospacedDigit()`) and a `Stepper` with its label hidden,
     over `Settings.Appearance.sizeRange` in steps of 1, bound to `setSize`.
   - Section 2, row 3: the preview line `Text("Find apps, run commands, take notes.")` in
     `.font(Font(model.previewFont as CTFont))`.
9. **Settings window wiring.**
   - `SettingsPane`: add `case appearance` directly after `general`, with title `"Appearance"` and
     symbol `"circle.lefthalf.filled"`.
   - `SettingsWindowController`:
     - add `private let appearancePane = AppearancePaneModel()` and
       `var onAppearance: ((OddFrogCore.Settings.Appearance) -> Void)?`
     - in `buildContent()`, forward `appearancePane.onChange` to `onAppearance`, and add its
       `NSHostingController` (with `sizingOptions = []`) as the second tab child, between the
       General host and `itemsPane`
     - in `present(...)`, call `appearancePane.show(settings.appearance)`
     - add `func update(appearance:)`, which sets `itemsPane.settings.appearance` and calls
       `appearancePane.show(appearance)`
10. **`AppDelegate`.**
    - In `wirePanel()`, set `settingsWindow.onAppearance` to copy `settings`, replace its
      `appearance` and call `applySettings(updated, persist: true)`, the same way
      `pluginsPane.onToggle` builds `updated`.
    - In the `settings` `didSet`, when `settings.appearance != oldValue.appearance`, call a new
      private `applyAppearance()`. It:
      - sets `NSApp.appearance` (`nil` for `.system`, `NSAppearance(named: .aqua)` for `.light`,
        `NSAppearance(named: .darkAqua)` for `.dark`)
      - sets `ContentFont.current = ContentFont(settings.appearance)`
      - calls `controller.applyContentFont()`, `chats.applyContentFont()` and
        `documents.applyContentFont()`
      - calls `settingsWindow.update(appearance: settings.appearance)`

    This one path covers launch, UI changes and hand edits of `settings.toml`. With default
    settings the `didSet` sees no change at launch and nothing runs.

## Constraints
- Write no code comments of any kind: no `//`, no `///` doc comments, no `/* */`, no MARK lines, in
  any file, including tests. If a line needs explaining, rename or restructure it.
- Single-statement bodies are still braced on their own: `if x { return }`, never `if x return`
  (Swift requires braces anyway, but do not squeeze bodies onto one line with `;`).
- Match the surrounding code:
  - `@MainActor` on app-target types
  - `@Observable` pane models with `@ObservationIgnored` callbacks
  - `Binding(get:set:)` rather than `$` bindings into models
  - `private(set)` for model state
  - no new dependencies
- Use stock controls only. No custom drawing, colours, gradients or shadows. The Settings window
  keeps system fonts. The only non-system font in it is the preview line.
- Keep `OddFrogCore` free of AppKit and SwiftUI imports.
- Surgical changes only; do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the existing
  `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift` `nonisolated(unsafe)` one
- `swift test` passes

## Manual review
Build and launch with `make run`.
1. Open Settings. The sidebar reads General, Appearance, Items, Plugins. Each pane still opens the
   right content, which checks the tab index shift.
2. **Light/Dark.**
   - Appearance → Dark: Settings, the launcher glass, Notes and Chat all turn dark even while
     macOS is in Light.
   - Light forces light.
   - System follows System Settings › Appearance again.
3. **Family and size.**
   - Set Font to Menlo and Size to 18. Open the launcher and type a query. The query line, titles
     and detail lines are all Menlo. Titles are larger than details and the query is larger than
     titles. Rows are taller and nothing clips. The panel grows downward from a fixed top.
   - Type a query with no matches: the "No results for …" line uses the new font.
   - Set Size to 10: rows shrink and the panel height follows.
4. **Notes.** Open a Notes document with some text. Change the size in Settings. The editor text
   restyles immediately, and the window subtitle shows no unsaved or error state from the font
   change alone.
5. **Chat.**
   - Open Chat with a few messages. Change the size. The transcript rows and the composer text
     restyle, and row heights re-wrap with no overlap.
   - Scrolled to the bottom: it stays at the bottom.
   - Scrolled up: the same message stays at the top.
6. The Settings window's own labels, the Items table and the month view keep system fonts.
7. **Stale-copy check.** Change the font, then edit an alias in Settings › Items. Reopen
   `~/.config/odd-frog/v2/settings.toml`.
   `[appearance]` still holds the new font.
8. **Hand edits.** Edit `settings.toml` by hand to `font_family = "Georgia"`: the launcher picks it
   up without a relaunch. `font_family = "NoSuchFont"` renders the system font, and the picker
   shows System.

## Out of scope
- Fonts in the Settings window, the Items table, the Links sheet and the month calendar view.
- Colour themes, accent colours or any custom selection drawing.
- Launcher width, position and number of visible rows. Launcher position is spec 54.
- Result icons and their size.
- Per-surface fonts (a different font for chat than for the editor).

## Open questions
none
