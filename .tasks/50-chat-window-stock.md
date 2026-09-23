# Task: Chat window on stock AppKit — table transcript, text-field composer, toolbar Stop, subtitle status

## Goal
The chat window shows its transcript as a stock view-based `NSTableView`. Each message is one row:
a bold speaker line ("You" or the plugin's name) above selectable body text. There are no bubbles,
fills, hex colours or corner radii. While a reply is empty, its row shows a spinning
`NSProgressIndicator`. Streamed text keeps the view pinned to the bottom unless the user has
scrolled up. The composer is a stock one-line `NSTextField` with the plugin's placeholder. Status
text goes to `window.subtitle`, and Stop is a toolbar item that is enabled only while a send runs.
Esc no longer closes the window; ⌘W does.

## Files
- Sources/OddFrog/ChatTranscriptView.swift                  (modify — table-based transcript)
- Sources/OddFrog/ChatMessageCell.swift                     (create — one transcript row)
- Sources/OddFrog/ChatWindowController.swift                (modify — composer, toolbar, subtitle)
- docs/query-plugins.md                                     (modify — Chat section wording)
- Sources/OddFrogCore/ChatSession.swift                     (read — the state the window renders; stays unchanged)
- Sources/OddFrogPluginAPI/PluginView.swift                 (read — `PluginMessage`, `PluginMessage.Role`)
- Sources/OddFrog/AppDelegate.swift                         (read — how the window is created and wired; stays unchanged)
- Sources/OddFrog/LauncherViewController.swift              (read — the single-column table and `makeView(withIdentifier:owner:)` reuse pattern)
- Plugins/Chat/plugin.toml, Plugins/Chat/Sources/ChatPluginCore/ChatProvider.swift (read — plugin name "Chat", placeholder "Message…")

## Context
- Preconditions:
  - Specs 43–49 have landed. The package targets macOS 26 (`swift-tools-version: 6.2`,
    `.macOS(.v26)`), and `swift build` has one warning, `nonisolated(unsafe)` in
    `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`.
  - Spec 45 built the standard main menu. File has Save ⌘S and Close ⌘W. Edit has Copy ⌘C and the
    rest of the standard items.
  - None of specs 43–49 touches the three chat files.
- Swift package, AppKit app, Swift 6 language mode. Tests use Swift Testing. There is no test
  target for AppKit code in `Sources/OddFrog`, and this task adds no tests.
- `AppDelegate` wiring, which does not change:
  - It owns `private lazy var chats = ChatWindowController()`.
  - It sets `chats.performSend` and `chats.cancelSend`.
  - It routes `plugins.onMessageDelta` to `chats.apply(_:pluginID:)`.
  - `reloadPlugins()` calls `chats.pluginsDidReload()`.
  - `runPluginAction` opens `.chat` views with `chats.present(_:send:result:pluginName:)`.
  - Keep every one of these signatures.
- `ChatSession` (`@MainActor`, in OddFrogCore) holds all chat state:
  - `messages: [PluginMessage]`, `draft`, `outgoing: Outgoing?`, `isSending`, `canSend`,
    `invalidated`, `error: String?`, `placeholder: String?`, `pluginName`, `title`.
  - `beginSend()` appends a user message (`host-user-N`) and an empty assistant message
    (`host-reply-N`), clears `draft`, and returns an `Outgoing` whose `replyID` is that reply's id.
  - `receive(_:)` appends a delta to the reply. On the first delta it may rename the reply's id to
    the provider's `messageID`.
  - `complete(id:view:)` clears `outgoing`. When the provider returned a view, it replaces
    `messages` (with the provider's ids) and `title`.
  - `fail(id:message:terminal:)` removes the pair, restores `draft`, and sets `error`.
  - `invalidate(message:)` marks the session dead.
  - `PluginMessage` is `{id, role: .user | .assistant, text}`.
  - The bundled Chat plugin is named "Chat" and sends `placeholder: "Message…"`.
- `ChatWindowController` today:
  - It is an `NSWindowController, NSWindowDelegate, NSTextViewDelegate`, with a titled, closable,
    resizable, miniaturizable window: content 560×640, `minSize` 380×320, autosave name "chat".
  - The composer is an `NSTextView` inside a borderless `NSScrollView` (`inputScroll`), sitting in
    a private `Capsule` view. `Capsule` overrides `wantsUpdateLayer`/`updateLayer` and
    `viewDidMoveToWindow`/`viewDidChangeEffectiveAppearance` to draw a 16 pt rounded, bordered
    layer.
  - `updateInputHeight()` grows the composer to six lines through the `inputHeight` constraint,
    with a 14 pt fallback font.
  - `placeholderLabel` is overlaid by hand.
  - A 28 pt bottom `bar` holds `statusLabel` (12 pt) and a small `.rounded` `stopButton`.
  - An `NSBox` `.separator` sits between the transcript and the composer.
  - The composer turns off quote and dash substitution, text replacement, link detection and
    spelling correction.
  - `textView(_:doCommandBy:)` sends on `insertNewline`, leaves `insertLineBreak` alone, and
    closes the window on `cancelOperation` (Esc and ⌘.).
  - `refresh()` sets the status label to `session.error`. Otherwise, while sending, it shows
    "Waiting for \(pluginName)…", and otherwise "". Stop is visible only while sending, and the
    input is editable unless `session.invalidated`.
  - `finish` and `activateWindow` call `window?.makeFirstResponder(input)`.
- `ChatTranscriptView` today:
  - It is an `NSView` wrapping an `NSScrollView` (forced `scrollerStyle = .overlay`,
    `drawsBackground = false`) around a flipped document view holding an `NSStackView` of private
    `Bubble` views.
  - Bubbles have a layer corner radius of 16, an accent fill with `NSColor.white` text for the
    user, a hand-picked hex grey pair for replies, a 75 % width cap, and a literal "…" while the
    reply is empty.
  - `render(_ messages:, streaming replyID:)` diffs bubbles by role.
  - It keeps the view pinned to the bottom when the user was within `Style.stickyBottom` (24 pt) of
    the bottom before the render. AppKit has no stock "stick to bottom" behaviour, so this check
    stays.
- Facts measured on this machine for a view-based `NSTableView` with `style = .inset`,
  `usesAutomaticRowHeights = true`, one column with `resizingMask = .autoresizingMask`,
  `headerView = nil`, and cells built from a vertical `NSStackView`:
  - Wrapping `NSTextField(wrappingLabelWithString:)` labels reflow and the rows grow, both when the
    row is reloaded and when the window narrows.
  - `reloadData(forRowIndexes:columnIndexes:)` re-measures the reloaded row.
  - After a full `reloadData()` with 60 rows while scrolled to the top, scrolling the clip view
    straight to `table.frame.height - visibleHeight` stopped about 2 400 pt short. Rows below had
    only estimated heights (`rowHeight`, default 24) until they were laid out.
  - Calling `scrollRowToVisible(lastRow)` first, then `layoutSubtreeIfNeeded()`, then scrolling the
    clip view to the table's bottom landed exactly at the bottom. That held after a full reload,
    after appending a row, and after five successive growths of a last row taller than the view.
  - `scrollRowToVisible` alone shows only the top of a last row that is taller than the view.
    Calling `scrollToEndOfDocument(_:)` on the table did not move it, and calling it on the
    `NSScrollView` raised an unrecognized-selector exception.
  - A prototype cell measured with `fittingSize` at the column width reported one line (16 pt) for a
    long wrapping label whose `preferredMaxLayoutWidth` was left at 0.
  - A selectable wrapping label in a cell becomes first responder on click, and text can be
    selected. This held with `refusesFirstResponder = true` on the table and
    `tableView(_:shouldSelectRow:)` returning false. No override is needed for it.
  - With `.inset`, the column is 32 pt narrower than the table (16 pt system inset per side), and
    the table adds 10 pt above the first row and below the last.
  - `stack.topAnchor.constraint(equalToSystemSpacingBelow: cell.topAnchor, multiplier: 1)`
    resolves to 20 pt, and the default vertical `NSStackView` spacing is 8 pt.
  - An `NSStackView` detaches hidden arranged views, so a hidden body or indicator takes no space.
- Other facts measured on this machine:
  - `NSTextField(string:)` is bezeled and editable, uses the 13 pt system font (the same size as
    `.body`), and is 24 pt tall.
  - Setting `stringValue` while the field is being edited updates the field editor text.
  - `isEnabled = false` ends editing, while assigning `isEnabled = true` or `placeholderString`
    during editing does not interrupt it.
  - `window.makeFirstResponder(field)` selects all of the field's text, even when the field is
    already being edited.
  - `NSProgressIndicator` with `style = .spinning` is 32×32 at its default control size. Its
    `isDisplayedWhenStopped` is true, so a stopped indicator stays visible unless it is hidden.
  - A plain `NSView`'s `layoutMarginsGuide` insets 20 pt on all four sides.
  - The system spacing between an `NSBox` separator and a text field below it is 6 pt.
  - `NSFont.preferredFont(forTextStyle: .headline)` is 13 pt bold.
  - SF Symbol `stop.fill` exists.
  - `NSWindow.subtitle` shows under the title once the window has a toolbar.
  - `NSToolbarItemValidation.validateToolbarItem(_:)` is how AppKit asks a toolbar item's target
    whether the item is enabled.
- Remaining literal numbers after this task: the initial content size 560×640 and `minSize`
  380×320 of the chat window, and the 24 pt stick-to-bottom threshold. The threshold is scroll
  behaviour, not styling.

## Plan
1. Create `Sources/OddFrog/ChatMessageCell.swift`: `@MainActor final class ChatMessageCell: NSTableCellView`.
   - `static let identifier = NSUserInterfaceItemIdentifier("message")`, assigned to `identifier`
     in `init()`. `required init?(coder:)` returns nil, as elsewhere in the target.
   - Subviews, in a vertical `NSStackView` with `alignment = .leading` and default spacing:
     - `speaker`: `NSTextField(labelWithString:)` with `NSFont.preferredFont(forTextStyle: .headline)`.
     - `body`: `NSTextField(wrappingLabelWithString:)` with its default font and selectability.
       Set `textField = body`.
     - `indicator`: `NSProgressIndicator` with `style = .spinning`. Do not set `controlSize`.
   - Pin the stack's leading and trailing edges to the cell's. Pin its top with
     `constraint(equalToSystemSpacingBelow: topAnchor, multiplier: 1)`, and its bottom flush to the
     cell's bottom. Consecutive messages are then separated by one system spacing (20 pt).
     - Rejected: system spacing at both the top and the bottom, which gives 40 pt between
       messages.
     - Rejected: `intercellSpacing`, which would need a literal.
   - `func show(_ text: String, speaker name: String, waiting: Bool)`:
     - Set the speaker and body strings.
     - Hide `body` and show `indicator` when `waiting`, and the reverse otherwise.
     - Call `startAnimation(nil)` or `stopAnimation(nil)` to match.
     - Set the indicator's accessibility label to "Waiting for \(name)".
     - VoiceOver then reads each row as speaker, then text. Today the speaker is conveyed only by
       colour and alignment.
2. `Sources/OddFrog/ChatTranscriptView.swift`: rewrite the internals and keep the class an `NSView`
   that the controller pins in place.
   - Delete `Style`, `Bubble`, `DocumentView`, and the `document` and `stack` properties, and
     replace them with:
     - `scroll` (`hasVerticalScroller = true`, `autohidesScrollers = true`, no `scrollerStyle`,
       `borderType` or `drawsBackground` assignments),
     - `table` (`NSTableView`),
     - `messages: [PluginMessage]`, `replyID: String?`, `assistant: String`,
     - `private let stickyBottom: CGFloat = 24`.
   - Table setup:
     - One `NSTableColumn(identifier: ChatMessageCell.identifier)` with
       `resizingMask = .autoresizingMask`.
     - `headerView = nil`, `style = .inset`, `usesAutomaticRowHeights = true`,
       `refusesFirstResponder = true`.
     - `dataSource` and `delegate` are the view itself, which conforms to `NSTableViewDataSource`
       and `NSTableViewDelegate`.
     - `setAccessibilityLabel("Transcript")`.
     - `scroll.documentView = table`. Pin the scroll view to the view's four edges.
   - Row height decision: automatic row heights. The wrapping body reflows on resize for free.
     - Rejected: `tableView(_:heightOfRow:)` from a prototype cell's `fittingSize`, as the launcher
       does. A wrapping label measures as one line unless `preferredMaxLayoutWidth` is set by hand
       for each width, and every row would need re-measuring on every resize. The launcher needs
       exact heights only to size its panel.
   - Data source and delegate:
     - `numberOfRows` returns `messages.count`.
     - `tableView(_:viewFor:row:)` reuses
       `tableView.makeView(withIdentifier: ChatMessageCell.identifier, owner: nil) as? ChatMessageCell`
       or creates one. It calls `show(message.text, speaker: message.role == .user ? "You" : assistant, waiting: message.id == replyID && message.text.isEmpty)`.
     - `tableView(_:shouldSelectRow:)` returns false. A transcript row is not a choosable item.
   - Change the signature to `func render(_ messages: [PluginMessage], streaming replyID: String?, assistant: String)`:
     - Record `sticky = isNearBottom()` before anything changes, then store the new values.
     - If the id list and `assistant` are unchanged, compute the rows whose `text` changed plus the
       rows whose id equals the previous or the new `replyID` (their waiting state may have
       flipped). Call `reloadData(forRowIndexes:columnIndexes:)` and then
       `noteHeightOfRows(withIndexesChanged:)` for those rows.
     - Otherwise call `reloadData()`.
     - If `sticky`, call `scrollToBottom()`.
     - Rejected: `reloadData()` on every delta. It rebuilds every visible cell per token and drops
       any text selection the user holds in earlier messages.
   - `isNearBottom()` keeps today's logic, reading `table.frame.height` instead of the old
     document view's height.
   - `scrollToBottom()`:
     - Return when there are no rows.
     - `table.scrollRowToVisible(table.numberOfRows - 1)`, then `table.layoutSubtreeIfNeeded()`.
     - If the table is taller than `scroll.contentView.bounds.height`, scroll the clip view to
       `NSPoint(x: 0, y: table.frame.height - visibleHeight)` and call `reflectScrolledClipView`.
     - The first call realizes the tail rows, so the height is measured, not estimated. The final
       scroll shows the end of a reply that is taller than the view. See Context for the
       measurements.
3. `Sources/OddFrog/ChatWindowController.swift`:
   - Delete the `Capsule` class and the `capsule` property, `inputScroll`, `placeholderLabel`,
     `statusLabel`, `stopButton`, `inputHeight`, `updateInputHeight()` and every call to it, and
     the whole text-view setup block at the top of `buildContent()`.
   - `input` becomes `NSTextField(string: "")`. Keep the default bezel, font and size. Do not set
     `controlSize`, `font`, `usesSingleLineMode`, `maximumNumberOfLines` or any substitution
     property. The system text-substitution preferences then apply through the field editor.
   - Conformances become
     `NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSToolbarDelegate, NSToolbarItemValidation`.
     `input.delegate = self`.
   - `textDidChange(_:)` becomes `controlTextDidChange(_:)`, with the same body minus
     `updateInputHeight()`. It reads `input.stringValue`.
   - `textView(_:doCommandBy:)` becomes `control(_:textView:doCommandBy:)`:
     `insertNewline(_:)` calls `submit()` and returns true, and everything else returns false.
     - Delete the `cancelOperation` case. Esc no longer closes the window, and ⌘W does.
     - Delete the `insertLineBreak` case, which already returned false.
   - Replace every `input.string` with `input.stringValue`, and every `input.isEditable` with
     `input.isEnabled`. `input.undoManager?.removeAllActions()` stays: the responder chain resolves
     it to the window's undo manager, which the field editor uses.
   - Add `private func focusInput()` that calls `window?.makeFirstResponder(input)` only when
     `input.currentEditor() == nil`. Use it in `finish(_:session:id:)` and `activateWindow()`.
     Otherwise a completed reply would select all of the text the user typed while waiting.
   - `render()` passes `assistant: session?.pluginName ?? ""`.
   - `refresh()`:
     - `window?.subtitle` gets the same three-way choice as today's status label.
     - `input.isEnabled = session?.invalidated != true` and
       `input.placeholderString = session?.placeholder`.
     - Finish with `window?.toolbar?.validateVisibleItems()`, so Stop's enabled state follows at
       once instead of waiting for the next event.
   - Toolbar: in `init()`, after `super.init(window:)`, create `NSToolbar(identifier: "chat")`, set
     its delegate to `self`, and assign it to `window.toolbar`. Leave `toolbarStyle`, `displayMode`
     and customization at their defaults.
     - `static let stopItem = NSToolbarItem.Identifier("stop")`.
     - `toolbarDefaultItemIdentifiers(_:)` and `toolbarAllowedItemIdentifiers(_:)` both return
       `[.flexibleSpace, Self.stopItem]`, so Stop sits at the trailing end.
     - `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` returns, for `stopItem`, an
       `NSToolbarItem` with `label = "Stop"`, `toolTip = "Stop"`,
       `image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")`,
       `target = self` and `action = #selector(stop(_:))`. It returns nil otherwise.
     - `stop()` becomes `@objc private func stop(_ sender: Any?)` with the same body.
     - `validateToolbarItem(_:)` returns `session?.isSending == true` for `stopItem`, and true for
       anything else.
     - Rejected: toggling `isHidden` on the item between sends, which makes the titlebar content
       jump on every send.
     - Rejected: a spinner item in the toolbar. The waiting state already shows in the reply row,
       and a 32 pt spinner does not fit a toolbar without forcing its control size.
   - `buildContent()`: keep the `NSBox` separator, and add a plain `composer` `NSView` below it.
     - Constraints:
       - The transcript is pinned to the content view's top, leading and trailing edges, and to
         the separator's top.
       - The separator spans the width, with its bottom on the composer's top.
       - The composer is pinned to the content view's leading, trailing and bottom edges.
       - `input` is pinned to all four edges of `composer.layoutMarginsGuide`, which gives the
         system 20 pt on every side.
     - Rejected: pinning `input` straight to `content.layoutMarginsGuide` with system spacing below
       the separator, which gives 6 pt above the field and 20 pt below it.
4. `docs/query-plugins.md`, Chat section:
   - "`messageDelta` events append to the reply bubble" becomes "append to the reply".
   - "A failed or cancelled send puts the text back into the input with an error line." becomes
     "A failed or cancelled send puts the text back into the input and shows the error as the
     window subtitle."

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
- The only size, spacing or styling literals left in the three chat files are the ones listed at
  the end of Context. Index arithmetic such as `numberOfRows - 1`, `multiplier: 1` on system
  spacing, and the zero `x` of the scroll point are not styling and are fine. Set no `textColor`
  anywhere in them.
- `ChatSession.swift`, `AppDelegate.swift` and the public members that `AppDelegate` calls on
  `ChatWindowController` (`performSend`, `cancelSend`, `present`, `apply`, `pluginsDidReload`)
  stay unchanged.
- Leave `NSApp.activate(ignoringOtherApps: true)` in `activateWindow()` as it is.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed)
- `grep -n "Capsule\|Bubble\|DocumentView\|typingGlyph\|updateInputHeight\|placeholderLabel\|statusLabel\|stopButton\|scrollerStyle\|cancelOperation" Sources/OddFrog/ChatWindowController.swift Sources/OddFrog/ChatTranscriptView.swift Sources/OddFrog/ChatMessageCell.swift` prints nothing
- `grep -n "systemFont(ofSize\|NSColor(\|cornerRadius\|\.layer\|controlSize\|bezelStyle\|textColor\|isAutomatic" Sources/OddFrog/ChatWindowController.swift Sources/OddFrog/ChatTranscriptView.swift Sources/OddFrog/ChatMessageCell.swift` prints nothing

## Manual review
Needs an OpenAI-compatible server at the Chat plugin's base URL (Settings › Plugins › Chat, default
`http://localhost:11434/v1`, for example Ollama with `llama3.2`).
1. `make run`, then type `chat` in the launcher and press Return on "New chat". The chat window has
   a toolbar with a disabled Stop button and no subtitle. The composer is a standard rounded text
   field showing "Message…", with system margins, below a separator line.
2. Type `write three paragraphs about frogs` and press Return. A row appears with a bold "You" and
   your text. A row below it shows a bold "Chat" with a spinner. The subtitle reads "Waiting for
   Chat…" and Stop is enabled.
3. As text streams, the spinner is replaced by the reply and the view stays pinned to the bottom.
   Start another long reply and scroll up while it streams: the view stays where you put it.
4. Drag across part of one message: the text highlights, and ⌘C copies it. Clicking a row never
   highlights the row itself. There are no coloured bubbles, and both speakers are left-aligned.
5. While a reply streams, type the next message into the field. When the reply finishes, your
   typed text is still there with the caret where you left it, and not all selected.
6. Send another message and press Stop. The subtitle reads "Stopped.", the pair disappears, the
   message text returns to the field, and Stop is disabled.
7. Press Esc in the composer: the window stays open. ⌘W closes it.
8. Reopen a chat and choose Reload Plugins from the status menu. The subtitle shows "Chat was
   reloaded. Close this window and open the chat again.", the field is disabled, and transcript
   text is still selectable.
9. Type `chat what is two plus two` and press Return on "Ask “what is two plus two”". The window
   opens and sends that prompt immediately.
10. Optional: with VoiceOver on, moving through the transcript reads the speaker before each
    message, and the spinner reads "Waiting for Chat".

## Out of scope
- A multi-line or auto-growing composer, and a keyboard shortcut for Stop.
- Markdown rendering, per-speaker alignment, avatars, or any colour or fill for either speaker.
- `ChatSession`, the Chat plugin, the `PluginView` chat contract, and `AppDelegate`.
- `NSApp.activate(ignoringOtherApps:)`, which stays.
- The document and month windows, which are covered by their own tasks.

## Open questions
none
