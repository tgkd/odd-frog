# Task: Give the launcher stock AppKit styling: inset table, text styles, system spacing, system shadow

## Goal
The launcher keeps its bare query line and its glass panel. Everything else uses the system's own
look:
- The result list is a stock `.inset` table with the system's rounded accent selection and no hover
  highlight.
- Labels use text-style fonts and semantic colours that adapt on the selected row by themselves.
- "Required" and "Optional" appear as plain words instead of a drawn chip.
- The line under the query is a stock separator, and the spacing comes from system margins and
  stack defaults.
- The panel uses the system window shadow and system window animation.

Row heights and the panel height come from Auto Layout measurements, not from constants.

## Files
- Sources/OddFrog/LauncherViewController.swift         (modify)
- Sources/OddFrog/ResultRowView.swift                  (modify)
- Sources/OddFrog/ResultRow.swift                      (modify)
- Sources/OddFrog/SearchField.swift                    (modify)
- Sources/OddFrog/LauncherPanel.swift                  (modify)
- Sources/OddFrog/IconCache.swift                      (modify)
- Sources/OddFrog/AppDelegate.swift                    (read — `showPanel()` calls `panel.present(height: controller.preferredHeight)`; `onHeightChange` calls `panel.resize(height:)` while visible; `hidePanel()` calls `panel.dismiss()`)
- Sources/OddFrog/SelectionPalette.swift               (read — still used by SettingsSidebar.swift, HoverRowView.swift and AliasCellView.swift; spec 48 deletes it)
- Sources/OddFrog/SettingsWindowController.swift       (read — also calls `icons.icon(for:size: 20)`, which must keep working)
- Sources/OddFrogCore/Item.swift                       (read — `LauncherItem.kindLabel`, `LauncherItem.subtitles(for:)`)
- Sources/OddFrogPluginAPI/PluginItem.swift            (read — `PluginArgument.placeholder` and `.optional`)

## Context
- Precondition: spec 43 has landed.
  - The deployment target is macOS 26.
  - In `LauncherViewController.loadView()`, the root is built unconditionally:
    `let glass = NSGlassEffectView()`, `glass.cornerRadius = Self.cornerRadius`,
    `glass.contentView = content`, then `glass.translatesAutoresizingMaskIntoConstraints = false` and
    `view = glass`. The glass sizes and constrains `content` by itself.
  - The expected build warning is only the UnitRegistry `nonisolated(unsafe)` one.
- `LauncherPanel` (an `NSPanel` subclass):
  - Window setup: `styleMask` `[.nonactivatingPanel, .borderless, .fullSizeContentView]`, level
    `.floating`, collection behaviour, `isOpaque = false`, `backgroundColor = .clear`,
    `hasShadow = false`, `animationBehavior = .none`, initial content rect 560 × 60.
  - `present(height:)` puts the panel on the screen under the mouse. It centres it horizontally with
    width `Self.width` (560) and puts the top edge 25 % below the top of the visible frame. When the
    panel is not yet visible and Reduce Motion is off, it fades in from `alphaValue = 0` and rises by
    `appearRise` (4 pt) over `animationDuration` (0.14 s) through `animate(_:)` (`NSAnimationContext`
    with an ease-out `CAMediaTimingFunction`). This is the only use of `import QuartzCore`.
  - `resize(height:)` keeps the top edge fixed and animates the frame the same way.
  - `dismiss()` calls `orderOut` and resets `alphaValue = 1`.

  Measured on this SDK: a borderless `.nonactivatingPanel` defaults to `hasShadow == true`, so the
  current line actively removes the system shadow. `animationBehavior` defaults to `.default`.
  `setFrame(_:display:animate: true)` blocks the main thread for the whole resize animation (about
  0.33 s). `resize(height:)` runs on keystrokes, so it must stay a plain `setFrame`.
- `LauncherViewController` layout today:
  - A fixed 44 pt header view holds the `SearchField`, inset 16 pt left and right.
  - Below it is a private `HairlineView` (0.5 pt, `updateLayer` fills `separatorColor`) inset 12 pt.
  - A centred empty-state label has `.systemFont(ofSize: 13)` and sits in a 56 pt band.
  - An `NSScrollView` is inset 8 pt at the sides and 6 pt at the top, with 8 pt added below. It sets
    `automaticallyAdjustsContentInsets = false`, `contentInsets = NSEdgeInsetsZero` and
    `scrollerStyle = .overlay`, and keeps `drawsBackground = false`. It holds a `.plain`
    `NSTableView` with:
    - `backgroundColor = .clear`
    - `rowHeight = ResultRowView.singleLineHeight`
    - `intercellSpacing` (0, 0)
    - `refusesFirstResponder = true`
    - one column with `resizingMask = .autoresizingMask`, no header
    - `selectionHighlightStyle = .regular`
  - `scrollHeight` is a height constraint on the scroll view, set in `refresh()` to
    `tableView.rect(ofRow: min(rows, visibleRowCap) - 1).maxY`.
  - `preferredHeight` adds the constants together by hand. It depends on `showsEmptyState`, which
    `refresh()` sets.
  - Nothing is pinned to the bottom of `content`. The panel height is applied only through
    `onHeightChange` and `LauncherPanel.present/resize`, and that must stay so.
- Rows today:
  - `ResultRow`, the `NSTableRowView` subclass returned by `tableView(_:rowViewForRow:)`:
    - forces `isEmphasized` to true,
    - overrides `interiorBackgroundStyle`,
    - tracks hover with an `NSTrackingArea`,
    - hand-draws a 10 pt rounded selection in `SelectionPalette.fill` and a
      `quaternaryLabelColor` hover fill.
  - `ResultRowView`, the `NSTableCellView`:
    - puts its labels in a plain `textBlock` view and swaps `oneLine`/`twoLine` constraint sets,
    - has fixed row heights of 36 and 40,
    - uses literal 14/11/10 pt fonts,
    - pins a 24 × 24 icon with `.scaleProportionallyUpOrDown`,
    - recolours its labels on selection in `applyPalette()` with `SelectionPalette.ink`,
    - draws a `ChipView` (a `CAShapeLayer` capsule) for "Required" and "Optional".
- Facts that decide the new design. Each was measured in a scratch build against the macOS 26
  target.
  - The table's selection:
    - In `.inset` style, the stock `NSTableRowView` draws the rounded accent selection when
      `isEmphasized` is true.
    - The table never becomes first responder, because typing stays in the query field. So without
      the forced `isEmphasized` the selected row draws in unemphasized gray. NSTableView has no
      "always emphasized" option.
    - With only `isEmphasized` forced, the stock `interiorBackgroundStyle` is already `.emphasized`
      on the selected row.
    - `NSTableCellView` forwards `backgroundStyle` to every nested label, including labels two
      `NSStackView` levels deep. `labelColor`, `secondaryLabelColor` and `tertiaryLabelColor` adapt
      to the emphasized row by themselves.
  - `.inset` table metrics:
    - The first row starts at y = 10. The table's height is the last row's `maxY` plus the same 10.
    - The cell sits 16 pt in from each side.
    - Default `intercellSpacing` is (17, 0).
    - The style paints `controlBackgroundColor` unless `backgroundColor = .clear`, so that line must
      stay for the glass to show.
    - Scroll view safe-area insets in this borderless panel are 0.
    - When `tableView(_:heightOfRow:)` is implemented, `rect(ofRow:)` returns the delegate's
      heights, even while the scroll view is 0 pt tall.

    `usesAutomaticRowHeights` was rejected: `rect(ofRow:)` then returns 24 pt estimates for rows
    that have not been laid out, so the panel came out short.
  - Default metrics:
    - Layout margins inside the glass content view, and inside any view placed in it, are 20 pt on
      every side.
    - `NSStackView` default spacing is 8 pt.
    - `.title2` is 17 pt, `.body` 13 pt, `.subheadline` 11 pt.
    - A bare `NSTextField` at `.title2` is 25.5 pt tall. `NSTextField(labelWithString:)` is 18.5 pt
      tall at `.body` and 16 pt at `.subheadline`, and its default font is already the 13 pt system
      font.
    - An `NSBox` with `boxType = .separator` takes 1 pt in Auto Layout.
  - SF Symbols at `NSImage.SymbolConfiguration(textStyle: .title2)` are 19–24 pt wide and 18–19 pt
    tall, so they fit a 24 pt icon slot unscaled. App icons from `IconCache` are already drawn at the
    requested size.
  - Vertical padding for a row cell, compared:
    - Layout margins, or system spacing from the cell's edge: 20 pt, which makes a one-line row
      64 pt.
    - No padding: a 24 pt row, and the 24 pt icon touches the selection edges.
    - `NSStackView.edgeInsets`: did not add padding to two-line rows.
    - The row stack's own `spacing` (8 pt), used as top and bottom padding: 40 pt one-line and 51 pt
      two-line rows, when title and detail lines are stacked with spacing 0.
    - With the default 8 pt between title and detail lines, rows were 59 pt, and the two lines read
      as separate items.
    - AppKit cannot resolve system spacing between two labels' baselines. It throws
      `NSInternalInconsistencyException`.
  - A vertical `NSStackView` with `alignment = .width` and `spacing = 0` detaches hidden arranged
    views. Its `fittingSize.height` is the sum of the visible views. Measured with a header whose
    field is pinned to its margins, the separator, the scroll view and an empty-state band:
    - field only: 66
    - empty state: 123
    - three rows of 64: 298

    `fittingSize` ignores the constraints that pin the stack inside `content`.
  - `NSStackView` makes its alignment constraints at priority 250 (`.defaultLow`), and
    `NSTextField(labelWithString:)` hugs its text horizontally at 251. With `alignment = .width` in a
    560 pt panel, measured:
    - The header, the separator and the scroll view fill the full width, because the editable query
      field, `NSBox` and `NSScrollView` have no intrinsic width.
    - A band that holds the empty-state label pinned to its margins came out 186 pt wide at the
      trailing edge, so "No results for …" was not centred.
    - With the label's horizontal hugging lowered to `.defaultLow - 1`, the band is 560 pt wide and
      the label spans it.
  - A long subtitle or title in the stack-based cell below truncates inside the table's fixed cell
    width, and the kind label stays at the trailing edge (measured in an `.inset` table).
  - These values were measured at runtime on a macOS 27 build host, in a build that targets
    macOS 26. Label heights may differ by about a point on macOS 26. No literal in this spec depends
    on them.
- `IconCache` has three private `tile(...)` overloads that draw coloured rounded tiles. Only they call
  each other; nothing else in the repository calls them. `emojiImage(_:size:)` draws `text:` emoji
  icons from script metadata. AppKit has no emoji-to-image API, so it stays as it is.
- `LauncherPanel.sendEvent(_:)` and `LauncherViewController.handleKeyEquivalent(_:)` are the ⌘-key
  routing that spec 45 changes. `control(_:textView:doCommandBy:)` handles Esc, the arrows, Return
  and Tab. All three stay untouched here.

## Plan
1. `Sources/OddFrog/SearchField.swift`:
   - Replace the literal 18 pt font with `font = NSFont.preferredFont(forTextStyle: .title2)`.
   - Replace the attributed placeholder with `placeholderString = "Search…"`.
   - Keep `isBezeled = false`, `isBordered = false`, `drawsBackground = false`,
     `focusRingType = .none` and the single-line settings (`lineBreakMode`, `usesSingleLineMode`,
     `cell?.wraps`, `cell?.isScrollable`).

   Decision: the field stays a bare `NSTextField`, not `NSSearchField`, because it takes commands
   and arguments, not only searches. Those four properties are the one documented exception to
   stock styling.
2. `Sources/OddFrog/ResultRow.swift`: reduce the class to the `identifier` constant and the forced
   `isEmphasized` override. Delete the rest:
   - `cornerRadius`
   - the tracking area and `isHovered`
   - `interiorBackgroundStyle`
   - `mouseEntered` and `mouseExited`
   - `drawSelection`, `drawBackground` and `rowPath`

   Decision: keep this one-property subclass rather than a stock row view, because without it the
   selection draws unemphasized gray (Context).
3. `Sources/OddFrog/ResultRowView.swift`: rebuild the cell as nested `NSStackView`s inside the stock
   `NSTableCellView`.
   - Keep `static let identifier` and set `identifier = Self.identifier` in `init()`.
   - Add `static let iconSide: CGFloat = 24`, the icon slot size.
   - Rename `enum Chip` to `enum Requirement` (`case required`, `case optional`).
   - Delete `singleLineHeight`, `twoLineHeight`, `textBlock`, `oneLine`, `twoLine`, the
     `backgroundStyle` override, `applyPalette()`, the `viewDidChangeEffectiveAppearance()` override
     and the whole `ChipView` class.
   - Labels, all `NSTextField(labelWithString:)`:
     - `titleLabel`: `.body`, tail truncation, horizontal compression resistance `.defaultLow`.
     - `subtitleLabel`: `.subheadline`, `secondaryLabelColor`, horizontal compression resistance
       `.defaultHigh`.
     - `valueLabel`: `.subheadline`, default `labelColor`, horizontal compression resistance
       `.defaultLow`. It has no medium weight.
     - A new `requirementLabel`: `.subheadline`, `tertiaryLabelColor`.
     - `kindLabel`: `.subheadline`, `tertiaryLabelColor`, `.right` alignment, horizontal hugging
       and compression resistance `.required`.

     `subtitleLabel` and `valueLabel` keep middle truncation, `maximumNumberOfLines = 1`,
     `usesSingleLineMode = true` and `truncatesLastVisibleLine`. Drop the subtitle's `.required`
     hugging.
   - `iconView`: `imageScaling = .scaleProportionallyDown` and
     `symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .title2)`, with width and height
     constraints equal to `Self.iconSide`. Symbols then render at the query line's text style,
     unscaled. 24 pt app and emoji images render 1:1. Larger plugin images shrink to fit.
     Decision: stretching symbols to 24 pt with `.scaleProportionallyUpOrDown` was rejected, because
     it ignores the text style the symbol is drawn for.
   - Build the stacks with `NSStackView(views:)`:
     - `detailStack`: horizontal, `[subtitleLabel, valueLabel, requirementLabel]`, default spacing.
       Keep it as a stored property.
     - `textStack`: vertical, `[titleLabel, detailStack]`, `alignment = .leading`, `spacing = 0`.
     - `rowStack`: horizontal, `[iconView, textStack, kindLabel]`, default spacing,
       `distribution = .fill`.

     With `.fill`, the text stack takes the free width, so the kind label sits at the trailing
     edge on both one-line and two-line rows. Measured.
   - Add `rowStack` as the only subview. Set its `translatesAutoresizingMaskIntoConstraints = false`,
     and pin its leading and trailing edges to the cell with no constant. Pin
     `rowStack.topAnchor` to `topAnchor` with `constant: rowStack.spacing`, and `bottomAnchor` to
     `rowStack.bottomAnchor` with the same constant.

     Decision: the vertical padding is the stack's own system spacing. The alternatives measured in
     Context were 20 pt margins, zero padding, `edgeInsets` and 8 pt line spacing. The text stack
     uses spacing 0 because the title and detail are two lines of one text block, and each label's
     height already includes its font's line spacing.
   - Set `textField = titleLabel` and `imageView = iconView`. These are the stock outlets. The
     table's default `rowSizeStyle` (`.custom`) applies no metrics to them.
   - `configure(title:detail:value:tooltip:kind:requirement:icon:)` replaces the `chip:` parameter
     with `requirement: Requirement?`. It sets:
     - the title, `toolTip = tooltip` and the icon image,
     - `subtitleLabel.stringValue = detail ?? ""` and `detailStack.isHidden = detail == nil`,
     - `valueLabel` text, hidden when `value == nil`,
     - `requirementLabel` to "Required" or "Optional", hidden when `requirement == nil`,
     - `kindLabel.stringValue = kind ?? ""`.

     The stacks detach hidden views, so no constraints are swapped.
4. `Sources/OddFrog/LauncherViewController.swift`:
   - Constants: delete `fieldHeight`, `fieldPadding`, `hairlineHeight`, `hairlineInset`,
     `listInsetTop`, `listInsetSide`, `listInsetBottom` and `emptyStateHeight`. Keep
     `cornerRadius` and `visibleRowCap`.
   - Delete the nested `HairlineView` class, the `hairline` property and the stored
     `showsEmptyState`.
   - Add `private let contentStack = NSStackView()`, `private let separator = NSBox()`,
     `private let emptyBand = NSView()` and `private let prototype = ResultRowView()`.
   - In `loadView()`, keep `content`, the glass root from spec 43 and the table setup's
     `dataSource`, `delegate`, `target`, `action`, `refusesFirstResponder`, `headerView = nil`,
     table column (`NSTableColumn` with `resizingMask = .autoresizingMask`), `backgroundColor = .clear`
     and `selectionHighlightStyle` lines. Then:
     - Table: set `tableView.style = .inset`. Delete the `rowHeight` and `intercellSpacing` lines.
     - Scroll view: delete `automaticallyAdjustsContentInsets`, `contentInsets` and `scrollerStyle`.
       Keep `hasVerticalScroller`, `autohidesScrollers` and `drawsBackground = false`.
     - Delete the `content.addSubview` calls for the header, the hairline, the empty label and the
       scroll view, the `translatesAutoresizingMaskIntoConstraints = false` lines on the header and
       the scroll view, and the whole `NSLayoutConstraint.activate` block that positions them. The
       stack below replaces all of it.
     - Header: a local plain `NSView` that holds the search field as today. Pin the search field's
       leading, trailing, top and bottom to `header.layoutMarginsGuide`. Keep
       `searchField.delegate = self`.
     - Separator: `separator.boxType = .separator`.
     - Empty state:
       - Delete the `emptyLabel.font` line and the `emptyLabel.isHidden = true` line.
       - Keep the secondary colour, centre alignment and tail truncation.
       - Add `emptyLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)`. This lets
         the stack's width alignment stretch the band to the full panel width, so the text is
         centred (Context).
       - Add the label to `emptyBand`, not `content`, and pin its four edges to
         `emptyBand.layoutMarginsGuide`.
     - `contentStack`:
       - `orientation = .vertical`, `alignment = .width`, `distribution = .fill`, `spacing = 0`.
       - Add the arranged subviews in this order: header, separator, scroll view, empty band.
       - Set `translatesAutoresizingMaskIntoConstraints = false`, add the stack to `content`, and
         pin its leading, trailing and top edges to `content`. Do not pin its bottom.
       - Activate `scrollHeight` (the scroll view's height, starting at 0) with it.

     The header and the empty band carry their own system margins, and the `.inset` table carries
     its own 10 pt insets. That is why the stack's spacing is 0 and the scroll view runs edge to
     edge.

     The search field and the empty label are pinned by constraints, so they keep
     `translatesAutoresizingMaskIntoConstraints = false`. The stack sets that property on its
     arranged subviews by itself.
   - `preferredHeight` becomes `contentStack.fittingSize.height`.
   - `refresh(keepSelection:)`:
     - Keep the search, `reloadData()`, `layoutSubtreeIfNeeded()` and the selection logic.
     - Set `scrollHeight.constant` to `0` when there are no rows. Otherwise set it to
       `tableView.rect(ofRow: visible - 1).maxY + tableView.rect(ofRow: 0).minY`, which adds the
       style's bottom inset (equal to its top inset).
     - Compute `showsEmptyState` as a local with today's rule.
     - Set `emptyBand.isHidden = !showsEmptyState`, `scrollView.isHidden = rows == 0` and
       `separator.isHidden = rows == 0 && !showsEmptyState`. These replace today's
       `emptyLabel.isHidden`, `scrollView.isHidden` and `hairline.isHidden` lines. The label itself
       is never hidden, because the band's visibility controls it.
     - Keep the empty-label text and the final `onHeightChange?(preferredHeight)`.
   - Add `private func configure(_ cell: ResultRowView, row: Int, icon: NSImage?)` holding today's
     `viewFor` body: `detail(for:)` and the `configure` call, passing `requirement:` instead of
     `chip:`.
     - `tableView(_:viewFor:row:)` reuses or creates the cell as today and calls it with
       `icons.icon(for: results[row].item, size: ResultRowView.iconSide)`.
     - `tableView(_:heightOfRow:)` calls it on `prototype` with `icon: nil`, so no icon load starts,
       and returns `prototype.fittingSize.height`.
   - `DetailLine.chip` becomes `requirement: ResultRowView.Requirement?`. `detail(for:)` sets it
     the same way (`.optional` or `.required` while no argument is typed).
5. `Sources/OddFrog/LauncherPanel.swift`:
   - Delete `animationDuration`, `appearRise`, `hasShadow = false`, `prefersReducedMotion`,
     `animate(_:)` and `import QuartzCore`.
   - Change `animationBehavior = .none` to `animationBehavior = .utilityWindow`.
   - `present(height:)`: compute the same target rect, call `setFrame(target, display: true)`, then
     `makeKeyAndOrderFront(nil)`, then `invalidateShadow()`. It no longer sets alpha or animates.
   - `resize(height:)`: compute the same top-anchored target, call `setFrame(target, display: true)`,
     then `invalidateShadow()`.
   - `dismiss()`: keep the `isVisible` guard and `orderOut(nil)`. Drop the `alphaValue` reset.

   `invalidateShadow()` makes the system shadow follow the new height of the non-opaque window.
   Keep:
   - `width`, the style mask, level, collection behaviour and the key/main overrides
   - `isOpaque = false` and `backgroundColor = .clear`, which the glass outline needs
   - `onResignKey`
   - `sendEvent(_:)`, which spec 45 owns

   Decision: the stock `.utilityWindow` animation replaces the fade and rise. Whether AppKit
   animates this borderless non-activating panel at all is the system's choice, and a plain appear
   is accepted.
6. `Sources/OddFrog/IconCache.swift`: delete the three private `tile(...)` overloads. Keep
   everything else, including `emojiImage(_:size:)`.

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
- The styling and layout literals left in the launcher after this spec are exactly these.
  Non-styling numbers such as key codes, the `maxResults` default and cache limits are not
  affected.
  - `LauncherPanel.width` = 560 (panel width).
  - `LauncherPanel`'s initial content rect height of 60 (initial window size).
  - The placement fraction 0.25 in `present(height:)` (top edge 25 % down the visible frame).
  - `LauncherViewController.cornerRadius` = 18 (glass corner radius; the glass default is 8, and no
    API gives a window radius).
  - `LauncherViewController.visibleRowCap` = 8 (content policy: rows shown before scrolling).
  - `ResultRowView.iconSide` = 24. AppKit has no icon metric for bitmap icons in an `.inset` table:
    `rowSizeStyle` metrics only reconfigure symbols and leave app icons at their 32 pt intrinsic
    size.
  - `spacing = 0` on `contentStack` and on the title/detail text stack (adjacency, not padding;
    reasons in Plan).
  - The emoji glyph scale `size * 20 / 24` in `IconCache.emojiImage`, unchanged.
  - The empty label's horizontal hugging priority `.defaultLow - 1`. It is a layout priority, not
    a size (reason in Context).
- The query field is the documented exception: keep `isBezeled = false`, `isBordered = false`,
  `drawsBackground = false` and `focusRingType = .none`. Do not turn it into `NSSearchField`.
- Keep `tableView.backgroundColor = .clear` and `scrollView.drawsBackground = false`, and keep
  `isOpaque = false` and `backgroundColor = .clear` on `LauncherPanel`. They let the glass show. Apart
  from semantic label colours, these are the only colour assignments.
- Do not touch key routing: `LauncherPanel.sendEvent(_:)`, `LauncherViewController.handleKeyEquivalent(_:)`
  and `control(_:textView:doCommandBy:)` stay byte-for-byte (spec 45 owns the first two).
- Do not delete `SelectionPalette.swift`: Settings still uses it until spec 48.
- Do not use `usesAutomaticRowHeights`, `setFrame(_:display:animate: true)` or
  `NSGlassEffectView.effectIsInteractive`.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed)
- `grep -n "SelectionPalette\|HairlineView\|ChipView\|drawSelection\|drawBackground\|updateLayer\|mouseEntered\|scrollerStyle\|hasShadow\|appearRise\|animationDuration\|singleLineHeight\|twoLineHeight\|listInset\|fieldHeight\|fieldPadding\|emptyStateHeight\|systemFont(ofSize" Sources/OddFrog/LauncherPanel.swift Sources/OddFrog/LauncherViewController.swift Sources/OddFrog/ResultRowView.swift Sources/OddFrog/ResultRow.swift Sources/OddFrog/SearchField.swift` prints nothing
- `grep -n "func tile" Sources/OddFrog/IconCache.swift` prints nothing
- `grep -rln "SelectionPalette" Sources | sort` prints exactly `Sources/OddFrog/AliasCellView.swift`, `Sources/OddFrog/HoverRowView.swift`, `Sources/OddFrog/SelectionPalette.swift`, `Sources/OddFrog/SettingsSidebar.swift`
- `grep -n "style = .inset" Sources/OddFrog/LauncherViewController.swift` prints one line

## Manual review
1. `make run`, then press the hotkey (default ⌥Space). The panel opens in the same place, 560 pt
   wide, with a system window shadow around the glass. There is no custom fade-and-rise; the system
   may fade it in or it may simply appear. The query row shows the "Search…" placeholder at 17 pt,
   with about 20 pt of glass above and below it, which is taller than before. Recent items, if any,
   are listed under it.
2. Type `de`. Under a thin system separator the results appear in a list inset from the panel
   edges:
   - The first row is selected with the system's rounded accent fill. The title, subtitle and kind
     on that row turn light by themselves. The secondary and tertiary text stays dimmer than the
     title.
   - Titles are 13 pt, subtitles and kinds 11 pt.
   - The kind label sits at the right edge of every row, including two-line rows.
   - Rows are about 40 pt (one line) and 51 pt (two lines).
3. Move the pointer over rows. Nothing highlights until you click. A click still runs the row.
   ↑ ↓, Return, Tab, Esc and ⌘1–9 behave as before.
4. Add a link whose URL contains `{query}` in Settings › Plugins › Commands › Manage Links…, or
   copy `examples/plugins/counter` to `~/.config/odd-frog/v2/plugins/counter` and enable Counter
   in Settings › Plugins. Type the item's name (the link's name, or `Count`): the second line reads
   "Query" (or "Optional note") followed by the gray word "Optional", with no box around it. Type
   the name, a space and some text: the text appears after the placeholder in primary colour, and
   "Optional" disappears.
5. Type `zzzqqq`. The separator stays, and "No results for “zzzqqq”" is centred across the full
   panel width in a band below it, not pushed to the right edge.
6. The default `max_results` is 8, so first set `max_results = 12` under `[general]` in
   `~/.config/odd-frog/v2/config.toml`. The app reloads it by itself. Type a single letter that
   matches more than eight items: eight rows show and the list scrolls. Set System Settings ›
   Appearance › Show scroll bars to Always: a normal scroll bar appears instead of the overlay
   one. The panel resizes as you type, with the top edge fixed, and the shadow follows the new
   height. Put `max_results` back afterwards.
7. Rows for script items with an emoji icon still show the emoji. SF Symbol icons, for example
   Calendar or Reminders rows, look like text-sized glyphs, not stretched to fill the slot.
8. Light and dark appearance both keep the selected row readable. To capture the panel with a
   query, run this as one command line (the open launcher takes the keyboard):

   ```
   printf 'de' > ~/Library/Logs/odd-frog-query.txt; pkill -USR1 -x OddFrog; sleep 1; pkill -USR2 -x OddFrog; sleep 1; screencapture -x -o -l "$(cat ~/Library/Logs/odd-frog-panel.window)" /tmp/panel.png; open /tmp/panel.png
   ```

   The image shows the panel with results for `de` and a readable selected row. Repeat after
   switching the appearance.

## Out of scope
- The query field becoming an `NSSearchField` (rejected), and any focus ring on it.
- ⌘-key interception, the main menu and the status menu (spec 45).
- Deleting `SelectionPalette.swift`, `HoverRowView.swift` or any Settings file (specs 46–48).
- Emoji icon rendering, the `IconCache` loading and caching logic, and the `icon(for:size:)`
  signature.
- The unused `shortPlaceholderLimit` constant in `LauncherViewController`.
- `.fullSizeContentView` in the panel's style mask, the window level and the collection behaviour.
- A context menu, or any other way to show secondary actions on rows.

## Open questions
none
