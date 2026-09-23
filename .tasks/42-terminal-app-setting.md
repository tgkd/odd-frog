# Task: Choose the terminal app from Settings › Plugins › Terminal, with a custom command option

## Goal
Settings › Plugins › Terminal gets two settings. A "Terminal app" popup offers Terminal, agterm,
iTerm2 and Custom, and defaults to Terminal. A "Custom command" field holds a template with
`{cwd}`, `{shell}` and `{command}` placeholders. Every `terminal` action (the `>` prefix,
Commands with `terminal = true`, Scripts, and the ⌘↩ "open a shell here" action on folders) runs
in the chosen app. The old `terminal` key in `config.toml` `[general]` is no longer read or
written.

## Files
- Plugins/Terminal/plugin.toml                          (modify)
- Sources/OddFrogCore/TerminalChoice.swift              (create)
- Sources/OddFrogCore/Config.swift                      (modify)
- Sources/OddFrogCore/ShellCommand.swift                (modify)
- Sources/OddFrog/ActionExecutor.swift                  (modify)
- Sources/OddFrog/AppDelegate.swift                     (modify)
- Resources/config.example.toml                         (modify)
- Tests/OddFrogCoreTests/ConfigTests.swift              (modify)
- Tests/OddFrogCoreTests/TerminalChoiceTests.swift      (create)
- docs/query-plugins.md                                 (modify)
- Sources/OddFrog/TerminalLauncher.swift                (read — launches the three presets; stays unchanged)
- Plugins/Web/plugin.toml, Plugins/Windows/plugin.toml  (read — existing `[[settings]]` entries to mirror)
- Sources/OddFrogCore/PluginPackage.swift               (read — `PluginSettingDefinition`, `choice` validation)
- Sources/OddFrog/PluginsPane.swift                     (read — `row(for:value:package:)` renders `choice` as a popup and `string` as a text field)
- Tests/OddFrogCoreTests/ShellCommandTests.swift        (read — test style, and running a shell string through `Process`)

## Context
- Swift package, `swift-tools-version: 6.0`, AppKit app on macOS. Tests use Swift Testing
  (`import Testing`, `struct` suites, `@Test func`, `#expect`) with `@testable import OddFrogCore`.
- Today the terminal app comes from the host config `~/.config/odd-frog/v2/config.toml`,
  `[general] terminal = "agterm" | "terminal" | "iterm"`, parsed into `GeneralConfig.terminal`
  (`TerminalKind`, declared at the top of `Sources/OddFrogCore/Config.swift`, default `.agterm`).
  No Settings UI shows it. `Resources/config.example.toml` (the first-run template) has
  `terminal = "agterm"`.
- `ActionExecutor.runHost` (`Sources/OddFrog/ActionExecutor.swift`) handles `case .terminal:` by
  building a command string and calling the private `runInTerminal(id:name:command:cwd:)`, which
  reads `config.general.terminal` and `config.general.shell` and awaits
  `terminals.launch(command:cwd:name:kind:shell:)`. That `.terminal` action is emitted by the Terminal
  plugin (`>` prefix), Commands items with `terminal = true` and Commands folder items (⌘↩), and
  Scripts (`Plugins/Shared/Sources/BundledFeatures/FeatureProvider.swift`). So the choice is used
  host-wide. It lives on the Terminal plugin only because that is where the user looks for it.
- `TerminalLauncher.launch` switches on `TerminalKind`:
  - `.agterm` runs `agtermctl session new … --command`, and uses Terminal.app instead when
    `agtermctl` is missing or agterm is not running.
  - `.terminal` and `.iterm` write a `.command` script and open it with the app whose bundle ID is
    `com.apple.Terminal` or `com.googlecode.iterm2`. They fail with
    `terminal app <bundle id> is not installed` when the app is absent.

  `TerminalLauncher.run` waits for the child process on the main actor, which is fine for
  `agtermctl` but not for a custom command that may keep running.
- `ActionExecutor.spawn(id:name:executable:arguments:cwd:reportOutput:)` starts a process in the
  background, records history, and reports a non-zero exit in the menu bar as
  `"<name> exited <status>\n<stderr>"`. `ShellCommand.backgroundArguments(command:)` returns
  `["-lc", command]`. `ShellCommand.quote` single-quotes a string for POSIX shells.
- Plugin settings: a manifest's `[[settings]]` entries decode to `PluginSettingDefinition`
  (`key`, `title`, `type` of `boolean|string|number|choice|folders`, `default`, optional `choices`).
  `PluginManifest.parse` validates every `default` against its type. For `choice`, the default
  must be one of `choices`. No bundled plugin uses `choice` yet. The Settings pane shows `choice` as
  an `NSPopUpButton` whose item titles are the raw choice strings and stores the selected title
  as a JSON string. User values are saved in `settings.toml` under the plugin's `[[plugins]]` entry
  as `values`. In memory they are `Settings.plugins: [PluginSetting]`, and each
  `PluginSetting.values` is a `[String: JSONValue]?` (`JSONValue` is in `OddFrogPluginAPI`, and
  `.string` gives a `String?`).
- Precedent for the host reading a plugin's setting: `AppDelegate`'s `windows.perform@1` handler
  reads `settings.plugins.first { $0.id == context.pluginID }?.values?["cascade_step"]`.
- `AppDelegate` stores `private var settings = Settings.empty`. It is assigned in exactly two
  places: `loadInitialSettings()` and `applySettings(_:persist:)`. `executor` is
  `private lazy var executor = ActionExecutor(…)`, and the config is loaded before the settings.
- `ConfigParser` decodes `RawGeneral` with the synthesized `Decodable`, which ignores unknown
  keys. Once `terminal` is removed from `RawGeneral`, existing config files that still contain
  `terminal = "…"` keep parsing. `ConfigParser.serialized` rewrites `config.toml` when links are
  edited, so the key disappears from the file the next time that happens.
- `Tests/OddFrogCoreTests/BundledPackageTests.swift` installs and parses every bundled
  `Plugins/*/plugin.toml`. An invalid Terminal manifest, such as a default missing from
  `choices`, fails that test.
- Baseline: `swift build` succeeds with two warnings that are already there (a
  `CGWindowListCreateImage` deprecation in `AppDelegate`, and `nonisolated(unsafe)` in
  `UnitRegistry.swift`). `swift test` passes 253 tests.

## Plan
1. `Plugins/Terminal/plugin.toml`: append two `[[settings]]` entries in the format used by
   `Plugins/Web/plugin.toml`:
   - `key = "app"`, `title = "Terminal app"`, `type = "choice"`,
     `choices = ["Terminal", "agterm", "iTerm2", "Custom"]`, `default = "Terminal"`.
   - `key = "custom_command"`, `title = "Custom command ({cwd}, {shell} and {command} are filled in)"`,
     `type = "string"`, `default = ""`.

   The choice strings are the popup titles and also the stored values, which is why they are
   display names.
2. Create `Sources/OddFrogCore/TerminalChoice.swift` (imports `Foundation` and `OddFrogPluginAPI`):
   - Move `TerminalKind` here from `Config.swift`. Keep the case names `terminal`, `agterm` and
     `iterm` so that `TerminalLauncher` compiles unchanged. Set the raw values to the manifest
     choice strings: `case terminal = "Terminal"`, `case agterm`, `case iterm = "iTerm2"`. Keep
     `String, Sendable, CaseIterable`, and drop `Decodable`.
   - Add `public enum TerminalChoice: Sendable, Equatable` with `case preset(TerminalKind)` and
     `case custom(String)`, plus `public static let pluginID = "terminal"` and
     `public static let customTitle = "Custom"`.
   - Add `public init(values: [String: JSONValue]?)`:
     - When `values?["app"]?.string` equals `customTitle`, the result is
       `.custom(values?["custom_command"]?.string ?? "")`.
     - Otherwise it is `.preset(TerminalKind(rawValue:) ?? .terminal)`, so a missing or unknown
       value means Terminal.
3. `Sources/OddFrogCore/Config.swift`: delete the `TerminalKind` enum. Remove `terminal` from:
   - `GeneralConfig` (the property and its `init` parameter),
   - `RawGeneral`,
   - `ConfigParser.build` (the `if let terminal = g.terminal` line),
   - the `General` struct in `ConfigParser.serialized` and its initializer call.

   Leave `hotkey`, `shell` and `max_results` as they are.
4. `Sources/OddFrogCore/ShellCommand.swift`: add
   `public static func customTerminalCommand(template: String, shell: String, cwd: String, command: String) -> String?`.
   - Return `nil` when the template, trimmed of whitespace, is empty or does not contain
     `{command}`.
   - Otherwise build the result in one left-to-right pass over the template. Replace each
     `{cwd}`, `{shell}` and `{command}` token with `quote(cwd)`, `quote(shell)` and
     `quote(command)`, and copy all other text verbatim. Use a single pass so that a substituted
     value containing text like `{cwd}` is never expanded again.
5. `Sources/OddFrog/ActionExecutor.swift`: add `var terminal = TerminalChoice.preset(.terminal)` next
   to `cascadeStep`. Rewrite `runInTerminal(id:name:command:cwd:)` to switch on `terminal`:
   - `.preset(let kind)`: the current body, with `kind` from the switch instead of
     `config.general.terminal`.
   - `.custom(let template)`:
     - Let `directory` be `cwd` or, when that is `nil`, the home directory.
     - Call `ShellCommand.customTerminalCommand(template:shell:cwd:command:)` with
       `config.general.shell` and `directory.path`.
     - If it returns `nil`, call
       `fail("\(name): set a custom command containing {command} in Settings › Plugins › Terminal.")`
       and return.
     - Otherwise call
       `spawn(id: id, name: name, executable: URL(fileURLWithPath: config.general.shell), arguments: ShellCommand.backgroundArguments(command: <result>), cwd: directory, reportOutput: false)`.

     This runs the template in the background through the user's login shell, which gives a
     Homebrew `PATH` for `open`, `kitty` and similar. It reports a typo in the template, such as
     an exit of 127, through the existing failure path. It never blocks the main actor.
     `TerminalLauncher` is not used for this case.
6. `Sources/OddFrog/AppDelegate.swift`: give `settings` a `didSet` that sets
   `executor.terminal = TerminalChoice(values: settings.plugins.first { $0.id == TerminalChoice.pluginID }?.values)`.
   That one observer covers both assignments: the initial load and every `applySettings` from
   the Settings pane or from an external `settings.toml` edit. `didSet` does not run for the
   property's initial value, so the default stays `.preset(.terminal)` until settings load.
7. `Resources/config.example.toml`: delete the `terminal = "agterm"` line.
8. `Tests/OddFrogCoreTests/ConfigTests.swift`: in `parsesExample`, delete only the
   `#expect(config.general.terminal == .iterm)` line. Keep `terminal = "iterm"` in the TOML text,
   so the test still proves that a legacy key parses.
9. Create `Tests/OddFrogCoreTests/TerminalChoiceTests.swift` (`@testable import OddFrogCore`,
   `import OddFrogPluginAPI`, `import Testing`, `import Foundation`) with these tests:
   - `TerminalChoice(values: nil)` and `TerminalChoice(values: ["app": .string("Nope")])` are
     `.preset(.terminal)`.
   - `"agterm"` gives `.preset(.agterm)`, and `"iTerm2"` gives `.preset(.iterm)`.
   - `["app": .string("Custom"), "custom_command": .string("x {command}")]` gives
     `.custom("x {command}")`, and `"Custom"` with no `custom_command` gives `.custom("")`.
   - `customTerminalCommand` returns `nil` for `""`, `"   "` and `"open -a Foo"`.
   - Substitution: template `"run {cwd} {shell} {command} {other}"` with cwd `/tmp/a b`, shell
     `/bin/zsh` and command `echo {cwd}` returns exactly
     `"run '/tmp/a b' '/bin/zsh' 'echo {cwd}' {other}"`.
   - Round trip: run `/bin/sh -c` on the result for template `printf '%s|%s' {cwd} {command}`, cwd
     `/tmp/it's here` and command `echo "$HOME" it's`, mirroring `terminalCommandStringRunsVerbatim`
     in `ShellCommandTests`. Stdout must be `/tmp/it's here|echo "$HOME" it's`.
10. `docs/query-plugins.md`: after the paragraph that follows the action-kind table (the one that
    starts "`{argument}` substitutes…"), add one paragraph. It says the host opens every
    `terminal` action in the app chosen under Settings › Plugins › Terminal:
    - Terminal is the default.
    - agterm uses Terminal when agterm is not running.
    - Custom runs its template through the configured login shell, with `{cwd}`, `{shell}` and
      `{command}` replaced by shell-quoted values. Example:
      `open -na kitty --args --directory {cwd} --hold {shell} -lc {command}`.

## Constraints
- Write no code comments of any kind: no `//` or `///` lines, no doc comments, no MARK banners,
  no TODOs. Leave existing comments untouched.
- Match the surrounding Swift style: dense single-line `guard … else { return }` and
  `if … { return … }` bodies where neighbouring code uses them, `public` API in `OddFrogCore`,
  and no new dependencies.
- `TerminalLauncher.swift` stays byte-for-byte unchanged. The enum case names it uses must
  therefore keep compiling.
- Leave `shell` in `config.toml` `[general]`. Only `terminal` moves.
- Surgical changes only. Do not touch anything outside Files without saying why.
- The work is writing the code in Plan and running the commands in Acceptance. Nothing
  else: do not start the app or a dev server, do not open a browser, do not take
  screenshots, do not write or run tests or scripts that are not listed in Plan, do not
  mock or call any API. When the Acceptance commands pass, stop.

## Acceptance
- `swift build` passes with no warnings beyond the two in Context
- `swift test` passes (253 existing tests plus the new `TerminalChoiceTests`)
- `grep -rn "general.terminal\|TerminalKind: String, Sendable, Decodable" Sources Tests` prints nothing

## Manual review
1. `make run`. Settings › Plugins › Terminal shows "Terminal app" set to Terminal, with the
   choices Terminal, agterm, iTerm2 and Custom, and an empty "Custom command" field.
2. With Terminal selected, `> echo hi` opens a Terminal.app window that prints `hi`.
3. Select agterm. `> echo hi` opens an agterm session. `settings.toml` now has
   `values = { app = "agterm" }` under the `terminal` plugin entry. Quit agterm and repeat:
   Terminal.app opens instead.
4. Select Custom with the field empty. `> echo hi` shows the "set a custom command containing
   {command}" error in the menu bar.
5. Set Custom to `open -na kitty --args --directory {cwd} --hold {shell} -lc {command}`. `> pwd`
   opens kitty, which prints the home directory. Set it to `nosuchterm {command}`. `> pwd` reports
   `exited 127` along with the shell's "command not found" text.
6. With agterm selected, a Commands item with `terminal = true` and ⌘↩ on a Commands folder item
   both open agterm. The setting applies beyond `>`.
7. `~/.config/odd-frog/v2/config.toml` still contains `terminal = 'agterm'` and loads without a
   config error. The line is ignored.

## Out of scope
- More presets (kitty, Ghostty, WezTerm, Alacritty). Custom covers them.
- Ghostty's "failed to launch the requested command" banner in agterm when a command exits
  non-zero within a few milliseconds. The command still ran; that output comes from agterm.
- Using Terminal.app when iTerm2 is not installed, or any change to `TerminalLauncher`.
- Moving `shell` into Settings, adding a Settings › General row, or carrying the old
  `config.toml` `terminal` value over into `settings.toml`.
- The Terminal plugin's provider code and its `>` result row.

## Open questions
none
