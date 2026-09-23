# Task: Settings › Plugins becomes a SwiftUI grouped form driven by an @Observable model

## Goal
The Plugins pane is a SwiftUI `Form` with `.formStyle(.grouped)`, hosted in an
`NSHostingController`. There is one section per package, and each section starts with its enable
switch. A package's trigger field, its manifest-declared settings, and its Manage Links button (when
the package has one) follow as rows. Validation messages appear in red under the package they
belong to. At the bottom is a Reload Plugins row with the trusted-code footnote. All behaviour of
today's `PluginsPane` is kept: toggles, trigger editing with conflict and validity checks, every
setting type including the folder picker, failure and discovery-error display, reload, and Manage
Links. `AppDelegate` does not change.

## Files
- Sources/OddFrog/PluginsPaneModel.swift           (create)
- Sources/OddFrog/PluginsPaneView.swift            (create)
- Sources/OddFrog/CommitTextField.swift            (create)
- Sources/OddFrog/SettingsWindowController.swift   (modify — type of `pluginsPane` and the Plugins tab child)
- Sources/OddFrog/PluginsPane.swift                (delete)
- Sources/OddFrog/AppDelegate.swift                (read — `wirePlugins()` callbacks and `updatePluginsPane()`; stay textually unchanged)
- Sources/OddFrogCore/PluginPackage.swift          (read — `PluginSettingDefinition`, `validate`, `PluginPackage.setting(in:)`, `isEnabled(settings:)`, `trigger(in:)`, `triggerConflict(_:among:settings:)`)
- Sources/OddFrogCore/PluginTrigger.swift          (read — `text`, `label`, `replacing(_:)`)
- Sources/OddFrogCore/Item.swift                   (read — `LauncherItem.abbreviate(_:)`)
- Sources/OddFrog/SettingsLayout.swift             (read — stays; the Items pane still calls `SettingsLayout.helper`, spec 48 deletes the file)
- docs/query-plugins.md                            (read — describes trigger editing; still accurate, no change)

## Context
- Precondition: spec 46 has landed.
  - `SettingsWindowController` imports SwiftUI. Its content is an `NSSplitViewController` whose
    detail is `private let paneController = NSTabViewController()` (`tabStyle = .unspecified`).
  - `buildContent()` adds the tab children in `SettingsPane` order: an `NSHostingController` for
    General, `hosted(makeItemsPane())` and `hosted(pluginsPane)`.
  - `hosted(_:)` wraps a view in a plain `NSViewController` and pins it to the layout margins.
  - `let pluginsPane = PluginsPane()` is still the AppKit view. `SettingsLayout.hairline()`
    returns an `NSBox` separator. `GeneralPaneModel` and `GeneralPaneView` show the model
    pattern this spec follows.
  - `showPane(_:)` calls `sidebar.focus()` (makes the sidebar table first responder) before it
    swaps the tab. A click on a sidebar row does the same. So a text field in the pane being left
    loses focus while it is still in the window, whether the switch comes from a click, from ⌘I in
    the launcher, or from `select(_:)`.
- `AppDelegate` wiring, all through `settingsWindow.pluginsPane`:
  - In `wirePlugins()`, AppDelegate sets `onReload` (→ `reloadPlugins()`) and
    `onToggle: (String, Bool)` (writes a `PluginSetting` with the new `enabled`).
  - It also sets `onSetting: (String, String, JSONValue)` (writes `values[key]`),
    `onTrigger: (String, String?)` (writes or clears `trigger`) and `onManageLinks` (sets
    `settingsWindow.links`, then calls `manageLinks()`).

    Each writer calls `applySettings(_:persist: true)`. That validates and saves `settings.toml`.
    It then either reloads plugins (enable or trigger changes) or calls
    `plugins.updateSettings`.
  - Both paths end in `PluginCoordinator.onChange`, which calls `updatePluginsPane()`. That
    function calls `settingsWindow.update(pluginSettings:)` and then
    `settingsWindow.pluginsPane.update(packages:settings:failures:errors:)` with
    `plugins.packages`, `settings.plugins`, `plugins.failures` and `plugins.discoveryErrors`.
  - When `applySettings` rejects a change it only reports to the menu bar, so the pane gets no
    update.
- `PluginsPane` behaviour today. Every item needs a home in the new pane:
  - `update(…)` returns early when all four inputs equal the last ones. Otherwise it rebuilds
    everything and hides the message line.
  - Grouping: bundled packages come first. A "Bundled" heading is shown only when installed
    (non-bundled) packages also exist. Installed packages follow under an "Installed" heading. The
    order within each group is the coordinator's order.
  - Per package, a card:
    - Title `manifest.name`, with the subtitle `"\(manifest.version) · \(source) · \(state)"`.
      `source` is `"Bundled"` or `LauncherItem.abbreviate(package.directory.path)`. `state` is
      `failures[id]`, or `"Ready"`/`"Off"` from `package.isEnabled(settings:)`. The subtitle is
      red when there is a failure.
    - An enable switch that calls `onToggle(id, isOn)`.
  - Trigger row, when `manifest.trigger` is non-nil:
    - The title is `trigger.label` ("Keyword" or "Prefix") and the subtitle is
      `"Type this first in the launcher to use \(manifest.name)."`.
    - The field's placeholder is the manifest `trigger.text`. Its value is the resolved trigger,
      `(try? package.trigger(in: settings))?.text ?? trigger.text`.
    - When editing ends, the text is trimmed and, for keywords, lowercased.
      - Empty or equal to the manifest text: hide the message, show the manifest text, and call
        `onTrigger(id, nil)` if a stored override exists.
      - Otherwise `trigger.replacing(text)` validates it. On a conflict
        (`package.triggerConflict(candidate, among: packages, settings: settings)`), show
        `"\(name): \(trigger.label) '\(text)' is already used by \(other.manifest.name)."` and
        revert the field to the resolved text.
      - If invalid, show `"\(name): \(error)"` and revert.
      - Otherwise hide the message, and call `onTrigger(id, text)` when `text` differs from the
        resolved text.
  - Setting rows come from `manifest.settings`. The title is `definition.title`. The value is
    `package.setting(in: settings)?.values?[key] ?? definition.defaultValue`. Every commit runs
    `definition.validate(value)`. Success hides the message and calls
    `onSetting(id, key, value)`. Failure shows `"\(name): \(error)"`.
    - `boolean`: a switch with `.bool`.
    - `choice`: a pop-up of `definition.choices`, committing `.string(title)`.
    - `string`: a text field with the placeholder `definition.defaultValue.string`. It commits
      `.string(text)` when editing ends.
    - `number`: a text field. The placeholder and value use `format(_:)`, which prints whole
      numbers without a decimal point. When both `minimum` and `maximum` exist, the subtitle is
      `"\(format(min)) – \(format(max))"`. When editing ends it commits
      `Double(trimmed).map(JSONValue.number) ?? .null`.
    - `folders`: the subtitle lists the paths through `LauncherItem.abbreviate`, one per line, or
      reads "No folders yet.".
      - "Add…" opens a directories-only, multiple-selection open panel with the prompt "Add", as a
        sheet. It rewrites paths under the home directory as `~/…`, skips duplicates, appends, and
        commits `.array` of `.string`.
      - "Clear" is disabled when the list is empty and commits `.array([])`.
  - When the package is enabled, has no failure, and `manifest.capabilities` contains
    `"links.manage@1"`, a "Links" row appears. Its subtitle is "Add, edit and remove URL
    commands." and its "Manage Links…" button calls `onManageLinks()`.
  - When there are no packages and no errors, the pane shows
    "No plugins found. Build the app bundle to include bundled plugins.".
  - Each discovery error is shown as its own red, wrapping line.
  - The footer holds the text "Local packages are trusted code. Enable user packages explicitly;
    changes to a package restart its providers." and a "Reload Plugins" button that calls
    `onReload()`.
  - The single red message line sits above the footer and stays hidden until a validation fails.
- Facts about SwiftUI in a grouped form:
  - `TextField` renders inline and trailing-aligned, with its `prompt` shown when it is empty.
    `Picker` renders as a pop-up, and `Toggle` as a switch.
  - A plain `Button` row renders as a push button.
  - A label made of two `Text` views renders as a title plus a secondary subtitle.
  - `Section { } header: { } footer: { }` puts a bold header above the card and secondary text
    below it.
  - A `TextField(text:)` binding is written on every keystroke. `.onSubmit` fires only on Return.
    Focus loss is observable only through `@FocusState`.
  - A `Text` built from a string literal is a `LocalizedStringKey` and renders Markdown, so URLs
    in literals become links. `Text(someStringVariable)` and `Text(verbatim:)` render verbatim.
  - `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`
    presents the open panel as a sheet. `.fileDialogConfirmationLabel(_:)` sets its button title.
- Bundled settings exercise every type except `number` in `Plugins/*/plugin.toml`:
  - `boolean`: Calculator `currency`, Scripts `watch`.
  - `string`: the four Chat settings, Terminal `custom_command`, Web `url`.
  - `choice`: Terminal `app`.
  - `folders`: Scripts `folders`.

  The one `number` is Windows `cascade_step` (16–120, default 32).

## Plan
1. Create `Sources/OddFrog/PluginsPaneModel.swift`:
   `@Observable @MainActor final class PluginsPaneModel`, importing `Foundation`, `Observation`,
   `OddFrogCore` and `OddFrogPluginAPI`.
   - State, each with `private(set)`:
     - `packages: [PluginPackage]`, `settings: [PluginSetting]`, `failures: [String: String]`
       and `errors: [String]`;
     - `message: (package: String, text: String)?`, the manifest ID the message belongs to plus
       the text.
   - Callbacks, each `@ObservationIgnored var`, with the same names and types as `PluginsPane`:
     `onToggle`, `onReload`, `onSetting`, `onTrigger` and `onManageLinks`. This is why
     `AppDelegate` compiles unchanged.
   - `func update(packages:settings:failures:errors:)` keeps today's early return when nothing
     changed. Otherwise it assigns all four and sets `message = nil`.
   - `func value(of definition: PluginSettingDefinition, in package: PluginPackage) -> JSONValue`
     returns the stored value or the default.
   - `func resolvedTrigger(of package: PluginPackage) -> String` returns
     `(try? package.trigger(in: settings))?.text ?? package.manifest.trigger?.text ?? ""`.
   - `func commit(_ value: JSONValue, for definition: PluginSettingDefinition, in package: PluginPackage)`
     ports the `row(for:value:package:)` closure. `message` becomes
     `(package.manifest.id, "\(package.manifest.name): \(error)")`.
   - `func commitTrigger(_ raw: String, for package: PluginPackage)` ports the `triggerRow`
     closure line for line, with the same message texts and the same `onTrigger` calls.
     - It starts with `guard let trigger = package.manifest.trigger else { return }`.
     - What the closure captured when the row was built is read at commit time instead:
       `stored` is `package.setting(in: settings)?.trigger`, and `resolved` is
       `resolvedTrigger(of: package)`.
     - The conflict check is `package.triggerConflict(candidate, among: packages, settings: settings)`.
     - It does not touch the field. The view shows `resolvedTrigger(of:)` again once its draft is
       dropped, and that is today's revert.
   - `func addFolders(_ urls: [URL], for definition: PluginSettingDefinition, in package: PluginPackage)`
     ports `SettingBinding.addFolders`: the `~` rewrite, dedup and append onto the current value.
     It then calls `commit(.array(…))`.
   - `static func format(_ number: Double) -> String` moves over unchanged from `PluginsPane`.
2. Create `Sources/OddFrog/CommitTextField.swift`: `struct CommitTextField: View`. It is a
   `TextField` that commits only when the user presses Return or leaves the field, as
   `controlTextDidEndEditing` does today.
   - Properties: `let title: String`, `let subtitle: String?`, `let prompt: String`,
     `let value: String` and `let onCommit: (String) -> Void`.
   - `@State private var draft: String?` and `@FocusState private var focused: Bool`.
   - The body is
     `TextField(text: Binding(get: { draft ?? value }, set: { draft = $0 }), prompt: Text(verbatim: prompt)) { Text(title); if let subtitle { Text(subtitle) } }`,
     then `.focused($focused)`, `.onSubmit(commit)` and
     `.onChange(of: focused) { _, isFocused in if !isFocused { commit() } }`.
   - `commit()` returns when `draft` is `nil`. Otherwise it sets `draft = nil` and calls
     `onCommit(text)`. Dropping the draft makes the field show the model value again, which
     reverts it after a rejected edit.

   Decision: a per-field view with its own draft. Rejected alternatives: binding straight to the
   model, which would save `settings.toml` on every keystroke, and one form-wide `FocusState` with
   string field IDs. For string and number settings this also reverts a rejected value, where
   today the invalid text stays in the field. The red message still explains the rejection.
3. Create `Sources/OddFrog/PluginsPaneView.swift`: `struct PluginsPaneView: View` with
   `let model: PluginsPaneModel`, importing `OddFrogCore`, `OddFrogPluginAPI`, `SwiftUI` and
   `UniformTypeIdentifiers`. It has `@State private var choosingFolders = false` and
   `@State private var folderTarget: (package: PluginPackage, definition: PluginSettingDefinition)?`.
   - Body: `Form { … }.formStyle(.grouped)`, then
     `.fileImporter(isPresented: $choosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true)`.
     The completion handler ignores failures, and on success calls
     `model.addFolders(urls, for: target.definition, in: target.package)` with `folderTarget`.
     Last comes `.fileDialogConfirmationLabel("Add")`. `folderTarget` is kept separate from the
     presentation flag so it is still set when the completion runs.
   - Inside the form, in this order:
     1. Bundled packages, then installed ones. Use
        `ForEach(Array(group.enumerated()), id: \.element.manifest.id)` and call a
        `@ViewBuilder` helper `section(for:header:)`.
        - The first bundled package gets the header `"Bundled"` only when installed packages
          exist.
        - The first installed package always gets `"Installed"`.
        - The helper builds `Section { rows } header: { Text(header) } footer: { footer }` when it
          has a header, and `Section { rows } footer: { footer }` otherwise.
        - The footer is `Text(message.text).foregroundStyle(.red)`, and only when
          `model.message?.package` equals this package's ID.
     2. When there are no packages and no errors:
        `Section { Text("No plugins found. Build the app bundle to include bundled plugins.").foregroundStyle(.secondary) }`.
     3. When there are errors: a `Section` with one `Text(error).foregroundStyle(.red)` per
        error, as `ForEach(Array(model.errors.enumerated()), id: \.offset)`.
     4. `Section { Button("Reload Plugins") { model.onReload?() } } footer: { Text("Local packages are trusted code. Enable user packages explicitly; changes to a package restart its providers.") }`.
   - Rows for one package, from a `@ViewBuilder` helper:
     1. The enable row is
        `Toggle(isOn: Binding(get: { enabled }, set: { model.onToggle?(manifest.id, $0) }))`.
        Its label is `Text(manifest.name)` plus the status text, which gets
        `.foregroundStyle(.red)` when there is a failure. Both strings are exactly as today.
     2. When the package has a trigger: `CommitTextField(title: trigger.label, subtitle: "Type this first in the launcher to use \(manifest.name).", prompt: trigger.text, value: model.resolvedTrigger(of: package))`,
        committing through `model.commitTrigger`.
     3. `ForEach(manifest.settings, id: \.key)`, one row per setting:
        - `boolean`: `Toggle(definition.title, isOn:)`. The binding reads `value.bool == true` and
          commits `.bool`.
        - `choice`: `Picker(definition.title, selection:)` over
          `ForEach(definition.choices ?? [], id: \.self) { Text($0).tag($0) }`. The binding reads
          `value.string ?? ""` and commits `.string`.
        - `string`: a `CommitTextField` with prompt `definition.defaultValue.string ?? ""`, value
          `value.string ?? ""` and no subtitle, committing `.string(text)`.
        - `number`: a `CommitTextField`.
          - Prompt: `definition.defaultValue.number.map(PluginsPaneModel.format) ?? ""`.
          - Value: `value.number.map(PluginsPaneModel.format) ?? ""`.
          - Subtitle: the "min – max" text when both bounds exist.
          - It commits `Double(text.trimmingCharacters(in: .whitespaces)).map(JSONValue.number) ?? .null`.
        - `folders`: a `LabeledContent`.
          - Its content is an `HStack` with `Button("Add…")`, which sets `folderTarget` and then
            `choosingFolders = true`, and `Button("Clear")`, which commits `.array([])` and has
            `.disabled(folders.isEmpty)`.
          - Its label is `Text(definition.title)` plus the folder list or "No folders yet." as the
            subtitle.
     4. The links row, under today's condition:
        `LabeledContent { Button("Manage Links…") { model.onManageLinks?() } } label: { Text("Links"); Text("Add, edit and remove URL commands.") }`.

   Set no fonts, frames, paddings or widths. The grouped style lays out the rows, so today's
   120/90/290pt field widths go away. The only colours are `.red` and `.secondary`.
4. `Sources/OddFrog/SettingsWindowController.swift`:
   - `let pluginsPane = PluginsPane()` becomes `let pluginsPane = PluginsPaneModel()`.
   - In `buildContent()`, the third tab child becomes
     `NSHostingController(rootView: PluginsPaneView(model: pluginsPane))` with
     `sizingOptions = []`. The form handles its own margins and the titlebar safe area, so it does
     not go through `hosted(_:)`.
   - `hosted(_:)` stays, because the Items pane still uses it.
5. Delete `Sources/OddFrog/PluginsPane.swift`. That removes `PluginsPane`, `FlippedView` and
   `SettingBinding`.

Decision: one section per package, with the enable switch as its first row, which mirrors today's
cards. Rejected alternative: using the package name as the section header with an "Enabled" row.
It would push the "Bundled"/"Installed" group headings out of the header slot. Validation messages
move from one line above the footer into the footer of the package that failed, where the user is
looking. The text is unchanged.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners, no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and `if … { return … }` bodies where neighbouring code uses them, one type per file for new types, and no new package dependencies (Apple system frameworks such as SwiftUI and Observation are fine).
- The deployment target is macOS 26 (after spec 43): call macOS 26 APIs directly, add no `#available`/`@available` checks, and use nothing that needs macOS 27.
- No hand-styling: no literal font sizes (use a control's default font, `NSFont.preferredFont(forTextStyle:)`, or SwiftUI's default fonts / text styles), no literal or hex colours and no custom fills (semantic system colours only), no corner radii, no `draw(_:)`/`drawSelection`/`drawBackground`/`updateLayer` overrides or layer styling, no forced `controlSize`, no bezel/border overrides, no hover effects, and system spacing (layout margins, system-spacing anchors, NSStackView/NSGridView/SwiftUI defaults) instead of literal padding. Literal numbers are allowed only where AppKit has no system value (initial window content sizes, the launcher panel width and its glass corner radius) — the spec must list which literals remain.
- This spec leaves no literal sizes in the new files. The only colours are SwiftUI `.red` (errors
  and failures, which are `systemRed` today) and `.secondary`.
- `AppDelegate.swift` does not change. `settingsWindow.pluginsPane` keeps the callback names and
  types, and `update(packages:settings:failures:errors:)` keeps its signature.
- Every user-visible string in Context stays word for word. Use `Text(verbatim:)` for any string
  literal that contains a URL or braces.
- State lives in the `@Observable` model owned by `SettingsWindowController`. No Combine and no
  `ObservableObject`. `@State` is only for view-local drafts and the file-importer presentation.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
    else: do not start the app or a dev server, do not open a browser, do not take
    screenshots, do not write or run tests or scripts that are not listed in Plan, do not
    mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings other than the `nonisolated(unsafe)` warning in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`
- `swift test` passes (no tests are added or removed)
- `ls Sources/OddFrog/PluginsPane.swift 2>/dev/null` prints nothing
- `grep -rnw "PluginsPane\|SettingBinding\|FlippedView" Sources` prints nothing
- `grep -n "systemFont\|controlSize\|bezelStyle\|frame(width\|padding(" Sources/OddFrog/PluginsPaneView.swift Sources/OddFrog/CommitTextField.swift Sources/OddFrog/PluginsPaneModel.swift` prints nothing

## Manual review
1. `make run` and open Settings › Plugins. Every package is a grouped section whose first row
   shows the name, "version · Bundled · Ready", and a switch. Only when a user package is
   installed under `~/.config/odd-frog/v2/plugins` do the "Bundled" and "Installed" headings
   appear.
2. Calendar shows a "Keyword" row holding `cal`, with the subtitle "Type this first in the
   launcher to use Calendar.". Terminal shows "Prefix" holding `>`.
3. Set Calendar's keyword to `c` and press Tab. `c` now opens the agenda, and `settings.toml` has
   `trigger = "c"` under the calendar entry.
4. Set Reminders' keyword to `c` and press Return. The Reminders section footer says in red that
   the keyword is already used by Calendar, and the field shows `rem` again. Try `Two Words`: the
   invalid-keyword message appears and the field shows `rem`.
5. Clear Calendar's field and press Tab. It shows `cal` again and `trigger` is gone from
   `settings.toml`.
6. Terminal app is a pop-up with Terminal, agterm, iTerm2 and Custom. Choosing agterm writes
   `app = "agterm"`.
7. Chat's "API base URL" shows its value. Edit it and click into the Model field: the new URL is in
   `settings.toml` without pressing Return. Edit it again and press Return: saved as well. Edit
   Model, then click General in the sidebar without pressing Return. Back on Plugins, Model shows
   the new value and `settings.toml` has it.
8. Scripts › Script folders shows "No folders yet.". Add… opens a sheet whose confirm button reads
   "Add". Choose two folders: they are listed as `~/…`, and Clear empties the list.
9. Windows (off by default) › Cascade step shows 32 with the subtitle "16 – 120". Enter 500 and
   press Return: the Windows section footer reads "Windows: Invalid setting 'cascade_step'
   (expected number).", and the field shows 32 again.
10. Turn Web off and on. The status text switches between Off and Ready, and the provider
    restarts.
11. Commands shows "Links" with "Manage Links…", which opens the Manage Links sheet.
12. Reload Plugins rescans packages. A broken user `plugin.toml` shows its error as a red row.

## Out of scope
- The Items pane, `SettingsLayout.swift` and `GroupBox.swift` (spec 48), and the Manage Links sheet
  (spec 49).
- A `NumberFormatter` or stepper for number settings, and locale-aware decimal parsing. `Double(_:)`
  stays.
- A per-folder list with +/- buttons. Add…/Clear stay.
- A toggle that `applySettings` rejects keeps showing the new position until the next update,
  which is also true today.
- `AppDelegate.swift`, `PluginCoordinator` and the manifest format.

## Open questions
none
