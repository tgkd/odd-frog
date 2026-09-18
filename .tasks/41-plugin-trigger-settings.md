# Task: Let the user change a plugin's trigger keyword or prefix from Settings › Plugins

## Goal
Every plugin with exclusive activation (today Calendar `cal`, Reminders `rem`, Notes `note`,
Chat `chat`, Terminal prefix `>`, and any user package that declares one) shows a "Keyword" or
"Prefix" text field in its box in Settings › Plugins. Typing a new value there replaces the
manifest trigger: the launcher answers to the new trigger and no longer to the old one, the value
is stored as `trigger` in that plugin's `[[plugins]]` entry of `settings.toml`, and clearing the
field returns to the manifest default. Invalid and conflicting values are refused in the pane with
a red message. Provider subtitles that quote their own keyword follow the keyword the user typed.

## Files
- Sources/OddFrogCore/PluginTrigger.swift                              (create — trigger value type: validation, conflict rule)
- Sources/OddFrogCore/PluginPackage.swift                              (modify — `PluginSetting.trigger`, `PluginManifest.trigger`, effective trigger, `query(from:settings:)`, conflict lookup)
- Sources/OddFrogCore/PluginCoordinator.swift                          (modify — use effective triggers in reload/search/runQuery/validateSettings, drop private `conflicts`)
- Sources/OddFrogPluginAPI/PluginProtocol.swift                        (modify — computed `PluginQuery.keyword`)
- Sources/OddFrog/PluginsPane.swift                                    (modify — trigger row, `onTrigger` callback)
- Sources/OddFrog/AppDelegate.swift                                    (modify — `onTrigger` wiring, keep `trigger` on toggle, reload on trigger change)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarProvider.swift   (modify — `monthItem(keyword:)`)
- Plugins/Calendar/Sources/CalendarPluginCore/CalendarHandler.swift    (modify — pass the keyword to `monthItem`)
- Plugins/Reminders/Sources/RemindersPluginCore/RemindersProvider.swift (modify — "Type a title after … add." uses the typed keyword)
- Tests/OddFrogCoreTests/PluginTests.swift                             (modify — new tests listed in Plan)
- Plugins/Calendar/Tests/CalendarProviderTests.swift                   (modify — `monthItem(keyword:)` call site, one new test)
- Plugins/Calendar/Tests/CalendarHandlerTests.swift                    (modify — two `monthItem(keyword:)` call sites)
- Plugins/Reminders/Tests/RemindersProviderTests.swift                 (modify — one new test)
- docs/query-plugins.md                                                (modify — trigger override paragraph)
- Sources/OddFrog/SettingsLayout.swift                                 (read — `settingRow`, `helper`, `hairline`; must stay untouched)
- Sources/OddFrogCore/Settings.swift                                   (read — `Settings.parse` / `serialized`; must stay untouched)
- Sources/OddFrogCore/StoragePaths.swift                               (read — builds `PluginSetting` values during v1 migration; must stay untouched)

## Context
- Swift 6 package, `swift-tools-version: 6.0`, macOS 14, strict concurrency. Tests use the
  `Testing` framework (`@Test`, `#expect`, `#require`), not XCTest. No Xcode project.
  From the repo root today: `swift build` succeeds with exactly two warnings
  (`CGWindowListCreateImage` deprecated in `Sources/OddFrog/AppDelegate.swift`;
  `nonisolated(unsafe)` unnecessary in `Plugins/Shared/Sources/BundledFeatures/UnitRegistry.swift`),
  and `swift test` passes 247 tests (core 118, bundled features 56, Chat 23, Notes 18, and 16 each
  for Calendar and Reminders).
- `OddFrogCore` (Foundation + TOMLKit) must not import AppKit. `OddFrogPluginAPI` is Foundation
  only. `OddFrog` is the AppKit app. A new `.swift` file under `Sources/OddFrogCore` is picked up
  without touching `Package.swift`.
- Triggers today live only in manifests (`Plugins/*/plugin.toml`): `keyword = "cal"`,
  `keyword = "rem"`, `keyword = "note"`, `keyword = "chat"`, `prefix = ">"`. `PluginManifest`
  exposes them as `keyword: String?` and `prefix: String?`. `PluginManifest.parse` requires, for
  `activation = "exclusive"` only, exactly one of the two, keyword matching `^[a-z][a-z0-9_-]*$`,
  prefix non-empty with no whitespace; its error text is
  "Exclusive activation requires one valid keyword or prefix.". Non-exclusive manifests may not
  declare either. Manifests whose `api_version` is not 2 skip all of this validation and are kept
  visible as failed packages.
- `PluginPackage.query(from:)` is the only place a trigger is matched: prefix plugins need
  `text.hasPrefix(prefix)` (case-sensitive) and get the trimmed remainder; keyword plugins compare
  the lowercased first whitespace-separated word to the keyword and get the remainder or `""`;
  non-exclusive activations get the whole trimmed text; no activation gives `nil`. Its two callers
  are `PluginCoordinator.search` and `PluginCoordinator.runQuery`.
- `PluginCoordinator.reload` computes trigger conflicts among enabled exclusive packages with the
  private static `conflicts(_:_:)` (keyword/keyword equal; prefix/prefix either is a prefix of the
  other; keyword/prefix when the keyword starts with the prefix) and records
  "Exclusive trigger conflicts with <name>." in `failures` for both. `failures` is reset only by
  `reload`. `validateSettings` runs `manifest.validatedSettings` for every package and throws on
  the first problem; `updateSettings` applies value changes without restarting providers.
- `PluginSetting` (`PluginPackage.swift`) is `Codable` with synthesized coding: `id`, `enabled`,
  `source: String?`, `values: [String: JSONValue]?`. It is one `[[plugins]]` table in
  `settings.toml`, written by `Settings.serialized()` (TOMLKit `TOMLEncoder`; nil optionals are
  omitted) and read by `Settings.parse`. `values` is validated against the manifest's
  `[[settings]]` and unknown keys are rejected, so the override cannot live there.
- `AppDelegate` owns the wiring:
  - `pluginsPane.onToggle` rebuilds the entry as
    `PluginSetting(id:enabled:source: package.source, values: <old values>)` — every other field of
    the old entry is dropped.
  - `pluginsPane.onSetting` copies the existing entry (or creates one), sets one value, replaces
    the entry, and calls `applySettings(updated, persist: true)`.
  - `applySettings` calls `plugins.validateSettings`, reports failure through `report(_:)` (status
    menu + notification) and returns; otherwise it saves, then calls `reloadPlugins()` when any
    package's enabled state changed, else `plugins.updateSettings`.
  - `reloadPlugins()` restarts every provider and tells open document/chat windows that their
    plugin was reloaded. External edits of `settings.toml` reach `applySettings` with
    `persist: false`.
- `PluginsPane.box(for:settings:failures:)` builds one grouped box: a header row (name, status,
  enable switch), then for each manifest setting a `SettingsLayout.hairline()` and a row from
  `row(for:value:package:)`. Text fields are `NSTextField` with `.roundedBezel`, font 13,
  `usesSingleLineMode`, a fixed width constraint (90 for numbers, 290 for strings), the default as
  `placeholderString`, and a `SettingBinding` (private class at the bottom of the file) as
  delegate; the binding commits in `controlTextDidEndEditing`. Validation errors go into the red
  `message` label as "<plugin name>: <error>". `update(...)` returns early when packages,
  settings, failures and errors are all unchanged, so a refused edit leaves the typed text in the
  field unless the code resets it. `bindings` keeps the binding objects alive.
- Two provider strings quote their own keyword:
  `CalendarProvider.monthItem()` subtitle "Open a month calendar · cal month" and
  `RemindersProvider` "Type a title after rem add.". Providers receive `PluginQuery.fullQuery`
  (the whole launcher text, e.g. `"cal month"`) next to the stripped `query`. `PluginQuery` is
  `Codable` with synthesized coding, so a computed property is not part of the wire format.
  `CalendarProvider.monthItem()` is called from `CalendarProvider.respond`, from
  `CalendarHandler.handle("query")`, and from three test lines
  (`CalendarProviderTests` once, `CalendarHandlerTests` twice), all with `fullQuery` starting
  with `cal`.
- `PluginTests` helpers: `manifest(id:mode:extra:)` builds a manifest from TOML (`extra` carries
  lines such as `"activation = 'exclusive'\nkeyword = 'one'"`), `fixture(_:source:)` writes an
  executable provider, the private `echo` script answers a query with one row whose title is the
  stripped query, and `waitUntil` polls. `exclusiveTriggersSuppressCatalogsAndConflictsAreVisible`
  is the pattern for coordinator trigger tests.

## Plan
Approach: the override is one optional string, `trigger`, on `PluginSetting`. It replaces the
text of whichever trigger kind the manifest declares; the kind itself cannot change. The
alternative — a reserved key inside `values` — was rejected because `values` is validated against
the manifest and handed to the provider. A trigger change goes through `reloadPlugins()`, the
same path as the enable switch, because conflict failures are only computed and cleared in
`reload`; the cost (providers restart, open plugin windows show their reload notice) is accepted.

1. `Sources/OddFrogCore/PluginTrigger.swift`: add
   `public enum PluginTrigger: Sendable, Equatable { case keyword(String), prefix(String) }` with
   - `text: String` — the associated string;
   - `label: String` — `"Keyword"` or `"Prefix"`;
   - `replacing(_ text: String) throws -> PluginTrigger` — same kind with the new text, throwing
     `PluginError.message("Invalid keyword '<text>'. Use a lowercase letter followed by letters, digits, - or _.")`
     when a keyword fails `^[a-z][a-z0-9_-]*$`, and
     `PluginError.message("Invalid prefix '<text>'. Use one or more characters without spaces.")`
     when a prefix is empty or contains whitespace;
   - `conflicts(with other: PluginTrigger) -> Bool` — the exact rule of the coordinator's current
     private `conflicts(_:_:)`.
2. `PluginPackage.swift`:
   - `PluginSetting` gains `public var trigger: String?` and the initializer gains a trailing
     `trigger: String? = nil`. Coding stays synthesized.
   - `PluginManifest` gains a computed `trigger: PluginTrigger?`: `nil` unless
     `activation == .exclusive`; otherwise `.keyword` or `.prefix` from the stored fields.
     `parse` keeps its current checks and error text.
   - `PluginPackage.trigger(in settings: [PluginSetting]) throws -> PluginTrigger?`: `nil` when the
     manifest has no trigger (any `trigger` in the setting is then ignored); the manifest trigger
     when the matching setting (`setting(in:)`) has no `trigger`; otherwise
     `manifestTrigger.replacing(override)`.
   - Replace `query(from:)` with `query(from fullQuery: String, settings: [PluginSetting]) -> String?`.
     Behaviour is unchanged except that exclusive matching uses `try? trigger(in: settings)`; an
     exclusive package whose trigger cannot be resolved returns `nil`.
   - `PluginPackage.triggerConflict(_ candidate: PluginTrigger, among packages: [PluginPackage], settings: [PluginSetting]) -> PluginPackage?`:
     the first package other than `self` (compare `manifest.id`) that is enabled in `settings` and
     whose resolved trigger conflicts with `candidate`.
3. `PluginCoordinator.swift`: in `reload`, run the conflict loop over resolved triggers
   (`try? package.trigger(in: settings)`, skipping `nil`) with `PluginTrigger.conflicts(with:)`,
   and delete the private static `conflicts`. In the per-package loop, resolve the trigger inside
   the existing `do`/`catch` so an invalid override lands in `failures[id]`. `search` and
   `runQuery` pass `settings` to `query(from:settings:)`. `validateSettings` additionally calls
   `try package.trigger(in: updated)` for every package.
4. `PluginProtocol.swift`: add to `PluginQuery` a computed `public var keyword: String` — the first
   whitespace-separated word of `fullQuery`, lowercased, or `""` when there is none.
5. Providers: `CalendarProvider.monthItem(keyword: String)` builds the subtitle
   `"Open a month calendar · \(keyword) month"`; `respond` and `CalendarHandler` pass
   `request.keyword` / the decoded query's `keyword`. In `RemindersProvider` the subtitle becomes
   `"Type a title after \(request.keyword) add."`. Update the three existing test call sites to
   `monthItem(keyword: "cal")`.
6. `PluginsPane.swift`:
   - Add `var onTrigger: ((String, String?) -> Void)?` (plugin id, override or `nil` to reset).
   - In `box(for:settings:failures:)`, when `manifest.trigger` is non-nil, append a hairline and a
     trigger row directly after the header row and before the manifest settings.
   - The row: title `trigger.label`; helper subtitle
     `"Type this first in the launcher to use \(manifest.name)."`; a text field styled like the
     existing string field, width 120, `placeholderString` = the manifest trigger text,
     `stringValue` = the resolved trigger text (manifest text when the stored override is invalid).
   - On end of editing: trim whitespace; lowercase when the trigger is a keyword. Empty, or equal to
     the manifest text, means reset: call `onTrigger(id, nil)` only if an override is stored.
     Otherwise build the candidate with `manifestTrigger.replacing(text)`; on a thrown error show
     `"<plugin name>: <error>"` in `message`. If
     `package.triggerConflict(candidate, among: lastPackages, settings: lastSettings)` returns a
     package, show `"<plugin name>: <Label> '<text>' is already used by <other name>."`. In both
     refusal cases restore the field to the resolved trigger text and do not call `onTrigger`.
     Otherwise hide `message` and call `onTrigger(id, text)` only when the text differs from the
     resolved trigger text.
   - Implement the commit with a `SettingBinding` whose `commit` closure receives
     `.string(field.stringValue)`; it needs the field to restore it, so capture the field weakly in
     the closure. Append the binding to `bindings`.
7. `AppDelegate.swift`:
   - `pluginsPane.onTrigger`: same shape as `onSetting` — copy or create the entry, set
     `trigger`, replace the entry, `applySettings(updated, persist: true)`.
   - `onToggle`: carry the old entry's `trigger` into the rebuilt `PluginSetting`.
   - `applySettings`: `changed` is also true when, for any package,
     `try? package.trigger(in: updated.plugins)` differs from
     `try? package.trigger(in: settings.plugins)`.
8. Tests in `Tests/OddFrogCoreTests/PluginTests.swift`:
   - `triggerOverridesReplaceTheManifestTrigger`: a keyword package `cal` with override `c`
     answers `"c month"` → `"month"`, `"C"` → `""`, and `"cal month"` → `nil`; a prefix package `>`
     with override `>>`; an override on an `activation = "live"` package is ignored; override
     `"Bad Word"` makes `trigger(in:)` throw and `query(from:settings:)` return `nil`.
   - `triggerOverridesRoundTripThroughSettings`: `Settings(plugins: [PluginSetting(..., trigger: "c")])`
     → `serialized()` → `Settings.parse` keeps `trigger == "c"`; an entry without it parses to `nil`.
   - `triggerConflictsUseOverrides` (`@MainActor`): packages `one`/`two` with keywords
     `one`/`two`; reloading with `two` overridden to `one` gives two failures;
     `triggerConflict` returns the other package for `.keyword("one")` and `nil` for
     `.keyword("three")`, and ignores a disabled package; `validateSettings` throws for an
     override `"Bad Word"`; after reloading a single package overridden to `x`, polling
     `search("x hi", …)` yields a row titled `hi`.
   - `queryKeywordIsTheFirstTypedWord`: `PluginQuery(query: "", fullQuery: "  CaL  month").keyword == "cal"`
     and `""` for an empty `fullQuery`.
9. Plugin tests: in `CalendarProviderTests`, a bare query with `fullQuery: "c"` ends with a row
   whose subtitle is `"Open a month calendar · c month"`. In `RemindersProviderTests`, query `add`
   with `fullQuery: "todo add"` and full access gives the subtitle `"Type a title after todo add."`
   (mirror the file's existing `Input`/snapshot helpers).
10. `docs/query-plugins.md`: after the sentence about conflicting triggers, add that the user can
    replace a package's keyword or prefix text in Settings › Plugins, that the override is stored
    as `trigger` in the package's `[[plugins]]` entry of `settings.toml`, that the kind cannot
    change, and that providers should read the typed keyword from `fullQuery` instead of quoting
    their manifest keyword.

## Constraints
- Write no code comments of any kind in new or edited code: no `//`, no `///`, no `// MARK:`, no
  TODOs. Existing comments stay byte-for-byte.
- In new code every early return is braced with `return` on its own line
  (`guard let x else {\n    return\n}`), and one statement per line — do not copy the
  semicolon-joined, single-line style of the older lines in `PluginPackage.swift` and
  `PluginCoordinator.swift`. Do not reformat those older lines.
- One top-level type per new file. `OddFrogCore` must not import AppKit; `OddFrogPluginAPI` stays
  Foundation-only.
- Do not edit any `Plugins/*/plugin.toml`, `Settings.swift`, `StoragePaths.swift`, or
  `SettingsLayout.swift`. Manifest defaults stay `cal`, `rem`, `note`, `chat`, `>`.
- `PluginQuery`, `PluginSetting` and `PluginManifest` keep synthesized/existing coding; nothing
  new goes on the provider wire.
- No new dependencies, no gradients, no custom shadows, no emoji in UI text.
- Surgical changes only; do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with only the two pre-existing warnings listed in Context.
- `swift test` passes, with more tests than the 247 baseline and no existing test removed.

## Manual review
After `make run`, open Settings › Plugins:
1. Calendar, Reminders, Notes and Chat each show a "Keyword" field holding `cal`, `rem`, `note`,
   `chat`; Terminal shows a "Prefix" field holding `>`. Scripts, Web, Calculator show none.
2. Set Calendar's keyword to `c` and press Tab. In the launcher `c` lists the agenda and the last
   row reads "Open a month calendar · c month"; `cal` no longer reaches Calendar.
   `~/.config/odd-frog/v2/settings.toml` (under `$XDG_CONFIG_HOME` when set) has `trigger = "c"`
   under the calendar `[[plugins]]` entry.
3. Set Reminders' keyword to `c`: the red message says the keyword is already used by Calendar
   and the field returns to `rem`. Enter `Two Words`: the invalid-keyword message appears and the
   field returns to `rem`.
4. Clear Calendar's field and press Tab: it shows `cal` again, `cal` works, and `trigger` is gone
   from `settings.toml`.
5. Toggle Calendar off and on while it has an override: the override survives.
6. Set Reminders to `todo`, type `todo add`: the subtitle reads "Type a title after todo add."

## Out of scope
- Changing a trigger's kind (keyword ↔ prefix), several keywords per plugin, or giving triggers to
  non-exclusive plugins (Applications, Commands, Scripts, Calculator, Web, Windows).
- Applying a trigger change without restarting providers.
- Rewording `docs/calendar-plugin.md` and `docs/plugin-system-rework.md`, which describe the
  default keywords.
- Item aliases and the Items pane.

## Open questions
none
