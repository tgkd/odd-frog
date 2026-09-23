# Task: Settings › Items becomes a stock inset table in its own view controller, and the last hand-drawn Settings helpers are deleted

## Goal
The Items pane moves out of `SettingsWindowController` into `ItemsPaneController`. It becomes a
stock `.inset` `NSTableView` with stock row selection, no hover, and plain `NSTableCellView`
cells. The columns are Show in launcher (checkbox), Item (icon + title), Kind, Built-in Aliases
(read-only) and Aliases, which the table's own field editor edits. Filtering, the empty message,
⌘I jump-to-item, click and Return to edit, Return to save and Esc to revert behave as today.
`AliasCellView`, `HoverRowView`, `GroupBox`, `SelectionPalette` and `SettingsLayout` are deleted.

## Files
- Sources/OddFrog/ItemsPaneController.swift          (create)
- Sources/OddFrog/SettingsWindowController.swift     (modify)
- Sources/OddFrog/AliasCellView.swift                (delete)
- Sources/OddFrog/HoverRowView.swift                 (delete)
- Sources/OddFrog/GroupBox.swift                     (delete)
- Sources/OddFrog/SelectionPalette.swift             (delete)
- Sources/OddFrog/SettingsLayout.swift               (delete)
- Sources/OddFrog/IconCache.swift                    (read — `icon(for:size:)`, `observeLoads(_:)`)
- Sources/OddFrog/AppDelegate.swift                  (read — `present(…focusing:)` from ⌘I, `update(items:)`, `onChange`; stays unchanged)
- Sources/OddFrogCore/Settings.swift                 (read — `ItemOverride`, `override(for:)`, `setOverride(_:)`)
- Sources/OddFrogCore/Item.swift                     (read — `LauncherItem.id/title/aliases/kindLabel`)

## Context
- Preconditions:
  - Spec 44 removed every `SelectionPalette` use from the launcher files. Specs 46 and 47 removed
    `SettingsSidebar.swift` and `PluginsPane.swift`.
  - What remains of the types deleted here is used only by the Items code in
    `SettingsWindowController.swift` and by each other:
    - `SettingsLayout.helper(_:)`: `itemsHelper` and `itemsEmptyLabel`. The other
      `SettingsLayout` functions have no callers.
    - `GroupBox`: the frame around the items table, and `SettingsLayout.groupedBox`.
    - `HoverRowView`: `tableView(_:rowViewForRow:)`.
    - `AliasCellView`: the Aliases column.
    - `SelectionPalette`: `AliasCellView` and `HoverRowView`.
- Shape of `SettingsWindowController` after specs 46 and 47:
  - It is an `NSWindowController` that conforms to `NSTableViewDataSource`, `NSTableViewDelegate`,
    `NSSearchFieldDelegate` and `NSWindowDelegate`.
  - The window content is `splitController`. `sidebar` is a `SettingsSidebarController`.
  - `paneController` is an `NSTabViewController` with three children, in `SettingsPane` order:
    the General hosting controller, `hosted(makeItemsPane())` and the Plugins hosting controller.
    `hosted(_:)` pins a view to a plain view controller's layout margins, and the Items pane is
    its only caller.
  - `general` is the `GeneralPaneModel` and `pluginsPane` is the `PluginsPaneModel`.
  - `showPane(_:)` does the following in order:
    1. `endAliasEdit(commit: true)` when leaving Items;
    2. `sidebar.focus()`, which makes the sidebar table first responder and so ends any edit in
       the pane being left while it is still in the window;
    3. sets `currentPane`, `sidebar.selected`, `paneController.selectedTabViewItemIndex` and
       `window?.title`;
    4. then `guard pane == .items else { return }`, `layoutColumns()` and the filter field as
       first responder.
  - `present`'s last branch ends with
    `if currentPane == .items { window?.makeFirstResponder(filterField) } else { sidebar.focus() }`.
  - `NSTabViewController` loads a child's view the first time that tab is selected. `present` can
    therefore reach the Items code before the Items view has ever loaded.
  - `present(settings:items:hotkey:focusing:)`, `update(items:)`, `update(pluginSettings:)`
    (sets `settings.plugins`), `select(_:)` and `manageLinks()` (calls
    `endAliasEdit(commit: true)`, then presents the link manager) are called by `AppDelegate`.
    `private(set) var settings` is read by nothing outside the class.
- Items pane behaviour today. Every item needs a home in the new controller:
  - The filter is an `NSSearchField` with placeholder "Filter". Every text change runs
    `applyFilter()`:
    1. It drops any alias edit without saving.
    2. It trims the query and matches, case-insensitively, the title, any built-in alias, or
       `kindLabel ?? "App"`.
    3. It reloads the table.
    4. When nothing matches a non-empty query it shows "No items match “\(raw)”." centred over
       the list.
  - `present(…, focusing: id)` sets the filter to the target item's title (or empty) and applies
    it.
    - If the target is visible: it switches to Items, selects and scrolls to the row, makes the
      table first responder and starts editing that row's aliases. This is the ⌘I jump from the
      launcher.
    - Otherwise, when Items is the current pane, it focuses the filter.
  - `update(items:)` returns early when the items are unchanged. Otherwise it stores them and
    re-applies the filter.
  - Columns are an unlabelled checkbox column (header tooltip "Show in launcher"), "Item",
    "Kind" and "Aliases" (header tooltip "Comma separated. Built-in aliases from config are
    kept.").
    - A manual `layoutColumns()` splits the width 2:1.4 on every resize.
    - Rows are 36pt with no intercell spacing, a clear background, `.plain` style and a
      `HoverRowView`, and the table sits inside a `GroupBox`.
  - Checkbox:
    - Its state is `override?.enabled ?? true`.
    - Toggling writes `ItemOverride.enabled` through `settings.setOverride`, calls
      `onChange(settings)` and reloads that row's Item cell.
  - Item column:
    - It shows `icons.icon(for: item, size: 20)` in a 20pt image view, with the title after it.
    - When the item is disabled, the icon alpha is 0.45 and the title uses
      `secondaryLabelColor`.
    - `icons.observeLoads` reloads the Item column for every visible row when an app icon
      finishes loading.
  - Kind column: `kindLabel ?? "App"`, in `secondaryLabelColor`, or `tertiaryLabelColor` when
    disabled.
  - Aliases column:
    - `AliasCellView` shows the built-in aliases (`item.aliases` minus the custom ones) in grey,
      followed by the custom ones (`settings.override(for:)?.aliases`).
    - It shows "Add alias" only on hover or selection.
    - Editing swaps in a hidden bezeled text field.
      - Editing starts on a click in the Aliases column (the table action checks
        `clickedColumn`), on Return or keypad Enter (key codes 36/76) through the `ItemTable`
        subclass, and from ⌘I.
      - Return or leaving the field saves. Esc reverts and hands focus back to the table.
      - Saving normalises with `AliasCellView.normalized` (split on commas, trim, lowercase, drop
        empties), writes `ItemOverride.aliases`, calls `onChange(settings)` and redraws the cell.
  - Leaving the Items pane and opening Manage Links both save an alias edit that is in progress.
  - The helper under the list reads "Grey aliases are built in. Click a cell to add your own;
    Return saves.". That describes the old rendering and must change.
- `applySettings` in `AppDelegate` ends in `rebuildItems()`. That calls
  `settingsWindow.update(items: plugins.catalogItems)` while the window is visible. The catalog
  items do not include overrides, so saving an alias or a checkbox does not change them, and
  `update(items:)` returns early.
- Facts about the stock pieces used below:
  - An `.inset` table keeps its stock row height of 24pt on macOS 26 whatever `rowSizeStyle` is.
    With a non-custom `rowSizeStyle`, the cell places its `imageView` at 22–28pt. That spills out
    of a 24pt row, so this table keeps the default `.custom` row size style and positions its
    outlets with constraints.
  - `IconCache.icon(for:size:)` draws app icons and emoji at the requested size, but returns SF
    Symbol images and image files (a plugin item's `icon` path) at their own size. An
    `NSImageView` with no size constraints takes its image's size: measured, a 512pt image gives
    a 512pt image view in a 24pt row.
  - `.uniformColumnAutoresizingStyle` (measured): when the starting widths fit in the clip view,
    it grows and later shrinks the resizable columns with the clip view, adding or removing the
    same amount from each. When the starting widths already exceed the clip view, it leaves them
    alone and the table scrolls sideways. The table follows its scroll view, so a sidebar divider
    drag refits the columns just like a window resize.
  - In a view-based table, `editColumn(_:row:with:select:)` makes the cell's view first
    responder, which starts editing an editable `NSTextField`. It does not select the row.
  - `NSTextField(labelWithString:)` with `isEditable = true` is the stock editable table-cell
    field: no bezel, and the field editor appears in place. It draws `placeholderString` when
    empty, even when not editing.
  - `NSControl.abortEditing()` throws away the typed text, so the field keeps its previous
    `stringValue`. It still sends `controlTextDidEndEditing`, synchronously, and the field carries
    that previous value.
  - While a text field is being edited, `window.firstResponder` is the shared field editor, an
    `NSTextView` with `isFieldEditor == true` whose `delegate` is the text field.

## Plan
1. Create `Sources/OddFrog/ItemsPaneController.swift`:
   `@MainActor final class ItemsPaneController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate`,
   importing `AppKit` and `OddFrogCore`.
   - A private nested `enum Column` holds identifiers `enabled`, `name`, `kind`, `builtin` and
     `aliases`, and `private static let iconSize: CGFloat = 16` is the Item column's icon size.
   - Public state:
     - `var settings = Settings.empty`;
     - `var onChange: ((Settings) -> Void)?`.
   - Private state:
     - `icons: IconCache`, `table = ItemTable()`, `filterField = NSSearchField()` and
       `emptyLabel = NSTextField(labelWithString: "")`;
     - `allItems` and `visibleItems`.
   - `init(icons:)` calls `super.init(nibName: nil, bundle: nil)`. It then configures the filter
     field (`placeholderString = "Filter"`, `delegate = self`), the empty label
     (`textColor = .secondaryLabelColor`, hidden), and the table and its columns as described
     below, and registers `icons.observeLoads`. The handler returns unless
     `table.window?.isVisible == true` and there are visible rows. It then reloads the Item column
     for all visible rows, as today. `required init?(coder:)` returns `nil`.

     Decision: configure these in `init`, not in `loadView`, so `show(items:revealing:)` and
     `update(items:)` work before the tab first loads the view (Context). The same pattern is in
     `SettingsSidebarController`.
   - `loadView()` only builds the layout:
     - Build a root `NSView`, then an `NSScrollView` with the table as its document view,
       `hasVerticalScroller = true` and `autohidesScrollers = true`.
     - Add a helper label, `NSTextField(wrappingLabelWithString: "Click an Aliases cell or press Return to add your own aliases, separated by commas. Return saves, Esc cancels.")`,
       with `font = .preferredFont(forTextStyle: .subheadline)` and
       `textColor = .secondaryLabelColor`.
     - Pin the filter field, scroll view and helper, top to bottom, to the root's
       `layoutMarginsGuide`. Use `constraint(equalToSystemSpacingBelow:multiplier: 1)` between
       them and full width on the leading and trailing margins. Add the empty label after the
       scroll view and centre it on the scroll view.
     - Set no fonts or sizes on the filter field.
   - Table:
     - `style = .inset` and `columnAutoresizingStyle = .uniformColumnAutoresizingStyle`.
     - `dataSource`/`delegate = self`, `target = self` and `action = #selector(tableClicked)`.
     - `table.onReturn` calls `beginEditing(row: table.selectedRow)`.
     - Do not set `rowHeight`, `intercellSpacing`, `backgroundColor`,
       `usesAlternatingRowBackgroundColors` or `rowSizeStyle`, and add no row views.
   - Columns:
     - `enabled`: empty title and header tooltip "Show in launcher". Its `width`, `minWidth` and
       `maxWidth` all equal
       `NSButton(checkboxWithTitle: "", target: nil, action: nil).fittingSize.width`, and
       `resizingMask = []`.
     - `name` "Item", width 160.
     - `kind` "Kind", width 60.
     - `builtin` "Built-in Aliases", width 90.
     - `aliases` "Aliases", width 90, header tooltip "Comma separated. Built-in aliases from
       config are kept.".

     The four text columns keep the default resizing mask. Their widths are starting widths that
     the uniform autoresizing grows to fill the list. They start small because that style only
     takes over when the columns start narrower than the list.
   - Cells come from `tableView(_:viewFor:row:)`. It reuses a cell by identifier through
     `makeView(withIdentifier:owner:)`, or builds one with a private `makeCell(_:)`, then calls a
     private `configure(_:column:row:)`.
     - `makeCell(_:)`:
       - `enabled`: an `NSTableCellView` holding
         `NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))`
         with `toolTip = "Show in launcher"`, centred with centre-X and centre-Y constraints. This
         is today's code.
       - Every other column: an `NSTableCellView` whose `textField` is
         `NSTextField(labelWithString: "")` with `lineBreakMode = .byTruncatingTail`.
         - The field is pinned leading to the cell and trailing with
           `lessThanOrEqualTo: cell.trailingAnchor`, and centred vertically.
         - In `name` the leading edge is `equalToSystemSpacingAfter:` an `NSImageView`, which is
           the cell's `imageView`. That image view is pinned to the cell's leading edge, centred
           vertically, and given width and height constraints equal to `Self.iconSize`. Its
           default `imageScaling` (`.scaleProportionallyDown`) fits larger images into that slot.
         - In `aliases` the field also gets `isEditable = true`, `usesSingleLineMode = true`,
           `placeholderString = "Add alias"` and `delegate = self`.
     - `configure(_:column:row:)`:
       - `enabled`: checkbox state from `override?.enabled ?? true`.
       - `name`: `icons.icon(for: item, size: Self.iconSize)`, the title, and `labelColor`, or
         `secondaryLabelColor` when disabled. There is no alpha on the icon.
       - `kind`: `kindLabel ?? "App"`, in `secondaryLabelColor`, or `tertiaryLabelColor` when
         disabled.
       - `builtin`: `item.aliases.filter { !custom.contains($0) }.joined(separator: ", ")`, in
         `secondaryLabelColor`.
       - `aliases`: `custom.joined(separator: ", ")`.
   - `@objc private func toggleEnabled(_ sender: NSButton)`:
     - Take the row from `table.row(for: sender)`, not the tag.
     - Update and save the override as today, call `onChange?(settings)`, then
       `reloadData(forRowIndexes:columnIndexes:)` for that row's `name` and `kind` columns.
   - Filtering:
     - `controlTextDidChange` runs `applyFilter()` when the object is `filterField`.
     - `applyFilter()` is today's method: `endEditing(commit: false)` first, then the same
       predicate, `reloadData()` and the empty label.
   - Editing:
     - `private static func normalized(_ text: String) -> [String]` moves over from
       `AliasCellView` unchanged: split on `","`, trim `.whitespaces`, lowercase, and drop empty
       parts.
     - `private var editedAliasField: NSTextField?` returns the text field when
       `table.window?.firstResponder` is an `NSTextView` with `isFieldEditor`, and its `delegate`
       is an `NSTextField` that `isDescendant(of: table)`. Otherwise it returns `nil`. It reads
       `table.window`, not `view.window`, so it never forces the view to load.
     - `func endEditing(commit: Bool)` returns when no alias field is being edited. With
       `commit`, it calls `table.window?.makeFirstResponder(table)`, which ends the edit and saves
       it. Without it, it calls `abortEditing()` on the field and then
       `table.window?.makeFirstResponder(table)`, so focus goes back to the table as today. The
       end-edit callback sees the unchanged stored value and saves nothing. That happens before
       `applyFilter()` reloads, so the row index is still valid.
     - `private func beginEditing(row: Int)` returns for an out-of-range row. Otherwise it selects
       the row, scrolls it into view, and calls
       `table.editColumn(table.column(withIdentifier: Column.aliases), row: row, with: nil, select: true)`.
     - `@objc private func tableClicked()` calls `beginEditing(row: table.clickedRow)` when
       `clickedRow >= 0` and `clickedColumn` is the Aliases column.
     - `controlTextDidEndEditing(_:)` ignores `filterField`.
       - For an alias field, it finds the row with `table.row(for: field)` (returning when it is
         out of range), normalises `field.stringValue` with `normalized(_:)`, and returns when the
         result equals the stored custom aliases.
       - Otherwise it saves `override.aliases`, calls `onChange?(settings)`, sets
         `field.stringValue` to the normalised list joined with ", ", and reconfigures that row's
         Built-in Aliases cell in place (`view(atColumn:row:makeIfNecessary: false)`).
       - Do not call `reloadData` from inside the end-editing callback.
     - `control(_:textView:doCommandBy:)` returns `false` for `filterField`, so the search field
       keeps its stock Esc.
       - For an alias field, `insertNewline(_:)` calls
         `table.window?.makeFirstResponder(table)` and returns `true`.
       - `cancelOperation(_:)` sets `textView.string` to the row's stored custom aliases joined
         with ", ", then makes the table first responder and returns `true`. The end-edit
         callback then finds nothing to save, which is the revert (measured: the field ends with
         the replaced string and the table is first responder).
       - Anything else returns `false`.
   - API for the window controller:
     - `func show(items: [LauncherItem], revealing id: String?) -> Bool`:
       1. Store `allItems`.
       2. Set the filter text to the revealed item's title, or empty.
       3. Call `applyFilter()`.
       4. Return whether the revealed item is among `visibleItems`.
     - `func update(items:)` is today's guard-and-refilter.
     - `func focusFilter()` makes `filterField` first responder.
     - `func edit(itemID: String)`: find the row in `visibleItems`, make the table first
       responder, then `beginEditing(row:)`.
   - Move the `ItemTable` class unchanged into this file as `private`.
2. `Sources/OddFrog/SettingsWindowController.swift`:
   - Drop the `NSTableViewDataSource`, `NSTableViewDelegate`, `NSSearchFieldDelegate` and
     `NSWindowDelegate` conformances.
   - Delete these members: the `Column` enum, `itemTable`, `itemScroll`, `filterField`,
     `itemsHelper`, `itemsEmptyLabel`, `selectedItemRow`, `editingAliasCell`, `settings`,
     `allItems`, `visibleItems`, the stored `icons`, `makeItemsPane()`, `layoutColumns()`,
     `applyFilter()`, the alias helpers (`aliasColumnIndex`, `aliasCell`, `refreshAliasCell`,
     `configureAliasCell`, `beginAliasEdit`, `endAliasEdit`), `itemTableClicked()`, `commit()`,
     `toggleEnabled(_:)`, `windowDidResize(_:)`, `controlTextDidChange(_:)`, every table
     data-source and delegate method, `textCell(…)`, `hosted(_:)`, the `window.delegate = self`
     line and the `ItemTable` class.
   - Add `private let itemsPane: ItemsPaneController`. Set it in `init(icons:)` with
     `ItemsPaneController(icons: icons)` before `super.init`. The initializer signature stays
     for `AppDelegate`. Delete the `icons.observeLoads` block from `init`, because
     `ItemsPaneController` registers its own. In `buildContent()`:
     - set `itemsPane.onChange = { [weak self] in self?.onChange?($0) }`;
     - make `itemsPane` the second child of `paneController`.
   - `present(settings:items:hotkey:focusing:)` becomes:
     1. `itemsPane.settings = settings`, `showHotkey(hotkey)` and `general.refreshLogin()`.
     2. `let revealing = itemsPane.show(items: items, revealing: id)`.
     3. `NSApp.activate(ignoringOtherApps: true)`, `showWindow(nil)` and
        `window?.makeKeyAndOrderFront(nil)`.
     4. If `revealing`, and `id` is non-nil: `showPane(.items)`, then `itemsPane.edit(itemID:)`.
        Otherwise `showPane(currentPane)`, which focuses the filter on Items and the sidebar
        elsewhere.
     The `initialFirstResponder` lines, the `layoutColumns()` calls and the spec 46
     `if currentPane == .items … else { sidebar.focus() }` line go away, because `showPane` now
     sets the focus after the window is key.
   - `showPane(_:)`:
     - When leaving Items, call `itemsPane.endEditing(commit: true)` instead of `endAliasEdit`.
     - `sidebar.focus()` and the lines that set `currentPane`, `sidebar.selected`, the tab index
       and the title stay as spec 46 left them.
     - The Items tail becomes `itemsPane.focusFilter()` after the `guard pane == .items`.
   - `update(items:)` forwards to `itemsPane.update(items:)`.
     `update(pluginSettings:)` sets `itemsPane.settings.plugins = pluginSettings`.
   - `manageLinks()` calls `itemsPane.endEditing(commit: true)` instead of `endAliasEdit`.
3. Delete `AliasCellView.swift`, `HoverRowView.swift`, `GroupBox.swift`, `SelectionPalette.swift`
   and `SettingsLayout.swift`.

Decisions recorded:
- Built-in aliases get their own read-only column, and the editable column holds only the user's
  aliases. Rejected alternative: a single cell mixing grey built-ins with editable text, which
  needs a custom cell.
- The "Add alias" placeholder shows on every empty row. Rejected alternative: showing it only on
  the selected row, which needs per-selection cell refreshes.
- The stock field editor selects all of the text when editing starts. Today the caret goes to
  the end.
- The row height stays the table's stock 24pt. Icons are requested at 16pt and shown in a 16pt
  image view positioned with constraints. Rejected alternatives: a non-custom `rowSizeStyle`,
  whose image frames spill out of inset rows, and an image view without a size, which takes the
  size of symbol and image-file icons (see Context).
- The Item title is not dimmed beyond `secondaryLabelColor`, and the 0.45 icon alpha goes away.
- A catalog refresh during an alias edit discards the edit, as today.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners, no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and `if … { return … }` bodies where neighbouring code uses them, one type per file for new types, and no new package dependencies (Apple system frameworks such as SwiftUI and Observation are fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font, `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or hex colours and no custom fills (semantic system colours only), no corner radii, no `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins, system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding. Literal numbers are allowed only where AppKit has no system value (initial window content sizes, the launcher panel width and its glass corner radius) — the spec must list which literals remain.
- Literals that remain after this spec:
  - `ItemsPaneController.iconSize`, 16pt, used for the icon request and the image view's width
    and height;
  - the initial widths of the four text columns (160, 60, 90, 90), which uniform autoresizing
    then grows or shrinks;
  - the Return and keypad Enter key codes (36, 76) in `ItemTable`.

  The window's 760×560 content size from spec 46 is unchanged.
- `AppDelegate.swift` does not change. Every `SettingsWindowController` member it uses keeps its
  signature.
- The user-visible strings "Filter", "No items match “…”.", "Show in launcher", "Item", "Kind",
  "Aliases", "App" and the Aliases header tooltip stay word for word.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
    else: do not start the app or a dev server, do not open a browser, do not take
    screenshots, do not write or run tests or scripts that are not listed in Plan, do not
    mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed)
- `ls Sources/OddFrog/AliasCellView.swift Sources/OddFrog/HoverRowView.swift Sources/OddFrog/GroupBox.swift Sources/OddFrog/SelectionPalette.swift Sources/OddFrog/SettingsLayout.swift 2>/dev/null` prints nothing
- `grep -rnw "SelectionPalette\|SelectionInk\|HoverRowView\|AliasCellView\|AliasPill\|GroupBox\|SettingsLayout" Sources Tests Plugins` prints nothing
- `grep -n "rowHeight\|intercellSpacing\|rowViewForRow\|alphaValue\|backgroundColor\|systemFont\|controlSize\|layoutColumns" Sources/OddFrog/ItemsPaneController.swift Sources/OddFrog/SettingsWindowController.swift` prints nothing
- `grep -rn "NSTableViewDataSource\|NSSearchFieldDelegate\|NSWindowDelegate" Sources/OddFrog/SettingsWindowController.swift` prints nothing

## Manual review
1. `make run` and open Settings › Items. There is a stock search field, and below it a stock inset
   table. The columns are an unlabelled checkbox column, then Item, Kind, Built-in Aliases and
   Aliases. The rows are standard height with small icons, and there is no card or border drawn
   around the list.
2. Move the mouse over the rows: nothing highlights. Click a row: the stock selection appears, and
   it turns grey when focus moves to the filter field.
3. Uncheck an item. Its title turns grey, the item disappears from the launcher, and
   `settings.toml` gains `enabled = false` for it. Check it again to restore it.
4. Click an empty Aliases cell ("Add alias" in placeholder grey). An in-place editor opens. Type
   `Foo, bar ,` and press Return. The cell shows `foo, bar`, the Built-in Aliases cell is
   unchanged, and `foo` finds the item in the launcher.
5. Select another row and press Return: editing starts. Type something and press Esc: the old
   aliases come back and nothing is saved.
6. Type `zzzz` into Filter: "No items match “zzzz”." is centred over the list. Clear the filter.
7. From the launcher, highlight an app and press ⌘I. Settings opens on Items, filtered to that
   title, with the row selected and its Aliases editor active.
8. Start an alias edit, type, then click General in the sidebar. Come back: the edit was saved.
9. Resize the window, then drag the sidebar divider. Each time the four text columns share the
   change in width, the checkbox column stays narrow, and no horizontal scroll bar appears.
10. An item whose icon is an SF Symbol (a Commands link) shows a small symbol in the same 16pt slot
    as app icons, and every row keeps the standard height.

## Out of scope
- The General and Plugins panes, the window shell (specs 46 and 47), and the Manage Links sheet
  (spec 49).
- Removing duplicate aliases, and validating aliases against other items.
- Keeping `SettingsWindowController`'s copy of item overrides in sync with external
  `settings.toml` edits while the window is open. Today it only refreshes on `present`, and that
  stays.
- `IconCache`, `AppDelegate` and the launcher table.

## Open questions
none
