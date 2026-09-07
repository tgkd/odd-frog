# Task: Plugin system rework 9/13 — Commands provider and capability-based link management

Ninth of thirteen tasks (19–31). Requires tasks 19–26. After this task the configured commands
(shell, path, link, URL template) are published by a persistent provider that owns
`commands.toml`, and Settings › Manage Links… edits links through the `links` capability of whichever
running plugin provides it. The host keeps no command parsing, no command item adapter, and no
`LinkEditor`; only the calculator still runs through host code.

## Goal
`make run` bundles `Plugins/commands` (provider `OddFrogCommandsPlugin`, `provides = ["links"]`).
Commands appear as before (kinds Shell/Terminal/Folder/URL, subtitles, `{query}` arguments, ⌘↩
secondary actions), hand edits to `~/.config/odd-frog/v2/plugins/commands/commands.toml` show up
without a restart, and Manage Links… lists, creates, edits and deletes links through the plugin with
stable link ids and revision checks: a link edited from two places fails visibly, a renamed link
keeps its Items overrides, and the button is disabled while no running plugin provides links.

## Files
- Package.swift                                              (modify — `OddFrogCommandsKit`, `OddFrogCommandsPlugin`, `OddFrogCommandsKitTests`)
- Makefile                                                   (modify — bundle the provider; drop the host example copy)
- Plugins/commands/plugin.toml                               (create)
- Plugins/commands/commands.example.toml                     (create — moved from Resources/commands.example.toml)
- Resources/commands.example.toml                            (delete)
- Sources/OddFrogCommandsKit/CommandsFile.swift              (create — entries, parsing, validation, ids)
- Sources/OddFrogCommandsKit/CommandCatalog.swift            (create — entries → `PluginItem`s)
- Sources/OddFrogCommandsKit/LinkEditor.swift                (create — moved from Core; ids + revisions)
- Sources/OddFrogCommandsPlugin/main.swift                   (create)
- Sources/OddFrogCommandsPlugin/CommandsHandler.swift        (create)
- Sources/OddFrogCore/Config.swift                           (modify — `[general]` only; drop commands, `commandsExamplePath`)
- Sources/OddFrogCore/Item.swift                             (delete — `CommandItem`/`CommandAction` were its last residents)
- Sources/OddFrogCore/LinkEditor.swift                       (delete)
- Sources/OddFrogCore/ItemAdapters.swift                     (modify — delete `commands(_:)`)
- Sources/OddFrogCore/PluginPaths.swift                      (modify — delete `commandsFile`)
- Sources/OddFrog/LinkService.swift                          (create — protocol + runtime-backed implementation)
- Sources/OddFrog/LinkManagerController.swift                (modify — async service calls, revisions, error display)
- Sources/OddFrog/SettingsWindowController.swift             (modify — service lookup, button enablement)
- Sources/OddFrog/AppDelegate.swift                          (modify — remove commands file handling and `applyLink`)
- Sources/OddFrog/HostServices.swift                         (read — `{argument}` substitution and `terminal` empty-command rule)
- Tests/OddFrogCommandsKitTests/CommandsFileTests.swift      (create — moved command cases from ConfigTests)
- Tests/OddFrogCommandsKitTests/CommandCatalogTests.swift    (create)
- Tests/OddFrogCommandsKitTests/LinkEditorTests.swift        (create — moved from Core, adapted to ids/revisions)
- Tests/OddFrogCoreTests/ConfigTests.swift                   (modify — general-only cases remain)
- Tests/OddFrogCoreTests/LinkEditorTests.swift               (delete)
- Tests/OddFrogCoreTests/ItemAdaptersTests.swift             (modify — drop command cases)
- Tests/OddFrogCoreTests/BundledManifestsTests.swift         (modify — commands manifest)
- README.md                                                  (modify — Config/Links sections)

## Context
- `ConfigParser.build` (Sources/OddFrogCore/Config.swift) validates commands: trimmed non-empty
  unique names (case-insensitive) → `emptyName(index)` / `duplicateCommandName`; exactly one of
  `command`/`path`/`url` → `commandMissingAction` / `commandMultipleActions`; `url` must parse with a
  scheme → `commandInvalidURL`; `terminal = true` only with `command` → `commandTerminalWithoutShell`;
  aliases trimmed, lowercased, unique across all commands → `duplicateAlias`; `path`/`cwd` tilde-
  expanded. `CommandItem {name, aliases, action: .shell(String)|.path(URL)|.url(URL), cwd, terminal}`.
- Task 20's `LegacyAdapters.commands(_:)` defines the item shape to reproduce: local id = lowercased
  name with whitespace runs replaced by `-`; `shell` without terminal → kind "Shell", action
  `.shell(command:cwd:)`, secondary `.terminal(command:cwd:)`; `shell` with terminal → kind
  "Terminal", action `.terminal`; `path` → kind "Folder", subtitle = `~`-abbreviated path, action
  `.open(url: file URL string)`, secondary `.terminal(command: "", cwd: path)` for directories and
  `.reveal(path:)` for files; `url` → kind "URL", subtitle = host + path without trailing slashes and
  with `%7Bquery%7D` shown as `{query}`, action `.open(url:)`, secondary `.copy(text: display URL)`;
  a URL containing `%7Bquery%7D` gets `argument: ArgumentSpec(placeholder: "query", optional: false)`
  and `{query}` → `{argument}` in both actions (the host percent-encodes the substitution inside
  `open.url`, task 20). Icons: shell/terminal `.glyph("$", "#292929", 13)`, path `.symbol
  ("folder.fill", blue, 12)`, url `.symbol("link", teal, 14)`.
- `LinkEditor` (Sources/OddFrogCore/LinkEditor.swift) edits one `[[commands]]` block textually,
  keeping every other byte intact: `commandRanges(in:)` finds header lines by parsing the prefix with
  `TOMLTable(string:)`, `updating(_:original:draft:)` replaces/appends/removes a block and re-parses
  the result to prove nothing else changed; `save(to:original:draft:)` re-reads the file and refuses to
  write when it changed since load. `LinkDraft.command()` validates name, URL (scheme required; http/
  https need a host) and comma-separated aliases. Error type `LinkEditError.message(String)`.
- Today's host link flow: `SettingsWindowController.showLinks` collects URL commands and calls
  `linkManager.present(links:for:)`; `LinkManagerController` (table with name/url/aliases columns,
  fields, New Link/Delete/Save/Done) calls `onApply(original, draft) throws -> [CommandItem]`, which
  `AppDelegate.applyLink` implements via `LinkEditor.save` + config reload + moving the item override
  from the old `command:<name>` id to the new one.
- Task 22's `PluginRuntime` exposes `linksList(_ id:)`, `linksCreate(_ id:_ params:)`,
  `linksUpdate(_ id:_ params:)`, `linksDelete(_ id:_ params:)` (async throws, id = plugin id)
  returning the task 19 types `Link {id, revision, name, url, aliases}`, `LinksListResult`,
  `LinkResult`; provider errors surface as `ProviderFailure.remote(ResponseError)` whose `message`
  is user-facing; `status(for:)` and `onStatusChanged` exist. `PluginRegistry.manifest(for:)` gives
  `provides`. Task 24 placed the commands file at `~/.config/odd-frog/v2/plugins/commands/
  commands.toml` (the plugin's `config_dir`), seeded by the host from `Resources/commands.example.toml`.
- Task 22 runs providers with the package directory as the working directory, so a bundled provider
  finds its assets at `FileManager.default.currentDirectoryPath`.
- Decisions: `[[commands]]` gains an optional `id` key (pattern `^[a-z0-9][a-z0-9._-]{0,63}$`); an
  entry without `id` uses the slug of its name (lowercased, whitespace runs → `-`, any character
  outside `[a-z0-9._-]` dropped); ids must be unique. The link `id` is the item's local id, so a
  rename no longer changes the global id and no override migration is needed. A link's `revision` is
  the FNV-1a 64-bit hash of `id + "\n" + name + "\n" + url + "\n" + aliases.joined(",")` truncated to
  `Int` (deterministic across processes). The host validates nothing itself: it sends the draft and
  shows the plugin's `invalid`/`conflict` message. Aliases travel as an array (the sheet splits the
  comma-separated field, trims, lowercases, de-duplicates).

## Plan
1. `Package.swift`: add `.target(name: "OddFrogCommandsKit", dependencies: ["OddFrogPluginAPI",
   .product(name: "TOMLKit", package: "TOMLKit")])`, `.executableTarget(name: "OddFrogCommandsPlugin",
   dependencies: ["OddFrogPluginAPI", "OddFrogCommandsKit"])`, `.testTarget(name:
   "OddFrogCommandsKitTests", dependencies: ["OddFrogCommandsKit"])`.
2. `CommandsFile.swift` (kit): `public enum CommandAction: Sendable, Hashable { case shell(String),
   path(URL), url(URL) }`, `public struct CommandEntry: Sendable, Hashable { id, name, aliases, action,
   cwd: URL?, terminal: Bool }`, `public enum CommandsError: Error, Equatable, CustomStringConvertible`
   with today's `ConfigError` command cases plus `invalidID(String)`, `duplicateID(String)`, and
   `toml(String)`; `public enum CommandsFile { static func parse(_ text: String) throws ->
   [CommandEntry]; static func slug(_ name: String) -> String; static func expandTilde(_:) -> String }`.
   `parse` decodes `[[commands]]` (all other tables ignored) with the validation rules from Context.
3. `CommandCatalog.swift` (kit): `public enum CommandCatalog { public static func items(for entries:
   [CommandEntry]) -> [PluginItem] }` with the shape in Context; helpers `abbreviate(path)`,
   `webAddress(url)`, `displayURL(url)` (replace `%7Bquery%7D` with `{query}`), `acceptsArgument(url)`.
4. `LinkEditor.swift` (kit): `public struct LinkDraft { name, url, aliases: [String] }`;
   `public enum LinkEditError: Error { case invalid(String), conflict(String) }`; `public enum
   LinkEditor`:
   - `static func links(in text: String) throws -> [Link]` (URL entries only, in file order, with
     `revision(for:)`).
   - `static func revision(for entry: CommandEntry) -> Int` (FNV-1a as decided).
   - `static func validate(_ draft: LinkDraft) throws -> (name: String, url: URL, aliases: [String])`
     with today's messages ("Enter a name for this link.", "Enter a full URL, such as
     https://github.com or obsidian://open.", "Web URLs need a host, such as https://github.com.").
   - `static func updating(_ text: String, linkID: String?, revision: Int?, draft: LinkDraft?) throws
     -> String`: `linkID == nil` → append a new block whose `id` is `slug(name)` made unique by
     appending `-2`, `-3`, …; otherwise find the entry by id (missing → `conflict("This link no longer
     exists. Reopen Manage Links.")`), compare `revision(for:)` with the given revision (mismatch →
     `conflict("This link changed outside this window. Reopen Manage Links and try again.")`), then
     replace (draft present, block serialized with `id`, `name`, `aliases`, `url` in that order via
     `TOMLEncoder`) or remove (draft nil) that block using today's textual `commandRanges` approach;
     re-parse and compare entries to prove only that entry changed, else
     `invalid("Could not safely update this config layout. No changes were saved.")`; duplicate name or
     alias errors from `CommandsFile.parse` are rethrown as `invalid(description)`.
   - `static func save(to url: URL, linkID: String?, revision: Int?, draft: LinkDraft?) throws -> Link?`
     (reads, updates, verifies the file is unchanged since the read, writes atomically, returns the
     resulting link or nil after a delete).
5. `Plugins/commands/plugin.toml`: `[plugin] id = "commands"`, `name = "Commands"`, `version =
   "1.0.0"`, `api = 1`, description "Your own shell commands, folders and links from commands.toml.";
   `[provider] mode = "persistent"`, `executable = "OddFrogCommandsPlugin"`, `catalog = true`;
   `[services] uses = ["open", "exec", "terminal", "clipboard", "launch"]`, `provides = ["links"]`.
   Move `Resources/commands.example.toml` to `Plugins/commands/commands.example.toml` unchanged.
6. `CommandsHandler.swift`: `final class CommandsHandler: PluginHandler` with lock-guarded `file:
   URL`, `entries: [CommandEntry]`, `lastContents: Data?`, a `DirectoryWatcher` on the config dir, and
   `server: PluginServer?`. `initialize`: `file = config_dir/commands.toml`; if missing, copy
   `<currentDirectoryPath>/commands.example.toml` there (create the directory); load (parse failure →
   keep the previous entries, print the error to stderr); start the watcher and on change re-read the
   file, ignore identical bytes, re-parse, emit `catalog_changed` when entries changed. `catalog` →
   `CommandCatalog.items(for: entries)`. `linksList` → `LinkEditor.links(in:)` of the current file
   text. `linksCreate/Update/Delete` → `LinkEditor.save` mapping `LinkEditError.invalid` →
   `PluginError.invalid(message)`, `.conflict` → `PluginError.conflict(message)`, then reload and emit
   `catalog_changed`. `shutdown` stops the watcher. `main.swift` as in tasks 25–26.
7. `Makefile`: `PLUGINS := windows web terminal applications scripts commands`; add `cp
   .build/release/OddFrogCommandsPlugin $(CONTENTS)/PlugIns/commands/` and its `codesign`; delete the
   `cp Resources/commands.example.toml …` line added in task 24.
8. Host removals: `Config.swift` keeps `GeneralConfig`, `Config {general}`, `ConfigError` without the
   command cases, `RawConfig {general}`, `ConfigLoader` without `commandsExamplePath`; delete
   `Item.swift`, `Core/LinkEditor.swift`, `LegacyAdapters.commands`, `PluginPaths.commandsFile`; in
   `AppDelegate` delete `commands`, `commandsWatcher`, `loadInitialCommands`, `reloadCommands`,
   `applyLink`, the `onApplyLink` wiring, and the `LegacyAdapters.commands(...)` term in
   `rebuildItems`. `URLTemplate.swift` stays in Core (the host uses `encode` for `{argument}`).
9. `Sources/OddFrog/LinkService.swift`:
   ```swift
   @MainActor protocol LinkService: AnyObject {
       func list() async throws -> [Link]
       func create(name: String, url: String, aliases: [String]) async throws -> Link
       func update(_ link: Link, name: String, url: String, aliases: [String]) async throws -> Link
       func delete(_ link: Link) async throws
   }
   @MainActor final class RuntimeLinkService: LinkService { init(runtime: PluginRuntime, pluginID: String) }
   ```
   forwarding to the task 22 methods. Add `static func message(for error: Error) -> String` returning
   the `ResponseError.message` for `ProviderFailure.remote`, "Links are not available right now." for
   other `ProviderFailure`s, and `localizedDescription` otherwise.
10. `LinkManagerController`: replace `onApply`/`links: [CommandItem]` with `service: LinkService?`
    and `links: [Link]`; `present(service:for:)` shows the sheet, calls `service.list()` inside a
    `Task` and fills the table (error → `errorLabel`); `saveLink` splits the aliases field, calls
    `create` or `update(original, …)` in a `Task`, reloads the list, selects the saved link by id;
    `deleteLink` confirms then calls `delete`; every failure shows `RuntimeLinkService.message(for:)`
    and leaves the fields untouched so the user can retry after reopening. `loadSelection` uses `Link`
    fields (`url` shown verbatim; the plugin already returns the display form with `{query}`).
11. `SettingsWindowController`: replace `onApplyLink` with `var linkService: (() -> LinkService?)?`;
    `showLinks` calls it, and if nil shows nothing; keep a reference to the Manage Links button and add
    `func update(linksAvailable: Bool)` toggling `isEnabled` and a tooltip "No running plugin provides
    links." when disabled; call it from `present` and from AppDelegate on `runtime.onStatusChanged`.
    `AppDelegate` implements the lookup: the first `registry.packages` entry (sorted by id) whose
    `manifest?.provides.contains(.links) == true` and `runtime.status(for:) == .running` →
    `RuntimeLinkService(runtime:pluginID:)`.
12. Tests:
    - `CommandsFileTests.swift`: the command cases moved from `ConfigTests` (`parsesExample` reduced
      to its command assertions, `rejectsMissingAction`, `rejectsMultipleActions`, `rejectsDuplicateAlias`,
      `rejectsTerminalWithoutCommand`), plus `explicitAndSlugIDs` (`id = "gh"` kept; "GitHub Search"
      → `github-search`; duplicate ids rejected; an invalid `id` rejected) and `generalTableIsIgnored`.
    - `CommandCatalogTests.swift`: one entry per action kind asserting id, kind, subtitle, icon,
      action, secondary, and the `{query}` URL producing `argument` plus `{argument}` in `open.url`
      and `copy.text`.
    - `LinkEditorTests.swift` (kit): the five Core cases ported (`addEditDeletePreservesOtherConfig`,
      `placeholderURLWritesLiteralQueryText`, `validatesBeforeWriting`,
      `preservesMultilineShellStringsAndQuotedHeaders`, `saveRoundTripAndStaleEditProtection`) using
      `linkID`/`revision`, plus `staleRevisionConflicts` (update with an old revision throws
      `.conflict`), `renameKeepsID`, and `newLinkIDIsUniqueSlug`.
    - `ConfigTests`: keep `defaultsWhenEmpty` (no `commands` assertion), `rejectsBadHotkey`,
      `reportsTOMLSyntaxErrors`, hotkey cases; drop the rest. Delete Core `LinkEditorTests.swift`.
      `ItemAdaptersTests`: drop the command cases. `BundledManifestsTests`: add `commandsProvidesLinks`
      (catalog true, `provides == [.links]`, uses contains `.open`, `.terminal`, `.clipboard`).
13. `README.md`: Config section — `[[commands]]` documented under
    `~/.config/odd-frog/v2/plugins/commands/commands.toml` with the optional `id` key and the slug
    rule; Links section — edits go through the Commands plugin, conflicts are reported and require
    reopening the sheet, and Manage Links… is disabled while the plugin is off.

## Constraints
- No code comments of any kind, in any file (the two comments in the old Core `LinkEditor.swift` do
  not travel with the moved code).
- Every `if`/`guard` body is braced.
- Swift 6 strict concurrency; the kit and executable import only `Foundation`, `OddFrogPluginAPI`
  and `TOMLKit`; `OddFrogCore` stays AppKit-free; Swift Testing only; tests use temporary files and
  never spawn the plugin executable or touch the network; no new third-party dependencies.
- The host must never check for the `commands` plugin id: link management is resolved by the
  `links` capability only.
- Hand-edited bytes outside the edited `[[commands]]` block must survive every editor write (the
  moved tests prove it).
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes, including `OddFrogCommandsKitTests`; `swift test --filter
  OddFrogCommandsKitTests` passes on its own.
- `make bundle` succeeds; `build/OddFrog.app/Contents/PlugIns/commands/` holds `plugin.toml`,
  `commands.example.toml` and a signed `OddFrogCommandsPlugin`.
- Manual after `make run` with `~/.config/odd-frog/v2/plugins/commands/commands.toml` removed: the
  file reappears with the four examples; `gh` opens GitHub; `ghs odd-frog` opens the search URL; `up`
  runs uptime in the terminal; editing the file by hand updates the launcher within a second; Settings
  › Items › Manage Links… lists GitHub and GitHub Search; adding a link "Docs" with alias `d` shows
  `d` in the launcher; renaming GitHub to "GitHub Home" keeps an alias added in Items; editing the file
  by hand while the sheet is open and then saving the sheet shows the conflict message; setting
  `[plugins.commands] enabled = false` disables Manage Links… and removes the commands.

## Out of scope
- Calculator extraction (task 28); removing `LegacySettings`, `URLTemplate`, `QuickAction`
  (task 29); the Plugins pane (task 30).
- Editing non-link commands in the UI; importing legacy `config.toml` commands.

## Open questions
none
