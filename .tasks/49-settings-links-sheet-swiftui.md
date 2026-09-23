# Task: The Manage Links sheet becomes a SwiftUI grouped form with a stock Table

## Goal
Manage Links is still a sheet on the Settings window with the same flow, but its content is
SwiftUI in an `NSHostingController`: a grouped `Form` with a "Links" section holding a stock
`Table` of links (Name, URL, Aliases) and the help text, and a "New link"/"Edit link" section with
Name, URL and Aliases fields and a red error footer. Below the form sit New Link, Delete (a
destructive button), Done (Esc) and Add Link/Save Changes (Return). Delete asks for confirmation
in a stock alert. Saving and deleting still go through the existing `onApply` closure into
`LinkEditor`, which is unchanged.

## Files
- Sources/OddFrog/LinkManagerController.swift        (modify — becomes the sheet host only)
- Sources/OddFrog/LinkManagerModel.swift             (create)
- Sources/OddFrog/LinkManagerView.swift              (create)
- Sources/OddFrogCore/Item.swift                     (modify — `CommandItem` conforms to `Identifiable`)
- Sources/OddFrogCore/LinkEditor.swift               (read — `LinkDraft`, `LinkDraft.command()`, `LinkEditError`; unchanged)
- Sources/OddFrogCore/URLTemplate.swift              (read — `URLTemplate.display(_:)`)
- Sources/OddFrogCore/Config.swift                   (read — `ConfigError.description`)
- Sources/OddFrog/SettingsWindowController.swift     (read — `manageLinks()`; unchanged)
- Sources/OddFrog/AppDelegate.swift                  (read — `applyLink(original:draft:)` behind `onApplyLink`; unchanged)

## Context
- Precondition: specs 46–48 have landed. `SettingsWindowController.manageLinks()` does these, in
  order:
  1. `guard let window`;
  2. `itemsPane.endEditing(commit: true)`;
  3. `linkManager.onApply = onApplyLink`;
  4. `linkManager.present(links: links, for: window)`.

  `linkManager` is `private let linkManager = LinkManagerController()`. The Settings window's
  content is an `NSSplitViewController`.
- `onApply` has type `(CommandItem?, LinkDraft?) throws -> [CommandItem]`. `AppDelegate` wires it
  to `applyLink(original:draft:)`, which calls `LinkEditor.save(to:original:draft:)` and reloads
  the config. For a deletion it also resets the item's override. It returns the new list of URL
  commands. Errors are `LinkEditError` (a `LocalizedError`) or `ConfigError` (whose
  `description` is the message).
- `CommandItem` (`Sources/OddFrogCore/Item.swift`) is `public struct CommandItem: Sendable, Hashable`
  with `public var id: String { "command:\(stableID)" }`. URL links have `action == .url(URL)`.
  Nothing declares `Identifiable` for it. SwiftUI `Table(_:selection:columns:)` needs
  `Identifiable` rows.
- `LinkManagerController` today is an `NSWindowController` around an `NSPanel` with styleMask
  `[.titled]`, content 580×490, `title = "Manage Links"` and `isReleasedWhenClosed = false`.
  Every item below needs a home in the new sheet:
  - `present(links:for:)` returns when the panel is already a sheet. Otherwise it stores the
    links, reloads, runs `newLink()`, calls `parent.beginSheet(panel)` and focuses Name.
  - The heading "Links" is 17pt semibold. The help text is "Web links open in your default
    browser. App links open in the app registered for that URL. Put {query} in a URL to insert
    what you type after the alias, for example gh odd-frog.".
  - "New Link" deselects the table, clears `original` and the three fields, and clears the error.
    It sets the editor heading to "New link" and the save button to "Add Link", disables Delete
    and focuses Name.
  - The table has columns Name, URL (`URLTemplate.display(url)`, middle-truncated) and Aliases
    (joined with ", "). Every cell's tooltip is its text. Selecting a row loads it: `original`
    becomes the link, the fields are filled, the heading becomes "Edit link", the save button
    becomes "Save Changes", Delete is enabled and the error is cleared. Deselecting leaves the
    editor as it is.
  - The fields are Name (placeholder "GitHub"), URL (placeholder
    "https://github.com or obsidian://open") and "Aliases (comma separated)" (placeholder
    "gh, github").
  - Save (key equivalent Return):
    1. Build `LinkDraft(name:url:aliases:)`, then `var saved = try draft.command()`, copying
       `original.stableID` when editing.
    2. `links = try onApply(original, draft)` and reload.
    3. Select, scroll to and load the row whose `id == saved.id`, then clear the error.
    4. On any throw, show `(error as? ConfigError)?.description ?? error.localizedDescription` in
       red.
  - Delete:
    - It is enabled only while editing. It opens an `NSAlert` sheet: "Delete “\(name)”?", with
      the text "This removes the link and its aliases from the launcher." and the buttons
      Delete and Cancel.
    - On Delete it runs `links = try onApply(original, nil)`, reloads and calls `newLink()`.
      Errors go to the red label.
  - "Done" (key equivalent Esc) calls `window.sheetParent?.endSheet(window)`.
  - Everything is laid out with literal 20/16/12/8pt constants, fixed 24pt field heights, a 110pt
    table and hand-set 11–17pt fonts.
- Facts about SwiftUI in this setup:
  - In a grouped `Form`, a `Table` with `.frame(height:)` inside a `Section` renders as a
    bordered list with its own header row and scrolls inside that height. Without a fixed height
    it grows with its rows and pushes the next section out of view.
  - Programmatic selection works through the `selection` binding. `ScrollViewReader.scrollTo`
    does not scroll a SwiftUI `Table`.
  - With `sizingOptions = []`, an `NSHostingController` does not resize its window. Assigning it
    as a window's `contentViewController` shrinks the window, so the content size is set again
    afterwards.
  - A string-literal `Text` or prompt is Markdown, so URLs in it render as links.
    `Text(verbatim:)` renders plain text.
  - SwiftUI evaluates `.defaultFocus($flag, true)` when the hosting window first shows the view
    hierarchy, and moves focus there.
  - `.keyboardShortcut(.defaultAction)` and `.cancelAction` map to Return and Esc.
  - `.alert(_:isPresented:actions:message:)` presents a sheet alert on the hosting window.
    `Button(role: .destructive)` gets the system's destructive treatment.

## Plan
1. `Sources/OddFrogCore/Item.swift`: change the declaration to
   `public struct CommandItem: Sendable, Hashable, Identifiable`. The existing `id` satisfies it,
   and nothing else changes. Decision: conform in the type's own module. Rejected alternatives: a
   `@retroactive` conformance in the app target, and a wrapper row type.
2. Create `Sources/OddFrog/LinkManagerModel.swift`:
   `@Observable @MainActor final class LinkManagerModel`, importing `Foundation`, `Observation`
   and `OddFrogCore`.
   - State:
     - `private(set) var links: [CommandItem] = []`;
     - `private(set) var selection: CommandItem.ID?` and `private(set) var original: CommandItem?`;
     - `var name = ""`, `var url = ""` and `var aliases = ""`;
     - `private(set) var error: String?`.
   - Callbacks:
     `@ObservationIgnored var onApply: ((CommandItem?, LinkDraft?) throws -> [CommandItem])?` and
     `@ObservationIgnored var onDone: (() -> Void)?`.
   - `func reset(links:)` stores the links and calls `newLink()`.
   - `func newLink()` sets `selection = nil` and `original = nil`, empties the three fields and
     clears `error`.
   - `func select(_ id: CommandItem.ID?)` sets `selection`. If no link has that ID it returns,
     which covers deselection. Otherwise it loads the link: `original`, `name`,
     `url = Self.address(of:)`, `aliases` joined with ", ", and clears `error`.
   - `func save()` and `func delete()` port `saveLink()` and the alert's Delete branch line for
     line. Both return early when `onApply` is `nil`, as today.
     - `save` builds the draft from `name`, `url` and `aliases`, copies `original.stableID` into
       `saved` when editing, and stores `links = try onApply(original, draft)`. It then calls
       `select(saved.id)` when the new list contains that ID, and sets `error = nil` on every
       successful path.
     - `delete` requires `original`. It stores `links = try onApply(original, nil)` and calls
       `newLink()`.
     - Both route errors into `error` through a private
       `static func describe(_ error: any Error) -> String` that returns
       `(error as? ConfigError)?.description ?? error.localizedDescription`.
   - `static func address(of link: CommandItem) -> String` returns `URLTemplate.display(url)` for
     `.url(url)` and `""` for anything else.
3. Create `Sources/OddFrog/LinkManagerView.swift`: `struct LinkManagerView: View` with
   `@Bindable var model: LinkManagerModel`, `@FocusState private var nameFocused: Bool` and
   `@State private var confirmingDelete = false`. The body is a `VStack(spacing: 0)` holding:
   - `Form { … }.formStyle(.grouped)` with two sections:
     1. The links section:
        - Content:
          `Table(model.links, selection: Binding(get: { model.selection }, set: { model.select($0) }))`
          with `.frame(height: 120)` and three `TableColumn`s: "Name", "URL" and "Aliases".
          - Each column uses the closure form and shows `Text(value)` with `.help(value)` for the
            tooltip.
          - URL uses `LinkManagerModel.address(of:)` and adds `.truncationMode(.middle)`.
          - Aliases uses `aliases.joined(separator: ", ")`.
        - Header: `Text("Links")`.
        - Footer: the help text, written with `Text(verbatim:)`.
     2. The editor section:
        - `TextField("Name", text: $model.name, prompt: Text("GitHub"))` with
          `.focused($nameFocused)`.
        - `TextField("URL", text: $model.url, prompt: Text(verbatim: "https://github.com or obsidian://open"))`.
        - `TextField("Aliases (comma separated)", text: $model.aliases, prompt: Text("gh, github"))`.
        - Header: `Text(model.original == nil ? "New link" : "Edit link")`.
        - Footer: `Text(error).foregroundStyle(.red)` when `model.error` is non-nil.
   - An `HStack` with `.padding()` (the default system padding), containing in order:
     - `Button("New Link")`, which calls `model.newLink()` and then sets `nameFocused = true`;
     - `Button("Delete", role: .destructive)`, which sets `confirmingDelete = true` and has
       `.disabled(model.original == nil)`;
     - `Spacer()`;
     - `Button("Done") { model.onDone?() }` with `.keyboardShortcut(.cancelAction)`;
     - `Button(model.original == nil ? "Add Link" : "Save Changes") { model.save() }` with
       `.keyboardShortcut(.defaultAction)`.
   - On the `VStack`:
     - `.defaultFocus($nameFocused, true)`;
     - `.alert("Delete “\(model.original?.name ?? "")”?", isPresented: $confirmingDelete)`. Its
       actions are `Button("Delete", role: .destructive)`, which calls `model.delete()` and then
       sets `nameFocused = true`, and `Button("Cancel", role: .cancel) {}`. Its message is
       `Text("This removes the link and its aliases from the launcher.")`.

   Set no fonts, sizes or colours other than the `.red` error and the frame height above.
4. `Sources/OddFrog/LinkManagerController.swift`: keep the class name, `var onApply`,
   `init()` and `present(links:for:)`, so `SettingsWindowController` compiles unchanged.
   - Add `import SwiftUI` and `private let model = LinkManagerModel()`.
   - `init()`:
     - Keep the `NSPanel` exactly as today: content rect 580×490, `[.titled]`, title "Manage Links",
       `isReleasedWhenClosed = false`.
     - Call `super.init(window:)`.
     - Set `model.onDone` to end the sheet (`window.sheetParent?.endSheet(window)`, with
       `[weak self]`).
   - `present(links:for:)`:
     1. Keep the `guard let window, window.sheetParent == nil else { return }`.
     2. Set `model.onApply = onApply` and call `model.reset(links: links)`.
     3. Create a fresh `NSHostingController(rootView: LinkManagerView(model: model))` with
        `sizingOptions = []`. Assign it to `window.contentViewController`, then call
        `window.setContentSize(NSSize(width: 580, height: 490))`.
     4. Call `parent.beginSheet(window)`.
   - Delete the table, fields, labels and buttons, `buildContent()`, `fieldBlock`, `newLink`,
     `saveLink`, `deleteLink`, `closeManager`, `loadSelection`, the `NSTableViewDataSource` and
     `NSTableViewDelegate` conformances, and their methods.

Decisions recorded:
- The existing `NSPanel` still hosts the sheet, which keeps today's size, guard and `endSheet`
  flow. Rejected alternative: `presentAsSheet` of the hosting controller, which would take the
  sheet's size from SwiftUI's ideal size.
- A fresh hosting controller is built for each presentation, so `.defaultFocus` puts the caret in
  Name every time the sheet opens. Rejected alternative: a model-driven focus request counter.
- The Table sits inside the form at a fixed height, so the editor stays visible however many
  links exist. The trade-off is that after Add Link the new row is selected but may be scrolled
  out of the 120pt list. The editor shows it, and SwiftUI offers no programmatic scroll for
  `Table`.
- A SwiftUI `.alert` replaces the `NSAlert`. The model never needs a window.
- The links list is a SwiftUI `Table`, because the whole sheet is SwiftUI and the list needs only
  single selection and tooltips. Rejected alternative: an AppKit `NSTableView` wrapped in
  `NSViewRepresentable` inside the form. The Items pane stays AppKit for a different reason: its
  in-place alias editing uses the table's field editor, which this list does not have.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners, no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and `if … { return … }` bodies where neighbouring code uses them, one type per file for new types, and no new package dependencies (Apple system frameworks such as SwiftUI and Observation are fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font, `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or hex colours and no custom fills (semantic system colours only), no corner radii, no `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins, system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding. Literal numbers are allowed only where AppKit has no system value (initial window content sizes, the launcher panel width and its glass corner radius) — the spec must list which literals remain.
- Literals that remain after this spec: the sheet's content size, 580×490 (as today), the links
  table height, 120pt, and `VStack(spacing: 0)`, which keeps the button row's default
  `.padding()` from stacking on top of the stack's default spacing. The only colour is SwiftUI
  `.red` for the error, which is `systemRed` today.
- `Sources/OddFrogCore/LinkEditor.swift`, `SettingsWindowController.swift` and `AppDelegate.swift`
  do not change. In `Item.swift`, only the `CommandItem` conformance list changes.
- Every user-visible string in Context stays word for word. Use `Text(verbatim:)` for literals
  that contain a URL or braces.
- State lives in the `@Observable` model owned by `LinkManagerController`. No Combine and no
  `ObservableObject`. `@State` is only for the alert flag.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
    else: do not start the app or a dev server, do not open a browser, do not take
    screenshots, do not write or run tests or scripts that are not listed in Plan, do not
    mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed; `LinkEditorTests` still pass unchanged)
- `grep -n "NSTableView\|NSTextField\|NSAlert\|systemFont\|fieldBlock\|heightAnchor" Sources/OddFrog/LinkManagerController.swift` prints nothing
- `grep -n "struct CommandItem: Sendable, Hashable, Identifiable" Sources/OddFrogCore/Item.swift` prints exactly one line
- `grep -n "font(\|systemFont\|foregroundColor\|Color(\|frame(width" Sources/OddFrog/LinkManagerView.swift Sources/OddFrog/LinkManagerModel.swift` prints nothing

## Manual review
1. `make run`, then open Settings › Plugins › Commands › Manage Links…. A sheet slides down with a
   "Links" section holding a bordered table (Name, URL, Aliases) of your URL commands and the help
   text below it. A "New link" section with Name, URL and "Aliases (comma separated)" fields
   follows. The caret is in Name.
2. Press Return with every field empty. "Enter a name for this link." appears in red under the
   fields.
3. Type `Docs`, `docs.example.com` and `d`, then press Return. The red text now reads "Enter a
   full URL, such as https://github.com or obsidian://open.", rendered as plain text.
4. Change the URL to `https://docs.example.com/{query}` and press Return. The row appears in the
   table and is selected, the section reads "Edit link", the button reads "Save Changes", and
   `config.toml` has a new `[[commands]]` block. In the launcher, `d foo` opens
   `https://docs.example.com/foo`.
5. Select another link: the fields load it. Edit its aliases and click Save Changes: the table
   updates.
6. Select Docs and click Delete. A stock alert asks "Delete “Docs”?", with the red-styled Delete
   and Cancel. Choose Delete: the row is gone and the editor is back to "New link".
7. Use an alias that another command already has: the config error appears in red and nothing is
   saved.
8. Press Esc, or click Done: the sheet closes. Open it again: the caret is back in an empty Name
   field.

## Out of scope
- `LinkEditor`, `LinkService`, and how `AppDelegate` saves links.
- The `links.manage@1` host service opens the sheet without refreshing `settingsWindow.links`
  first, so it can show a stale list. That fix belongs in `AppDelegate` and is a separate change.
- Sorting or searching links, and double-click to edit.
- The Settings window, the Items pane and the Plugins pane.

## Open questions
none
