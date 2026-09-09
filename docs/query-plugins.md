# Query plugins, API 1

A plugin is a directory containing a UTF-8 `plugin.toml` and an executable:

```toml
id = "example"
name = "Example"
version = "0.1.0"
api_version = 1
executable = "provider"
keyword = "example"
services = []
```

The keyword matches a whole first word, case-insensitively, and exclusively owns that query.
`example hello` sends `query: "hello"` and `fullQuery: "example hello"`. `examples` does not match.
Conflicting enabled keywords fail visibly. IDs must be lowercase letters/digits/dots/hyphens;
keywords start with a lowercase letter and may also contain digits, underscores, and hyphens.

Providers are trusted executables with the current user's ordinary process access. Host services
must be declared separately. The services are `calendar.events` and `reminders.items`.
Calendar details reach a provider only after the user enables the package, grants macOS calendar
permission, and runs its keyword. No event data is stored in launcher history or settings.

## Exchanges

The host executes the provider twice, each time writing one JSON object to stdin and closing it.
The provider writes one JSON object to stdout and exits. Diagnostics belong on stderr. The host
uses private temporary files for transport and removes them after the exchange; neither events
nor provider output is written to the app log. Each exchange has a two-second deadline and a
four-MiB limit on input, stdout, and stderr. Failure is latched until Reload Plugins.

First, `prepare`:

```json
{"apiVersion":1,"id":"request-id","operation":"prepare","query":"tomorrow","fullQuery":"cal tomorrow","now":1788955200,"timeZoneIdentifier":"Europe/Belgrade","maxResults":8}
```

Respond with the matching ID/version, an empty `items` array, and optionally a calendar range:

```json
{"apiVersion":1,"id":"request-id","items":[],"calendarRequest":{"start":1788991200,"end":1789077600}}
```

Dates are Unix seconds. The host only allows ranges up to 32 days long, starting no earlier than
two days before `now` and ending no later than 32 days after it. Requesting an undeclared service
or an invalid range fails the provider. A provider without services returns just the empty array.

A reminders provider asks for a bounded number of incomplete reminders instead of a date range:

```json
{"apiVersion":1,"id":"request-id","items":[],"remindersRequest":{"limit":2000}}
```

`limit` must be between 1 and 2000. The host returns incomplete reminders only, ordered by due date
with undated ones last, and truncates to `limit`.

Next, `query` repeats the request with `operation: "query"` and, if requested, `calendar`:

```json
{"access":"fullAccess","events":[{"id":"occurrence-id","title":"Design review","start":1789027200,"end":1789030800,"allDay":false,"calendarName":"Work","location":"Meeting room"}]}
```

`access` is one of `notDetermined`, `fullAccess`, `denied`, `restricted`, or `writeOnly`. Only
`fullAccess` includes events. Optional `url` is the event's URL. No EventKit objects cross the boundary.

The reminders snapshot arrives as `reminders` and has the same access values:

```json
{"access":"fullAccess","truncated":false,"defaultListName":"Inbox","reminders":[{"id":"item-id","title":"Buy milk","due":1789027200,"allDay":false,"listName":"Inbox","priority":0}]}
```

`due` is absent for undated reminders, `allDay` marks a date-only due date, `priority` follows
EventKit (0 none, 1–4 high, 5 medium, 6–9 low), and `truncated` reports that `limit` cut the list.
`defaultListName` names the list a new reminder would go to, and is absent when there is none.

The final response contains rows and no calendar request:

```json
{"apiVersion":1,"id":"request-id","items":[{"id":"one","title":"Hello","subtitle":"An example result","kind":"Example","symbol":"star","primary":{"kind":"copy","value":"Hello"}}]}
```

Rows require unique nonempty local `id` and `title`. Optional fields: `subtitle`, `kind`, SF Symbol
name `symbol`, Tab `completion`, `primary`, and `secondary`. Missing completion preserves the query.
Missing primary makes a status-only row. Missing secondary falls back to primary. All query rows
are transient; provider order is preserved. Return at most 50 rows; the host applies `maxResults`.

Actions use `kind` and a string `value`:

| Kind | Value |
| --- | --- |
| `openURL` | HTTP(S) URL or `x-apple.systempreferences:` URL |
| `openApplication` | macOS application bundle identifier |
| `copy` | Plain text |
| `requestCalendarAccess` | Empty string; requires `calendar.events` |
| `requestRemindersAccess` | Empty string; requires `reminders.items` |
| `completeReminder` | A reminder `id` from the snapshot; requires `reminders.items` |
| `createReminder` | A new reminder title, 1–500 characters; requires `reminders.items` |

The host owns rendering, action execution, permission UI, query cancellation, selection preservation,
and stale-response rejection. Provider code must stay outside the host target.

## Minimal provider

Save this as executable `provider` beside the example manifest (requires Python 3 on PATH):

```python
#!/usr/bin/env python3
import json
import sys

request = json.load(sys.stdin)
items = []
if request["operation"] == "query":
    text = request["query"] or "Hello"
    items = [{"id": "answer", "title": text,
              "primary": {"kind": "copy", "value": text}}]
json.dump({"apiVersion": 1, "id": request["id"], "items": items}, sys.stdout)
```

Install the folder under `~/.config/odd-frog/plugins`, use Reload Plugins, enable it in Settings,
then type `example hello`. No host rebuild is required.
