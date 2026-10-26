# Local plugins — API 2

A package is a directory containing `plugin.toml`, optional executables, and assets. Install it under
`~/.config/odd-frog/v2/plugins/` (or `$XDG_CONFIG_HOME/odd-frog/v2/plugins/`), then enable it in
Settings → Plugins. A matching ID replaces a bundled package. Approval is bound to the bundled origin or canonical user-package source path plus ID; a user replacement does not inherit bundled approval. These are trusted
local programs with ordinary OS access, not sandboxed extensions. There is no API 1 runtime adapter.

## Manifest

```toml
id = "example.counter"
name = "Counter"
version = "1.0.0"
api_version = 2
mode = "persistent"
executable = "provider.py"
catalog = true
capabilities = []

[[settings]]
key = "step"
title = "Increment"
type = "number"
default = 1
minimum = 1
maximum = 100
```

Required metadata: `id` (lowercase letters, digits, dots, hyphens; 1–64 characters), `name`,
`version`, and `api_version`. Mode is `declarative`, `one-shot`, or `persistent`. Executable paths
are relative to the package, cannot contain `..`, and must be executable. A declarative package
has only `[[commands]]` and settings, with no provider. `catalog = true` and `background = true`
start providers when enabled; query-only providers start on demand. `enabled_by_default` defaults
to true for bundled packages; user packages always require explicit enablement.

Query providers declare `activation = "exclusive" | "live" | "fallback"`. Exclusive activation
requires exactly one `keyword` or `prefix`. Keywords match case-insensitively at word boundaries;
prefixes are case-sensitive. Conflicting enabled exclusive triggers are rejected, including
overlapping prefixes. Nonexclusive providers receive the full trimmed query. `order` (integer,
default zero), followed by plugin ID, determines provider order. Each provider controls its row order.

In Settings → Plugins the user can replace the text of a package's keyword or prefix. The override is
stored as `trigger` in that package's `[[plugins]]` entry of `settings.toml`, and clearing the field
restores the manifest text. The kind cannot change: a keyword package keeps a keyword and a prefix
package keeps a prefix, validated exactly like the manifest and refused when it conflicts with
another enabled trigger. A provider that mentions its own trigger in a row should read the typed
first word from `fullQuery` instead of quoting the manifest keyword.

An exclusive provider can also appear in the root search, without its trigger. Declare
`root_results = N` (0–10, default 0, exclusive activation only) and the host asks the provider for up
to N rows whenever the user types something else. These rows take their own slots after the
catalog matches and live answers, and they never replace the fallback rows. The query has
`root: true` and `fullQuery` as typed. Return only real matches in that mode: no status, hint,
loading or error rows, and an empty array when there is nothing to show. The Plugins pane lets the user
lower, raise (up to 10) or turn off the count for a package with `root_results`; the override is stored as
`root_results` in the package's `[[plugins]]` entry. Packages without the manifest field are never asked
for root rows. Triggered queries (`f query`) behave as before and always omit `root`.

Root rows suit a name or an address, not a query that something already answered. A live provider
marks a row with `answer: true` when it answers the typed query outright, like `2 + 2` or `100 eur`.
While such a row is shown, the host drops all root rows. A row that is only one reading of the query,
like `2024-03` as a subtraction, stays unmarked, and root rows appear next to it. After the query
changes, root rows wait up to 150 ms for live providers, so a quick answer replaces them before they
appear. Unfinished input such as `100 e` has no answer yet, so root rows may show while it is typed.

With nothing typed, the launcher lists each enabled exclusive package with its trigger and hotkey,
below the recent items, so the user can see what to type. Recents give up slots before an entry
does. The Plugins pane has a switch for this list, stored as `show_plugins` in the `[launcher]` table
of `settings.toml`.

Settings definitions have `key`, `title`, `type`, and `default`. Types are `boolean`, `string`,
`number` (optional `minimum`/`maximum`), `choice` (required `choices`), and `folders` (array of
nonempty paths). The host validates defaults and edits. Invalid external edits retain the last
valid settings. Providers receive all validated defaults and overrides in their context.

## Wire format

UTF-8 newline-delimited JSON on stdin/stdout. One JSON object per line, including a final newline.
Do not log to stdout. Each line is limited to 4 MiB, in either direction. Dates are Unix seconds.
The language-independent schema and sample exchanges are in [api2](api2/).

```json
{"apiVersion":2,"id":"q1","method":"query","params":{"apiVersion":2,"context":{"settings":{},"storagePath":"/tmp/data","configPath":"/tmp/config.toml"},"input":{"query":"2+2","fullQuery":"2+2","now":1788955200,"timeZoneIdentifier":"Europe/Belgrade","maxResults":8}}}
{"apiVersion":2,"id":"q1","result":[{"id":"answer","title":"4","primary":{"kind":"copy","value":"4"}}]}
```

All envelopes contain `apiVersion: 2` and exactly one of `method`, `result`, or `error`.
Requests and responses have a nonempty string `id`; events do not. Responses echo the request ID.
Errors are `{ "code": "query", "message": "Try another query" }`. An explicit JSON `null` is a valid
result. Unknown response IDs, malformed envelopes, crashes, oversized messages, and deadlines stop
the provider until Reload Plugins. Ordinary query and action errors remain recoverable.

Host operations use `params = {apiVersion: 2, context: {...}, input: ...}`:

| Method | Input | Result |
| --- | --- | --- |
| `initialize` | `{}` | `{"apiVersion":2}` |
| `catalog` | `{}` | Array of items; replaces the provider catalog |
| `query` | query, fullQuery, now, timeZoneIdentifier, maxResults, optional root | Array of at most 50 items |
| `activate` | actionID, payload, item, optional argument, optional text | Effects object, optionally with a view |
| `settings` | `{}`; updated values are in context | Acknowledgement object |

Every operation includes context, so a one-shot executable can perform one operation and exit
without process-local initialization state. Persistent executables accept multiple concurrent
requests and must keep consuming stdin while operations await host-service responses. Initialization
and catalog requests have 30-second deadlines; queries have a two-second deadline. User actions have
no query deadline and can be cancelled from the status menu.

Host events: `cancel` with `{requestID: "..."}` and `shutdown` with `{}`. Cancellation should stop
work for that request; a late response is ignored. Providers may emit `catalogChanged` and
`queryInvalidated` with `{}`. These events never carry result rows: the host fetches current data.
Providers may also emit `messageDelta` with `{viewID, messageID, delta}` while a chat `send`
callback is running: the host appends `delta` to the reply of the open chat with that `viewID` and
ignores deltas addressed to any other view. The `view` returned by the callback is authoritative.
Provider process generations reject events from a previous package instance. Disable/reload stops
the process group, cancels active service work, and clears its catalogs and live results.
Closing the panel cancels queries but keeps catalog/background providers alive.

Search shows cached catalog matches immediately, debounces queries by 75 ms, cancels superseded
work, and discards old query responses. Exclusive providers suppress all other results. Otherwise
live answers precede fuzzy-ranked catalog matches. Fallback rows appear only after applicable
providers finish and there are no live or catalog matches. Selection follows item identity.

## Items and actions

All catalog and query items use the same shape. Required: local `id` and `title`. Optional:
`subtitle`, `kind` label, SF Symbol `symbol`, `icon` (absolute file, package-relative asset,
`text:` glyph, or `file:<absolute path>` for the Finder icon of any file or folder), `aliases` array, `argument: {placeholder, optional}`, `completion`, `primary`,
`secondary`, `history`, and `answer` (see root rows above). Host identity is `plugin:<plugin-id>:<local-id>`. IDs must be unique
within a catalog/response. Set `history: true` for reusable catalog items; live results are always
transient. Missing secondary action uses primary. Missing primary produces an inert status row.

An action has `kind`, `value`, and optional `payload`, `argv`, `cwd`, `output`:

| Kind | Meaning of value |
| --- | --- |
| `copy` | Clipboard text |
| `openURL` | URL, including registered app URL schemes |
| `openPath` / `reveal` | Filesystem path |
| `openApplication` | Absolute app path or bundle ID |
| `execute` | Absolute executable; argv is an array, no shell expansion |
| `terminal` | Shell command, or executable when argv is supplied |
| `service` | Declared versioned host capability; payload is its input |
| `callback` | Provider action ID; payload is arbitrary JSON |

`{argument}` substitutes the selected text argument. An argv element equal to `{argument}` is
omitted when no argument is supplied. Terminal argv is shell-quoted by the host. URL templates
use `{query}` with percent encoding. `output = "notification"` reports bounded command output;
otherwise stdout is discarded. Plain executable scripts remain ordinary commands, without JSON.

The host opens every `terminal` action in the app chosen under Settings › Plugins › Terminal.
Terminal is the default. agterm uses Terminal when agterm is not running. Custom runs its template
through the configured login shell, with `{cwd}`, `{shell}` and `{command}` replaced by shell-quoted
values. Example: `open -na kitty --args --directory {cwd} --hold {shell} -lc {command}`.

An action in a result row that the host runs itself (not `callback` or `service`) may carry
`after: {callback, payload?}`. Once the host has started that action without an
immediate error, it sends the owning provider an `activate` request with `actionID` set to `callback`
and `payload` as given, and the selected `item`. The call is fire-and-forget: the response is ignored
and failures are silent. Use it to learn from host-run actions, such as a file index raising the rank of
an opened path. Declarative packages cannot use `after`.

Callbacks receive the selected item, original payload, action ID, and argument. A callback invoked
from a document or chat window also receives the editor buffer in `text`. Success effects:
`{notification?: string, refreshCatalog: boolean, refreshQuery: boolean, view?: object}`. Errors use
the normal structured error envelope. The host checks package generation and enablement before
activation.

## Views

Effects may carry one `view`, whose `kind` selects the window the host opens: `editor`, `chat`, or `month`.

### Editor

An editor view is `{kind: "editor", id, title, text, placeholder?, save}`. `id` is plugin-scoped and must be stable for a given document: the host reuses its one
document window, and a view whose plugin and `id` already match the open document just refocuses it
without touching the buffer. `title` is the window title and `text` is the initial
buffer; the document window does not display `placeholder`.

`save` must be a `callback` action, and it is invoked with the editor text in `text`. The host
autosaves one second after typing pauses, on Cmd+S, on close, when another document replaces this
one, and on quit. A `view` returned from a save updates the window title only; the buffer and the
selection are never replaced. A failed autosave or Cmd+S shows the error as the window subtitle. When a save fails on close,
on replacement or on quit, or a quit's save takes longer than two seconds, the quit is cancelled
if one was pending, the text stays on screen, and a sheet offers Save and Close, Keep Editing, and
Discard and Close. Reloading plugins invalidates the open document: the host never re-sends a draft to a
superseded provider, and the text stays editable and copyable so it can be recovered by hand. The subtitle says so, and a
sheet offering Keep Editing or Discard and Close appears whenever unsaved text is at stake.

### Chat

A chat view is `{kind: "chat", id, title, messages, placeholder?, prompt?, send}`. `messages` is the
whole transcript, an array of `{id, role: "user" | "assistant", text}` with unique non-empty IDs.
`title` is the window title and `placeholder` is shown while the input is empty. An optional
`prompt` seeds the input and is sent by the host as soon as the window is on screen, so the first
turn streams like any other. `id` behaves like the editor's: a chat view whose plugin and `id`
already match the open chat just refocuses its window.

`send` must be a `callback` action, and it is invoked with the input text in `text`. While it runs,
`messageDelta` events append to the reply; the `messages` it returns replace the transcript
and its `title` updates the window. The host keeps no transcript of its own, so a plugin that wants
history must store it. A failed or cancelled send puts the text back into the input and shows the error as the
window subtitle. Reloading plugins invalidates the open chat: the transcript stays selectable and the input is
disabled.

### Month

A month view is `{kind: "month", id, title}`. The host opens its single calendar window
titled `title`, showing the current month in the user's calendar, first weekday, and
locale, with today marked. A Month/Year control in the window's toolbar switches to the
whole year as month tiles, and clicking a tile opens that month. Navigation is local to the
host, and no callback runs while browsing. The toolbar's previous and next buttons, and
Option+Cmd+Left Arrow and Option+Cmd+Right Arrow, step one month or one year back and
forward; Cmd+1 and Cmd+2 choose Month or Year, and Cmd+T returns to today. Presenting any
month view brings the window forward and resets it to the current month. The view carries
no data; a plugin that wants more must wait for a later view contract.

## Host services

While an operation is active, either runtime can issue a correlated request:

```json
{"apiVersion":2,"id":"s1","method":"host.service","params":{"requestID":"q1","capability":"calendar.read@1","params":{"start":1788912000,"end":1788998400}}}
```

The host replies with `id: "s1"` and result/error. The request must name an active operation and a
capability declared in the manifest. Service definitions are versioned separately in
[host-services.md](host-services.md); Calendar/Reminders payloads are not transport fields.
Permission prompts and writes require user activation (`activate` or a selected host service action),
never initialize/catalog/query. Reusable services can be added in a host release without changing API 2.

## Build and examples

`make bundle` packages every directory under `Plugins/` as a manifest-only bundled package.
`.build/release/OddFrogPackage Plugins .build/release build/plugins` runs that packaging step alone.
Bundled providers are Swift libraries linked into the host, so there is no standalone provider build.

Runnable examples: [declarative](../examples/plugins/declarative/), [one-shot Python query](../examples/plugins/one-shot/),
and [persistent Python catalog, settings, and callback](../examples/plugins/counter/).
The Swift `OddFrogPluginAPI` target is an optional SDK, not the protocol specification.

For isolated development runs, set `XDG_CONFIG_HOME` and `ODD_FROG_SUPPORT_HOME` to temporary directories. The latter overrides the application-support root before the `v2` suffix.
