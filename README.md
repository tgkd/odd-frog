# Odd Frog

A small native macOS launcher: global hotkey, floating panel, fuzzy search over installed
apps, your own commands, and optional window management.

## Build and run

```
make run       # build, bundle build/OddFrog.app, relaunch
make install   # copy to ~/Applications (needed for Launch at Login)
make test      # swift test
```

Requires Xcode command line tools with Swift 6. No Xcode project; SwiftPM plus a Makefile.

`SIGN` defaults to an ad-hoc signature (`-`). Rebuilding changes that identity and can invalidate
macOS Accessibility access, even if System Settings still shows it enabled. For a stable identity,
create a self-signed code-signing certificate in Keychain Access → Certificate Assistant → Create
a Certificate… (certificate type "Code Signing", name e.g. `OddFrog Dev`), then use
`make run SIGN="OddFrog Dev"` or `make install SIGN="OddFrog Dev"`. If access stops working after
an ad-hoc rebuild, remove Odd Frog from Accessibility and add the rebuilt app again.

## Usage

Press `⌥Space` (default). Type. `↑`/`↓` to move, `↩` to run, `⎋` to hide. Clicking anywhere
else hides the panel. With an empty query the list shows only items you have used before; on a
fresh install it shows just the search field. `⇥` completes the selected item into the search
field. Return on a command that needs an argument fills the command in so you can type the
value. `⌘1`–`⌘9` runs the first through ninth visible row.

`⌘↩` runs the selected item's secondary action: apps reveal in Finder, folder commands open
in the configured terminal, URL commands copy the URL, background shell commands run in the
terminal, and scripts run in the terminal with full output.

`⌘I` hides the panel and opens Settings › Items with the selected item found and its Aliases
cell ready for editing. `⌘,` hides the panel and opens Settings unchanged.

With window management enabled, ten "Window" items appear: Left ½, Right ½, Left ⅔, Right ⅔,
Top ½, Bottom ½, Top ¾, Bottom ¾, Maximize, and Tidy Windows. Placements act on the focused
window of the frontmost app, using that window's screen and leaving room for the menu bar and
Dock. Tidy Windows cascades standard windows on that screen in the current Space diagonally,
requesting the same size for each and preserving front-to-back order. The step compresses for
many windows so the requested size stays at least half the screen on each axis; apps may enforce
larger minimum sizes. Add aliases or disable individual actions in Settings › Items.

Kind labels are searchable: `window` finds Window actions, and `window left` narrows them to
the left placements. You can also prefix a name or alias with `script`, `folder`, `url`,
`shell`, or `terminal`. Names and aliases still work on their own.

When nothing matches, the panel offers a fallback instead of an empty list: "Open <url>" when
the text looks like a URL, and "Search for “<text>”" that opens the web search configured in
Settings (DuckDuckGo by default). Typing `>` followed by text shows a single "Run in Terminal"
row that runs the rest of the text; it bypasses item search entirely, even if an item would
otherwise match. Fallback rows are never recorded, so they never appear under an empty query.

An arithmetic expression shows a "Calculator" row above everything else: `+`, `-`, `*`, `/`,
`^`, `%`, parentheses, `x` or `×` for multiplication, and `of`. A percentage after `+` or `-`
is relative, so `500 + 20%` is `600`, while `500 * 20%` and `20% of 500` are both `100`.
Return copies the result to the clipboard. A bare number is never treated as a calculation, so
`1` still searches.

The same row converts units: `100 km in mi`, `20 c in f`, `512 gb in gib`, `1.5h in min`.
Length, mass, temperature, data storage, duration, volume, speed and area are covered, with
`in`, `to`, `as`, `->` or `=` between the units, or nothing at all (`100km mi`). Conversion
factors come from the system, and a query that mixes dimensions, such as `100 kg in miles`,
shows no row at all.

Currency works the same way: `100 usd in eur`, `200 eur to rsd`, `$100 in eur`, `100 usd eur`.
The row shows the converted amount, the ISO code, and how old the rate is. Rates come from
[Exchange Rate API](https://www.exchangerate-api.com) through its keyless open endpoint,
which publishes once a day. The app downloads the whole table and converts locally, so what
you type is never sent anywhere. A fetch happens at most once every six hours, in the
background, never while you type. The table is cached in
`~/Library/Application Support/odd-frog/rates.json`, so conversion keeps working offline.
Until that file exists, a currency query just searches as usual.

Scripts can toggle the panel with `pkill -USR1 -x OddFrog`.

## Calendar, Reminders, and plugins

The bundled Calendar plugin shows a live agenda in the normal launcher list:

- `cal` or `cal today`: remaining events today, including ongoing and all-day events.
- `cal tomorrow`: tomorrow's events.
- `cal week`: the next seven calendar days, including today.
- `cal 12d`: the next 12 calendar days, including today; any number up to 30 works.
- `cal design`: search titles, calendar names, and locations over the next 30 calendar days.
- `cal tomorrow design`, `cal week design`, and `cal 12d design`: search within that period.

On first use, choose **Allow Calendar access** and respond to the macOS prompt. Reading events
requires Full Access; the plugin does not create or modify events. Denied access offers a link to
Calendar privacy settings. Calendars are those available through macOS EventKit.

Return opens the Calendar app (it does not select the event). Command-Return joins an HTTPS Zoom,
Google Meet, Teams, or Webex link from the event's URL/location, when present; otherwise it opens
Calendar. Event notes are not read. Results use local time, stay chronological, and do not enter
launcher history. Snapshots are cached in memory for up to 30 seconds and invalidated on store changes.

The bundled Reminders plugin lists incomplete reminders from Apple Reminders:

- `rem` or `rem today`: overdue reminders plus everything due before the end of today.
- `rem tomorrow`: tomorrow's reminders only, without overdue ones.
- `rem week`: overdue plus everything due in the next seven calendar days, including today.
- `rem 12d`: the same for the next 12 calendar days; any number up to 30 works.
- `rem all`: every incomplete reminder, including ones with no due date.
- `rem milk`: search titles and list names across every incomplete reminder.
- `rem week design` and `rem 12d design`: search within that period.
- `rem add Buy milk`: create a reminder in the default list. A search that matches nothing offers
  the same row, so `rem call the plumber` turns straight into a new reminder.

On first use, choose **Allow Reminders access** and respond to the macOS prompt. Reading reminders
requires Full Access. The plugin can mark a reminder completed and create new ones; it never edits
or deletes them, and it does not read reminder notes. Denied access offers a link to Reminders
privacy settings.

Return opens the Reminders app. Command-Return marks the selected reminder completed and posts a
notification. Rows show the due date, the list, and a high-priority marker; overdue rows are
labelled. An all-day reminder counts as overdue only once its day has passed. Reminders are read
at most every 30 seconds and are invalidated when the store changes.

**Settings → Plugins** enables/disables packages and displays discovery/runtime errors. **Reload
Plugins**, available there and in the menu bar, rereads packages and clears failures. Changing a
package on disk requires Reload.

Every feature is its own package, including Applications, Commands/Links, Scripts, Calculator,
Windows, Web, Terminal, Calendar, and Reminders. The bundled ones are compiled into the host and run
inside it; each still enables and disables independently in Settings → Plugins, which removes its
results and stops its background work. The host keeps UI, ranking, history, storage, and macOS services.

Install trusted local packages in `~/.config/odd-frog/v2/plugins/<folder>/` (respecting `XDG_CONFIG_HOME`).
They run as separate processes speaking the API 2 protocol over stdin/stdout. A user package with a
bundled ID replaces the built-in one and runs in its own process, but needs explicit enablement for
its source path. Packages can publish catalogs, answer queries, declare settings, and handle their own
callbacks. API 1 packages remain visible with an upgrade error.
See [the API 2 protocol and examples](docs/query-plugins.md).

On first launch, legacy configuration and application-support files are staged, validated, and migrated
to `v2`. Original files stay intact. Migration errors offer Retry Migration in the status menu; a completed
v2 configuration is never overwritten. See [migration details](docs/plugin-system-rework.md).

## Config

`~/.config/odd-frog/v2/config.toml` (created from a template on first launch, hot-reloaded on save):

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

Settings has General (hotkey and login), Items (catalog visibility and aliases), and Plugins.
Plugin controls are generated from each manifest: booleans, strings, numbers, choices, and folder lists.
Scripts owns folder/watch settings, Web owns its URL template, Calculator owns currency conversion,
and Windows owns its cascade step. Invalid external settings edits retain the last valid settings.

`~/.config/odd-frog/v2/settings.toml` is hot-reloaded. Plugin enable approvals include both ID and source;
use the UI to enable a package. Each plugin entry can contain a `values` table with its declared settings.
Item overrides use `plugin:<plugin-id>:<local-id>` identities. Configured command/link IDs remain stable
when renamed in Manage Links.

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

`examples/scripts/` holds ready-made script commands; add that folder (or a copy of a single
script) under Settings → Plugins → Scripts to use them.

- **Toggle Theme** switches macOS between light and dark. With no argument it flips the current
  appearance; `toggle theme light` and `toggle theme dark` set it directly. The new appearance is
  shown as a notification. The first run asks to let Odd Frog control System Events; without that
  permission the script reports where to grant it in System Settings → Privacy & Security →
  Automation.

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
