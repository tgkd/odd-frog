# Odd Frog

A small native macOS launcher: global hotkey, floating panel, fuzzy search over installed
apps and your own commands, nothing else.

## Build and run

```
make run       # build, bundle build/OddFrog.app, relaunch
make install   # copy to ~/Applications (needed for Launch at Login)
make test      # swift test
```

Requires Xcode command line tools with Swift 6. No Xcode project; SwiftPM plus a Makefile.

## Usage

Press `⌥Space` (default). Type. `↑`/`↓` to move, `↩` to run, `⎋` to hide. Clicking anywhere
else hides the panel. With an empty query the list shows only items you have used before; on a
fresh install it shows just the search field. `⇥` completes the selected item into the search
field. Return on a command that needs an argument fills the command in so you can type the
value. `⌘1`–`⌘9` runs the first through ninth visible row.

`⌘↩` runs the selected item's secondary action: apps reveal in Finder, folder commands open
in the configured terminal, URL commands copy the URL, background shell commands run in the
terminal, and scripts run in the terminal with full output.

When nothing matches, the panel offers a fallback instead of an empty list: "Open <url>" when
the text looks like a URL, and "Search for “<text>”" that opens the web search configured in
Settings (DuckDuckGo by default). Typing `>` followed by text shows a single "Run in Terminal"
row that runs the rest of the text; it bypasses item search entirely, even if an item would
otherwise match. Fallback rows are never recorded, so they never appear under an empty query.

Scripts can toggle the panel with `pkill -USR1 -x OddFrog`.

The menu bar item offers Show, Settings…, Reload Config, Open Config, Open Log, Rescan Apps,
the last failure (click to copy), and Launch at Login.

## Config

`~/.config/odd-frog/config.toml` (created from a template on first launch, hot-reloaded on save):

```toml
[general]
hotkey = "alt+space"        # modifiers: cmd, alt, ctrl, shift; keys: space, a-z, 0-9, f1-f15, return, tab, escape
terminal = "agterm"         # agterm | terminal | iterm
shell = "/bin/zsh"
max_results = 8

[[commands]]
name = "Build Project"
aliases = ["build", "b"]
command = "./scripts/build.sh"   # runs in the background; non-zero exit shows a notification
cwd = "~/Projects/MyApp"

[[commands]]
name = "Open Projects"
aliases = ["projects", "repos"]
path = "~/Projects"              # opened with the default app (Finder for folders)

[[commands]]
name = "Production SSH"
aliases = ["ssh prod"]
command = "ssh my-server"
terminal = true                  # runs in the configured terminal

[[commands]]
name = "GitHub"
aliases = ["gh"]
url = "https://github.com"

[[commands]]
name = "GitHub Search"
aliases = ["ghs"]
url = "https://github.com/search?q={query}"  # {query} becomes what you type after the alias
```

Each command has exactly one of `command`, `path`, `url`. Aliases must be unique; typing an
alias exactly always puts that command first. A `url` containing `{query}` takes the rest of the
typed text as an argument, so `ghs odd-frog` opens `https://github.com/search?q=odd-frog`. A
config that fails to parse is reported and the previous config stays active, including the
hotkey.

## Settings

Menu bar → Settings… (or edit `~/.config/odd-frog/settings.toml`, hot-reloaded):

- **Hotkey**: click the recorder, press a combination. It is applied immediately and written
  into `config.toml`.
- **Launch at login**: available once the app lives in `/Applications` or `~/Applications`
  (`make install`). macOS may ask you to approve it in System Settings → Login Items.

- **Script folders**: every executable script in these folders becomes a launcher item. Raycast
  script-command headers are honoured: `@raycast.title`, `@raycast.mode`, `@raycast.icon`,
  `@raycast.packageName`, `@raycast.argument1`. Scripts without a header use their filename.
  Compiled binaries and non-executable sources are skipped. "Watch folders" rescans on changes.
- **Items**: every app, command and script with an enabled checkbox and extra aliases.
- **Web search**: the URL used for the "Search for …" fallback when nothing matches. Must
  contain `{query}`. Defaults to `https://duckduckgo.com/?q={query}`.

```toml
[scripts]
folders = ["~/Projects/raycast-scripts"]
watch = true

[[items]]
id = "/Applications/Xcode-Beta.app"
enabled = false

[[items]]
id = "script:/Users/me/Projects/raycast-scripts/kill-port.sh"
aliases = ["kp"]

[search]
url = "https://duckduckgo.com/?q={query}"
```

Item ids are the app bundle path, `command:<name>` for config commands, and `script:<path>`.

### Links

Settings → **Manage Links…** lists URL commands, including the default GitHub shortcut (`gh`).
Use **New Link** to enter a name, full URL, and comma-separated aliases, then **Add Link**.
Select an existing link to edit it with **Save Changes**, or remove it with **Delete**.
Changes are saved immediately to `config.toml` and appear in the launcher without restarting.

`https://` and `http://` links open in your default browser. App URLs such as `obsidian://open`
open in the app registered for that scheme. Names and command aliases must be unique.
Extra aliases added in the Items table remain available when a link is edited or renamed.
Put `{query}` in a URL to insert what you type after the alias, for example `gh odd-frog`.

### Scripts

`silent` and `inline` scripts run in the background; their output is shown as a notification.
`fullOutput` scripts open in the configured terminal. A script with `@raycast.argument1` takes
the argument from the query after the command name: `kill 3000`, `kp 3000`.

### Using ⌘Space

Spotlight keeps its own binding, so both would fire. Disable Spotlight's shortcut first:
System Settings → Keyboard → Keyboard Shortcuts → Spotlight, then set `hotkey = "cmd+space"`.

### Terminals

`terminal = "agterm"` opens a new agterm session via `agtermctl` and falls back to Terminal.app
only when `agtermctl` is missing or agterm is not running. `terminal` and `iterm` open a
generated `.command` file, so no Automation permission is requested.

## Ranking

Fuzzy subsequence scoring with bonuses for prefix, word-boundary, camelCase and consecutive
matches, normalized to 0–100 per query. Frecency adds a bounded bonus (at most 15 points,
half-life 7 days), so a clearly better lexical match cannot be displaced, but close matches
learn from use. State lives in `~/Library/Application Support/odd-frog/frecency.json`.

## Logs

`~/Library/Logs/odd-frog.log`.

## App icon

The original frog artwork and all macOS icon sizes can be regenerated with
`swift scripts/generate-icon.swift`. The generated `Resources/AppIcon.icns` is included in
normal builds, so running the generator is only necessary when changing the artwork.
