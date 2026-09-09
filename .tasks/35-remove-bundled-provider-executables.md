# Task: Remove the bundled provider executables and describe the in-process model

Second of two tasks (34–35). Requires task 34: the host already runs every bundled package through
`LocalProvider` and the eight `OddFrog*` provider executables are dead weight (about 18 MB of the
21 MB bundle, eight extra link steps per build).

## Goal
The package builds no provider executables. `make bundle` ships each bundled package as
`plugin.toml` (plus `assets/` when present) only; the app bundle is roughly 3 MB. Bundled manifests
carry no `executable` key. The Makefile, packaging tool and documentation describe the actual
model: bundled features are compiled into the host and run in-process; API 2 over NDJSON is the
contract for user-installed packages, and a user package with a bundled ID still replaces it.

## Files
- Package.swift                                                    (modify — drop eight executable targets)
- Plugins/Applications/Sources/main.swift, Plugins/Commands/Sources/main.swift, Plugins/Scripts/Sources/main.swift, Plugins/Calculator/Sources/main.swift, Plugins/Web/Sources/main.swift, Plugins/Terminal/Sources/main.swift (delete, and delete the now-empty `Sources` directories)
- Plugins/Calendar/Sources/OddFrogCalendar/main.swift, Plugins/Reminders/Sources/OddFrogReminders/main.swift (delete with their directories)
- Plugins/Applications/plugin.toml, Plugins/Commands/plugin.toml, Plugins/Scripts/plugin.toml, Plugins/Calculator/plugin.toml, Plugins/Web/plugin.toml, Plugins/Terminal/plugin.toml, Plugins/Calendar/plugin.toml, Plugins/Reminders/plugin.toml (modify — remove `executable`)
- Makefile                                                         (modify — remove `PLUGIN`, `plugin`, `calendar-plugin`, `reminders-plugin`)
- Sources/OddFrogPackage/main.swift                                (modify — remove `--product` mode)
- docs/plugin-system-rework.md                                     (modify — first paragraph and table)
- docs/query-plugins.md                                            (modify — "Build and examples")
- README.md                                                        (modify — line 12 and lines 122–133)
- Tests/OddFrogCoreTests/BundledPackageTests.swift                 (modify — drop the `products` property if task 34 left it only for the host hash; keep the hash check)
- Sources/OddFrogCore/PluginCoordinator.swift                      (read — the transport selection added by task 34)

## Context
- After task 34, `Package.swift` still declares these executable targets: `OddFrogCalendar`
  (path `Plugins/Calendar/Sources/OddFrogCalendar`), `OddFrogReminders`
  (`Plugins/Reminders/Sources/OddFrogReminders`), and `OddFrogApplications`, `OddFrogCommands`,
  `OddFrogScripts`, `OddFrogCalculator`, `OddFrogWeb`, `OddFrogTerminal` (each at
  `Plugins/<Name>/Sources`). Each contains only `main.swift`. The library targets
  `CalendarPluginCore` (`Plugins/Calendar/Sources/CalendarPluginCore`), `RemindersPluginCore`
  (`Plugins/Reminders/Sources/RemindersPluginCore`) and `BundledFeatures`
  (`Plugins/Shared/Sources/BundledFeatures`) stay; the host links them through `OddFrogBuiltins`.
- `OddFrogPackage` and `OddFrog` are the only executable products the Makefile builds after this
  task. `make bundle` → `plugins` → `build` (`swift build -c release`), then
  `.build/release/OddFrogPackage Plugins .build/release build/plugins`, then `codesign` of every
  executable found under `build/plugins` (the `find … -perm +111` step finds nothing and is
  harmless — leave it), then assembles `build/OddFrog.app` and copies `build/plugins` to
  `Contents/Resources/Plugins`.
- `Sources/OddFrogPackage/main.swift` copies `plugin.toml`, an optional `assets/` directory, and
  — only `if let executable = package.manifest.executable` — the built product. With no
  `executable` in bundled manifests, that branch is never taken, so packaging keeps working
  unchanged. Its `--product <root> <id>` mode prints a package's executable name and exists only
  for the Makefile's `plugin` target.
- Makefile today: `PLUGIN ?=` variable; targets `plugin` (builds `OddFrogPackage`, asks it for the
  product, builds that product, packages one id, signs it), `calendar-plugin` and
  `reminders-plugin` (aliases of `plugin`). `.PHONY` lists them.
- Manifests: `mode` stays as declared (`persistent` / `one-shot`) — after task 34 the coordinator
  ignores it for in-process packages except `declarative`. `PluginManifest.parse` (task 34)
  accepts a non-declarative manifest without `executable`.
- Documentation statements that become false:
  - `docs/plugin-system-rework.md` opening paragraph: "Its Swift targets have no dependency on
    `BundledFeatures`, `CalendarPluginCore`, or `RemindersPluginCore`. Installing a package or
    replacing a bundled package uses discovery and explicit enablement, without recompiling the
    host." The table's "Mode" column lists process modes (Persistent catalog, One-shot fallback…).
  - `docs/query-plugins.md` "Build and examples": "`make plugins` builds and signs all bundled
    packages using their metadata. To build a provider alone: `swift build -c release --product
    OddFrogCalculator`. … `make plugin PLUGIN=calculator` builds the packaging utility and selected
    provider only…".
  - `README.md:12`: `make plugin PLUGIN=calculator  # build/sign a standalone package`.
  - `README.md:124`: "Calendar's executable is bundled separately from the host."
  - `README.md:126–128`: "Every feature is a separately installed API 2 package, including
    Applications, Commands/Links, Scripts, Calculator, Windows, Web, and Terminal."
  - `docs/plugin-system-rework.md` "Verification": "Bundled-package acceptance tests exercise all
    nine providers … and replace Calculator while comparing the unchanged host binary's SHA-256 digest."
    (still true after task 34; keep.)
- `Tests/OddFrogCoreTests/BundledPackageTests.swift` reads `.build/debug/OddFrog` (or
  `$ODD_FROG_TEST_PRODUCTS/OddFrog`) to hash the host binary before and after replacing
  `calculator` with a Python package; that check stays meaningful and must remain.

## Plan
1. `Package.swift`: delete the eight `.executableTarget` entries named above. Keep `OddFrogPackage`,
   `OddFrog`, every library and every test target.
2. Delete the eight `main.swift` files and the directories that become empty:
   `Plugins/{Applications,Commands,Scripts,Calculator,Web,Terminal}/Sources/`,
   `Plugins/Calendar/Sources/OddFrogCalendar/`, `Plugins/Reminders/Sources/OddFrogReminders/`.
   `Plugins/Calendar/Sources/CalendarPluginCore/` and `Plugins/Reminders/Sources/RemindersPluginCore/`
   stay.
3. Remove the `executable = "…"` line from the eight bundled manifests. Do not touch
   `Plugins/Windows/plugin.toml` or anything under `examples/plugins/`.
4. Makefile: remove `PLUGIN ?=`, the comment above `plugin:`, and the `plugin`, `calendar-plugin`,
   `reminders-plugin` targets and their `.PHONY` entries.
5. `Sources/OddFrogPackage/main.swift`: remove the `--product` branch and its usage text; keep the
   packaging loop (including the `if let executable` copy, which user-style packages with
   executables under `Plugins/` could still use).
6. `docs/plugin-system-rework.md`: rewrite the first paragraph to say the host compiles the bundled
   features in (`OddFrogBuiltins` links `BundledFeatures`, `CalendarPluginCore`,
   `RemindersPluginCore`) and runs them in-process through the same coordinator interface as
   external packages; a user package with a bundled ID replaces it and runs out-of-process over
   NDJSON. Replace the table's "Mode" column with "Activation" (catalog / live / fallback /
   exclusive keyword `cal` / exclusive prefix `>` / declarative) and drop the process words.
7. `docs/query-plugins.md` "Build and examples": replace the first paragraph with: `make bundle`
   packages every directory under `Plugins/` as manifest-only bundled packages;
   `.build/release/OddFrogPackage Plugins .build/release build/plugins` does the packaging step
   alone; bundled providers are Swift libraries linked into the host, so there is no standalone
   provider build. Keep the examples paragraph and the `XDG_CONFIG_HOME`/`ODD_FROG_SUPPORT_HOME`
   note.
8. `README.md`: delete line 12; rewrite lines 122–133 so they say bundled features run inside the
   host, are enabled/disabled per package in Settings → Plugins, that trusted local packages under
   `~/.config/odd-frog/v2/plugins/<folder>/` run as separate processes over the API 2 protocol, and
   that a user package with a bundled ID replaces the built-in one (explicit enablement, own
   process). Keep the Calendar/Reminders usage text above line 122 unchanged.
9. `Tests/OddFrogCoreTests/BundledPackageTests.swift`: if task 34 left `products` used only for the
   host hash, keep it; remove any leftover reference to copying provider executables.
10. `rm -rf .build/release build && make bundle`; confirm `build/OddFrog.app/Contents/Resources/Plugins/*/`
    contain only `plugin.toml` and the app is about 3 MB.

## Constraints
- No comments in edited code; keep existing comment lines you do not otherwise touch.
- Do not change `PluginManifest`, `PluginDiscovery`, `PluginCoordinator`, or any protocol type —
  task 34 already made `executable` optional; this task only removes files, manifest keys, build
  targets and words.
- `examples/plugins/*` and `docs/api2/*` are untouched.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` passes (from the repo root) and `ls .build/debug | grep -E '^OddFrog[A-Za-z]*$'` prints
  exactly two lines: `OddFrog` and `OddFrogPackage` (today it prints ten).
- `swift test` passes, including `BundledPackageTests` and the `docs/api2/exchanges.ndjson`
  round-trip test in `PluginTests`.
- `make bundle` passes; `find build/OddFrog.app/Contents/Resources/Plugins -type f` lists exactly
  nine `plugin.toml` files (plus `assets/` contents if a package has them) and
  `du -sh build/OddFrog.app` is under 5 MB.
- `grep -rn "make plugin\|OddFrogCalculator\|OddFrogCalendar\|executable is bundled" README.md docs Makefile Package.swift` prints nothing.
- `open build/OddFrog.app`; `2+2`, `saf`, `> uptime`, `cal`, `rem` return rows and
  `ps aux | grep 'OddFrog.app/Contents/Resources/Plugins'` shows no processes.

## Out of scope
- Any behaviour change in the launcher, settings, migration or host services.
- Routing user providers' stderr into `odd-frog.log`.
- Reformatting the semicolon-joined one-liners in `OddFrogCore`.

## Open questions
none
