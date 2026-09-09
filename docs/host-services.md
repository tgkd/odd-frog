# Host services, version 1

Capabilities are exact strings, including their `@1` suffix. Unknown versions remain visible as
package errors in Settings. All calls are correlated to a live provider operation. Read calls never
prompt. Cancellation removes active service tasks; handlers check cancellation before writes.

| Capability | Input | Result | Activation required |
| --- | --- | --- | --- |
| `calendar.read@1` | `{start, end}` Unix seconds; positive range ≤32 days near now | Calendar snapshot | No |
| `calendar.access@1` | `{}` | Effects, refreshQuery | Yes |
| `reminders.read@1` | `{limit}` integer 1–2000 | Reminders snapshot | No |
| `reminders.access@1` | `{}` | Effects, refreshQuery | Yes |
| `reminders.complete@1` | `{id}` nonempty reminder ID | Effects, notification, refreshQuery | Yes |
| `reminders.create@1` | `{title}` trimmed 1–500 characters | Effects, notification, refreshQuery | Yes |
| `windows.perform@1` | `{action}`: `place:left:1-2`, `place:right:2-3`, etc., `maximize`, or `tidy` | Effects | Yes |
| `links.manage@1` | `{}` | Opens the standard host link editor; effects | Yes |
| `links.read@1` | `{}` | `{revision, links: [{id, name, url, aliases}]}` | No |
| `links.write@1` | `{revision, id?, name, url, aliases?}` or `{revision, id, delete:true}` | Updated revision and links | Yes |

Calendar snapshots have `access` and `events`. Access is `notDetermined`, `fullAccess`, `denied`,
`restricted`, or `writeOnly`. Events contain `id`, `title`, `start`, `end`, `allDay`, `calendarName`,
`location`, and optional `url`. End times are exclusive. The Calendar package owns range interpretation,
filtering, date labels, and meeting-link recognition. EventKit objects never cross the boundary.

Reminders snapshots have the same `access` enum, `reminders`, `truncated`, and optional
`defaultListName`. Items contain `id`, `title`, optional Unix `due`, `allDay`, `listName`, `priority`,
and optional `url`. The host returns incomplete items; the package owns query interpretation and labels.

Window placement uses Accessibility in the host. The Windows package declares the launcher commands.
`tidy` reads the requesting package's validated `cascade_step` setting (default 32). Permission failures
explain how to grant Accessibility and retry. Calls do not manipulate privacy settings automatically.

Link IDs survive renames. Writes require the revision returned by the previous read and recheck the
file before atomic replacement; stale writes fail with `code: "revision"`. The host editor uses the
same stable records and external-edit protection. Only URL records can be edited through this capability.
