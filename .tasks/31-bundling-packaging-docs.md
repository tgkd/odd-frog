# Task: Plugin system rework 13/13 — bundling, independent plugin packaging, docs, end-to-end verification

Last of thirteen tasks (19–31). Requires tasks 19–30: seven bundled packages, a Plugins pane, no
legacy host code. This task finishes the Makefile, proves a plugin can be replaced without
rebuilding the host, writes the authoring documentation with three working examples, and rewrites
the README for the plugin architecture.

## Goal
`make bundle` produces `build/OddFrog.app` with all seven packages under `Contents/PlugIns/`,
each provider executable signed before the app. `make plugin-calculator` builds and zips the
calculator package on its own; `make install-plugin-calculator` installs it into
`~/.config/odd-frog/plugins/calculator/` where it overrides the bundled one without the host
binary changing. `docs/plugins.md` lets someone write a plugin from scratch, and
`docs/examples/` holds three packages that work as-is. README describes the current app.

## Files
- Makefile                                          (modify)
- docs/plugins.md                                   (create)
- docs/examples/hello-command/plugin.toml           (create — declarative)
- docs/examples/port-lookup/plugin.toml             (create — one-shot)
- docs/examples/port-lookup/port-lookup.py          (create — executable, python3)
- docs/examples/clock/plugin.toml                   (create — persistent)
- docs/examples/clock/clock.py                      (create — executable, python3)
- README.md                                         (modify — Build and run, Usage, Config, Settings, Plugins, Logs)
- .gitignore                                        (modify — only if `build/plugins` needs a rule; `build/` is already ignored, so probably no change)
- Sources/OddFrogPluginAPI/ManifestParser.swift     (read — exact validation messages to quote in docs, created by task 19)
- Sources/OddFrogPluginAPI/Protocol.swift           (read — exact wire keys, created by task 19)
- Sources/OddFrogCore/ProviderProcess.swift         (read — deadlines and limits to quote, created by task 22)
- Plugins/calculator/plugin.toml                    (read — the manifest whose version is bumped during verification)
- Plugins/web/plugin.toml                           (read — example of a live/fallback manifest)

## Context
- Makefile today (verified `make bundle` exits 0 on 2026-09-07 from a clean checkout, ~10 min for
  a cold release build): variables `SIGN ?= -`, `APP := OddFrog`, `BUILD := build`, `BUNDLE :=
  $(BUILD)/$(APP).app`, `CONTENTS := $(BUNDLE)/Contents`, `BIN := .build/release/$(APP)`; targets
  `build` (`swift build -c release`), `bundle` (copies binary, `Resources/Info.plist`,
  `Resources/config.example.toml`, `Resources/AppIcon.icns`, writes `PkgInfo`, `codesign --force
  --sign "$(SIGN)" --deep $(BUNDLE)`), `run` (`pkill -x OddFrog`, wait, `open`), `install` (rsync to
  `~/Applications/OddFrog.app`), `test` (`swift test`), `clean`. Tasks 25–28 extended `bundle` to
  copy `Plugins/<id>/` into `$(CONTENTS)/PlugIns/<id>/`, copy each built provider next to its
  manifest, and sign the executables before the app. This task normalizes that into two
  variables and loops.
- Package ids and executables:

  | id | executable |
  |---|---|
  | applications | OddFrogAppsPlugin |
  | commands | OddFrogCommandsPlugin |
  | scripts | OddFrogScriptsPlugin |
  | calculator | OddFrogCalculatorPlugin |
  | windows | (none, declarative) |
  | web | OddFrogWebPlugin |
  | terminal | OddFrogTerminalPlugin |

- SwiftPM builds a single product with `swift build -c release --product OddFrogCalculatorPlugin`;
  the binary lands at `.build/release/OddFrogCalculatorPlugin`.
- Discovery (task 21): bundled packages come from `Bundle.main.builtInPlugInsURL`
  (`Contents/PlugIns`), user packages from `~/.config/odd-frog/plugins/<dir>/plugin.toml`
  (`XDG_CONFIG_HOME` honoured); a user package with the same id overrides the bundled one; the
  Plugins pane shows source "User" for it. Reload Plugins (status menu and the pane's Reload
  button) rescans and restarts providers.
- Enable state (task 24): bundled packages follow `default_enabled` (Windows is off); user
  packages are disabled until enabled in Settings › Plugins or `[plugins.<id>] enabled = true`
  in `~/.config/odd-frog/v2/settings.toml`.
- Wire protocol, manifest schema, roles, activation, settings types, services, deadlines
  (initialize/catalog 30 s, query 2 s, activate 30 s, links 10 s), 4 MiB line limit, and error
  codes are exactly as implemented in `Sources/OddFrogPluginAPI/` (task 19) and
  `Sources/OddFrogCore/ProviderProcess.swift` (task 22). Read those files and quote the real keys;
  the summary below is the design and must match the code:
  - request `{"id": 1, "method": "query", "params": {...}}`; response `{"id": 1, "result": {...}}`
    or `{"id": 1, "error": {"code": "invalid", "message": "…"}}`; event `{"event":
    "catalog_changed"}` / `{"event": "refresh"}`.
  - methods: `initialize {api, host_version, plugin_id, settings, config_dir, data_dir}` →
    `{api, name, version}`; `catalog {}` → `{items}`; `query {query_id, text, input, keyword}` →
    `{items}`; `activate {item_id, name, payload, argument, secondary}` → `{action, message}`;
    `configure {settings}`; `cancel {query_id}`; `shutdown {}`; `links.list`, `links.create
    {name, url, aliases}`, `links.update {id, revision, name, url, aliases}`, `links.delete {id,
    revision}`.
  - one-shot providers get a single `catalog` or `query` request whose `params` also carries
    `settings`, and answer with a single response line.
  - keyword activation: a user live-query plugin must list `keywords` unless it sets `activation =
    "all"`; `input` is the text after the keyword, `text` the full query.
- Logs: host log `~/Library/Logs/odd-frog.log`; provider stderr lines are appended there prefixed
  `plugin <id>:` (task 22).
- Legacy files `~/.config/odd-frog/config.toml`, `settings.toml`,
  `~/Library/Application Support/odd-frog/frecency.json`, `rates.json` are never touched by v2;
  manual migration is: copy `[general]` into `~/.config/odd-frog/v2/config.toml`; copy
  `[[commands]]` blocks into `~/.config/odd-frog/v2/plugins/commands/commands.toml`; rewrite
  `[[items]]` ids to the global form (`<path>` → `applications:<path>`, `command:<Name>` →
  `commands:<name-with-dashes>`, `script:<path>` → `scripts:<path>`, `window:place:left:1-2` →
  `windows:place-left-1-2`, `window:maximize` → `windows:maximize`, `window:tidy` →
  `windows:tidy`); `[scripts]` → `[plugins.scripts]`, `[search] url` → `[plugins.web] search_url`,
  `[currency] enabled` → `[plugins.calculator] currency`, `[window] enabled/cascade_step` →
  `[plugins.windows] enabled/cascade_step`. History starts empty.
- README sections today: Build and run, Usage, Config, Settings (Links, Scripts, Using ⌘Space,
  Terminals), Ranking, Logs, App icon. The Usage text about keys, window items, kind labels,
  fallbacks, `>`, calculator, units, currency, `pkill -USR1`, and the status menu remains true;
  the Config section still documents `[[commands]]` inside `config.toml` and the Settings section
  was rewritten in task 30.
- `python3` is at `/usr/bin/python3` on macOS 14+ (Command Line Tools); example scripts use
  `#!/usr/bin/env python3` and only the standard library (`json`, `sys`, `time`, `subprocess`).

## Plan
1. `Makefile`:
   ```make
   PLUGINS            := applications commands scripts calculator windows web terminal
   PLUGIN_EXECUTABLES := applications=OddFrogAppsPlugin commands=OddFrogCommandsPlugin \
                         scripts=OddFrogScriptsPlugin calculator=OddFrogCalculatorPlugin \
                         web=OddFrogWebPlugin terminal=OddFrogTerminalPlugin
   PLUGIN_DIR         := $(BUILD)/plugins
   USER_PLUGINS       := $(HOME)/.config/odd-frog/plugins
   ```
   Add a helper function `plugin-exe = $(patsubst $(1)=%,%,$(filter $(1)=%,$(PLUGIN_EXECUTABLES)))`.
   - `bundle`: after copying the app resources, `for id in $(PLUGINS)`: `mkdir -p
     $(CONTENTS)/PlugIns/$$id`, `cp -R Plugins/$$id/. $(CONTENTS)/PlugIns/$$id/`; if the id has an
     executable, `cp .build/release/<exe> $(CONTENTS)/PlugIns/$$id/<exe>` and `codesign --force
     --sign "$(SIGN)" $(CONTENTS)/PlugIns/$$id/<exe>`; finally the existing `codesign … --deep
     $(BUNDLE)`. Write the loop with an explicit `if [ -n "$$exe" ]` guard so `windows` copies
     only its manifest.
   - `package-plugin-%` (pattern rule, id = `$*`): `swift build -c release --product <exe>` when
     the id has one; `rm -rf $(PLUGIN_DIR)/$*`, `mkdir -p`, copy `Plugins/$*/.` and the signed
     executable, then `cd $(PLUGIN_DIR) && zip -qr ../$*-plugin.zip $*`.
   - `plugin-calculator: package-plugin-calculator` (the explicit target the doc asks for).
   - `plugins`: `$(foreach id,$(PLUGINS),package-plugin-$(id))` as prerequisites.
   - `install-plugin-%: package-plugin-%`: `mkdir -p $(USER_PLUGINS)`, `rsync -a --delete
     $(PLUGIN_DIR)/$*/ $(USER_PLUGINS)/$*/`, then `echo "Installed $* into $(USER_PLUGINS)/$*.
     Enable it in Settings › Plugins or via [plugins.$*] enabled = true, then Reload Plugins."`.
   - `install-plugin-calculator` needs no explicit rule (the pattern covers it); add `plugins
     plugin-calculator install-plugin-calculator` to `.PHONY`.
   - `clean` also removes `$(PLUGIN_DIR)` (already under `build/`).
2. `docs/plugins.md`, sections in this order, each with real values copied from the code:
   1. What a plugin is (package dir, `plugin.toml`, optional executable, assets; bundled vs user
      locations; override rule; Reload Plugins; enable state defaults).
   2. Manifest reference: every table and key with type, default, and the validation message
      thrown when violated (copy from `ManifestParser.swift`). Include the three forms
      (declarative, one-shot, persistent) with a minimal manifest each.
   3. Items and actions: `PluginItem` fields, `IconSpec` forms, every `PluginAction` type with its
      JSON, the `{argument}` token and where it is substituted, `recordable`, the global id rule,
      secondary fallback rule.
   4. Query roles and activation: exclusive/live/fallback, `priority` ordering, keyword rule,
      `text` vs `input`, debounce and the 2 s query deadline, transient results.
   5. Protocol: framing, envelopes, error codes, 4 MiB limit, stderr for diagnostics, a full
      example session (initialize → catalog → query → activate → shutdown) as literal lines, the
      event lines, one-shot semantics, deadlines table, what happens on failure (status shown in
      Settings, no automatic restart, Reload).
   6. Settings: the five types with their keys (`min`, `max`, `choices`, `must_contain`),
      validation behaviour, where values live (`[plugins.<id>]`), `configure` delivery, `config_dir`
      and `data_dir` paths.
   7. Host services: the seven `uses` names, which action needs which, what an undeclared use does,
      the `links` capability and the four `links.*` methods with the revision/conflict rule.
   8. Installing, enabling, reloading, logs (`~/Library/Logs/odd-frog.log`, `plugin <id>:` lines),
      packaging with `make package-plugin-<id>` / `make install-plugin-<id>`.
   9. Migrating from the old configuration (the mapping in Context, as a table).
   10. Examples: link the three directories and say how to install each (`cp -R
       docs/examples/<name> ~/.config/odd-frog/plugins/`, enable, Reload).
3. `docs/examples/hello-command/plugin.toml`: id `hello-command`, api 1, no provider,
   `services.uses = ["exec"]`, one item `id = "hello"`, title "Say Hello", kind "Shell", icon
   `{ glyph = "$", color = "gray" }`, action `{ type = "shell", command = "say hello from odd frog" }`,
   aliases `["hello"]`.
4. `docs/examples/port-lookup/`: manifest id `port-lookup`, `[provider] mode = "oneshot",
   executable = "port-lookup.py"`, `[query] role = "live", activation = "keyword", keywords =
   ["port"]`, `services.uses = ["clipboard"]`. `port-lookup.py` reads one JSON object from stdin;
   for `query`, parses `params.input` as an integer port, runs `lsof -nP -iTCP:<port> -sTCP:LISTEN`
   via `subprocess.run` with a 1 s timeout, and returns items (one per listening process) with
   id `pid-<pid>`, title `<command> (pid <pid>)`, subtitle the raw lsof line, kind "Port", action
   `{"type": "copy", "text": "<pid>"}`, `recordable: false`; non-numeric input or no listeners →
   empty `items`; `catalog` → empty items; anything else → `{"id": …, "error": {"code":
   "unsupported", "message": "…"}}`. Mark the file executable (`chmod +x`, and commit the mode).
5. `docs/examples/clock/`: manifest id `clock`, `[provider] mode = "persistent", executable =
   "clock.py"`, `[query] role = "live", activation = "keyword", keywords = ["time"]`,
   `services.uses = ["clipboard"]`, one `[[settings]]` `key = "utc"`, `type = "bool"`, title "Show
   UTC", default false. `clock.py`: NDJSON loop over stdin; `initialize` stores settings and
   returns `{api: 1, name: "Clock", version: "1.0.0"}`; `query` returns one item id `now`, title
   the current time (`%H:%M:%S`, UTC when the setting is on), subtitle the date, kind "Clock",
   action copy of the title, `recordable: false`; `configure` updates the setting; `cancel`,
   `shutdown` → `{}` (and exit after shutdown); a background thread writes
   `{"event": "refresh"}` every 60 s; stdout writes go through one lock and `flush()`; unknown
   methods → `unsupported`. Executable bit set.
6. `README.md`:
   - Build and run: add `make plugins`, `make plugin-calculator`, `make install-plugin-<id>`, and
     one sentence that `make bundle` signs each plugin executable before the app (same `SIGN`
     caveat applies).
   - Usage: keep the text; replace "With window management enabled" with "With the Windows plugin
     enabled (Settings › Plugins)"; keep calculator/units/currency paragraphs (cache path already
     updated in task 28).
   - Config: `~/.config/odd-frog/v2/config.toml` holds only `[general]`; commands moved to
     `~/.config/odd-frog/v2/plugins/commands/commands.toml` with the same `[[commands]]` format
     (keep the existing example block, moved under the new path, and the "each command has exactly
     one of…" rules).
   - New "Plugins" section after Settings: what ships, where user plugins go, the override rule,
     enabling and Reload Plugins, link to `docs/plugins.md` and the examples, one paragraph on
     replacing the calculator with `make install-plugin-calculator`.
   - Logs: mention `plugin <id>:` lines.
   - Add a short "Upgrading from the pre-plugin config" pointer to the migration section of
     `docs/plugins.md`.
7. Verification (record outcomes in the completion summary):
   1. `swift test` passes.
   2. `make bundle`; `ls build/OddFrog.app/Contents/PlugIns` lists the seven ids; `codesign -dv
      build/OddFrog.app/Contents/PlugIns/calculator/OddFrogCalculatorPlugin` reports a signature.
   3. `shasum -a 256 build/OddFrog.app/Contents/MacOS/OddFrog` → note the hash. `make run`.
   4. `cp -R docs/examples/port-lookup ~/.config/odd-frog/plugins/`, Settings › Plugins → enable
      "port-lookup" (source User, "One-shot · Live queries · keyword port"), Reload; in the
      launcher `port 22` (or any port with a listener, e.g. start `python3 -m http.server 8000`
      and query `port 8000`) shows a row per listener; Return copies the pid.
   5. `cp -R docs/examples/clock ~/.config/odd-frog/plugins/`, enable, `time` shows the clock
      row; toggle "Show UTC" in its settings and the row changes without a restart; leave the
      panel open a minute and the row refreshes.
   6. Independent replacement: in `Plugins/calculator/plugin.toml` set `version = "1.0.1"`, run
      `make install-plugin-calculator` (this rebuilds only the plugin product), revert the manifest
      edit with `git checkout Plugins/calculator/plugin.toml`, click Reload Plugins; Settings ›
      Plugins shows Calculator 1.0.1 with source "User"; `2+2` still works; `shasum -a 256
      build/OddFrog.app/Contents/MacOS/OddFrog` equals the hash from step 3. Remove
      `~/.config/odd-frog/plugins/calculator` and Reload: back to 1.0.0 "Bundled".
   7. For each bundled plugin in turn, disable it in Settings › Plugins: its items disappear from
      the launcher and `pgrep -f OddFrog<X>Plugin` prints nothing for providers; re-enable restores
      them. The host keeps running throughout (`pgrep -x OddFrog` unchanged).

## Constraints
- No code comments of any kind in Swift; the Makefile has no comments either; Python examples may
  contain no comments beyond the shebang (documentation lives in `docs/plugins.md`).
- Example scripts use only the Python standard library and must run under `/usr/bin/python3`.
- Every JSON key and every manifest key in the docs must match the code in `Sources/OddFrogPluginAPI/`
  (read it; do not copy from memory).
- Do not change any Swift source in this task except when a doc-vs-code mismatch reveals a bug;
  then fix the doc, not the code, and list the mismatch in the completion summary.
- Do not edit other `.tasks/*.md` files.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes (from the repo root).
- `swift build -c release` succeeds.
- `make bundle` succeeds and `ls build/OddFrog.app/Contents/PlugIns` prints
  `applications calculator commands scripts terminal web windows`.
- `make plugin-calculator` succeeds and produces `build/calculator-plugin.zip` containing
  `calculator/plugin.toml` and `calculator/OddFrogCalculatorPlugin`.
- `make plugins` succeeds and `build/plugins/` has seven directories.
- The manual verification steps 3–7 in Plan behave as described, with the host binary hash
  unchanged across the calculator replacement.
- `docs/examples/port-lookup/port-lookup.py` and `docs/examples/clock/clock.py` are executable
  (`test -x`) and `python3 -c 'import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]'
  docs/examples/port-lookup/port-lookup.py docs/examples/clock/clock.py` prints nothing.
- `echo '{"id":1,"method":"query","params":{"query_id":1,"text":"port 8000","input":"8000","keyword":"port","settings":{}}}' | docs/examples/port-lookup/port-lookup.py`
  prints one JSON line with `"id":1` and an `items` array.

## Out of scope
- A marketplace, downloads, update checks, sandboxing, or code-signing plugins with a real
  identity.
- Changing plugin behaviour or manifests beyond the temporary version bump used for verification.
- Removing the old `.tasks` specs or the `docs/plugin-system-rework.md` design document.

## Open questions
none
