# Workflows

A workflow is a TOML file that describes steps in a line: run a command, let you review
text, show a result. There is no branching, no loop and no expression language. Logic that needs more
goes into an `exec` step that calls a script.

## Where files live

Choose one or more folders in Settings → Plugins → Workflows. Any folder works. Keep workflow files
outside the odd-frog repository; they are your own data, not packages, and they need no approval.

The plugin reads every `.toml` file directly in each folder (not in subfolders) and ignores hidden
files. Folders are read in the order of the setting, files by name. A file that a symlink points to is
read once. When two files have the same `id` or the same `keyword`, the first one wins and the second
one shows as an error.

## Run a workflow

Type the workflow's keyword, a space and your text: `idea fix the bug`. The text after the keyword is
`{input}`. If the workflow has no `argument` table, it takes no text.

`wf` lists the runs, one row per run:

- A running row shows the current step. Return on it cancels the run.
- A failed row shows the failed step and why it failed.
- A paused row (a `confirm` step waits for you) shows the step as `review`. Return on it opens the
  editor again with your last draft (Continue). The secondary action cancels the run.
- A file that does not load shows as an error row with the reason.

The end of a run and a failure also give a notification.

A keyword that is equal to the trigger of another plugin (`note`, `cal`, `wf`, ...) is taken by that
plugin. Use another keyword.

## Format

```toml
id = "hello"
title = "Hello workflow"
keyword = "hello"
argument = { placeholder = "Name", optional = false }

[[steps]]
id = "greet"
kind = "exec"
argv = ["/bin/echo", "Hello, {input}!"]

[[steps]]
kind = "show"
text = "{greet.last_line}"
```

Top level:

| Key | Value |
| --- | --- |
| `id` | Letters, digits, `_` and `-`, up to 64 characters, starting with a letter or digit. Required. |
| `title` | The name in the launcher. Required, not empty. |
| `keyword` | Lowercase letters, digits, `_` and `-`, starting with a letter. Required. |
| `argument` | Optional table: `placeholder` (default `"Input"`) and `optional` (default `false`). Without it the workflow takes no text. |
| `[[steps]]` | One or more steps. |

Every step:

| Key | Value |
| --- | --- |
| `kind` | `exec`, `confirm` or `show`. Required. |
| `id` | Optional. Letters, digits, `_` and `-`, starting with a letter or `_`. Unique in the file, never `input`. Only a step with an `id` can be used in later steps. |
| `on_error` | `"stop"` (default) or `"continue"`. |
| `timeout` | Seconds, a positive integer or decimal. Only on `exec` (default 600). |

An unknown key is an error when the file loads, also a key of another kind (for example `argv` on a
`confirm` step). This catches typing errors early.

### exec

| Key | Value |
| --- | --- |
| `argv` | List of strings, not empty. `argv[0]` is the program. |
| `cwd` | Optional working folder. Default: the folder of the workflow file. It must be an absolute path after substitution. |
| `output` | `"text"` (default) or `"json"`. |

- There is no shell. Each `argv` element goes to the program as one argument.
- `argv[0]` is an absolute path, a path relative to `cwd`, or a bare name that is looked up in `PATH`.
- The command runs in its own process group. Cancel and timeout stop the whole group.
- A non-zero exit fails the step. Stdin is empty.
- The command gets the environment of the app. The plugin's `path` setting goes in front of `PATH`,
  and a bare command name is looked up in that `PATH`. An app started from Finder has no Homebrew
  `PATH`, so add those folders to the setting.

### Models and other services

Odd Frog knows no service. A step that needs a model, an API or a token calls your own command with
`exec`, and that command holds the address, the model and the secret. For example, with a CLI that
sends a prompt to a model:

```toml
[[steps]]
id = "draft"
kind = "exec"
argv = ["aigw", "-f", "~/notes/products.md", "Return one JSON object {{title, body}. Idea: {input}"]
output = "json"
```

If the command can print a JSON object inside code fences, strip them in a small script of your own,
because `output = "json"` reads stdout as it is.

### confirm

| Key | Value |
| --- | --- |
| `text` | The text to review. Required. |
| `title` | Optional window title. |
| `editable` | `true` (default) or `false`. |

The step opens the editor window with the rendered `text` and the run pauses. The window title is
`title`, or the workflow title when `title` is not set or renders empty. Your edits are saved as a
draft while you type. Cmd+Return continues the run with the reviewed text. Return is a new line.
Closing the window does not cancel the run: it stays paused in `wf`.

The values of the step:

- `{<id>.title}` is the first line of the reviewed text that is not empty, without leading and
  trailing spaces.
- `{<id>.body}` is the text after that line, without blank lines at its start and end.
- `{<id>.text}` is the full reviewed text.
- `{<id>.file}` is the path of a temporary file that holds the body (mode 0600, deleted when the run
  ends in any state).

A reviewed text that is empty or only spaces fails the step: "The reviewed text is empty."

With `editable = false` the window still opens, but the run continues with the rendered text, not
with what is in the window.

A paused run is kept in memory only. Reload Plugins or quit stops it, and it shows as stopped in `wf`.
Two `confirm` steps in one run open the editor two times, each with its own document.

### show

| Key | Value |
| --- | --- |
| `text` | The result text. Required. |

The step shows a notification, and the text appears on the run's row in `wf`. A `show` step has no
values for later steps.

## Substitution

Templates are `argv` elements, `cwd`, `prompt`, `text` and `title`. They have one namespace:

- `{input}` is the text after the keyword.
- `{<id>.<field>}` is a value of an earlier step that has an `id`.

Fields:

| Kind | Fields |
| --- | --- |
| `exec` | `output` (stdout), `last_line`, `exit`, `stderr` |
| `confirm` | `text`, `title`, `body`, `file` |
| any step with `output = "json"` | also every top-level field of the JSON object |

`last_line` is the last line of `output` that is not empty, with spaces trimmed. A standard field name
wins over a JSON field with the same name.

Rules:

- Only `{name}` and `{name.field}` are placeholders, where a name is letters, digits, `_` and `-`,
  starting with a letter or `_`. All other braces are literal. `Return {title, product, body}` stays
  as written.
- `{{` gives a literal `{`. `{{input}` gives the text `{input}`. `}` is always literal.
- One pass. A value is never scanned again: when a command prints `{review.file}`, that text stays as
  it is.
- One placeholder in an `argv` element gives one element. Values are never split at spaces.
- `~` at the start of `argv[0]`, `cwd` and each `context` path is your home folder. A `~` in a
  substituted value stays as it is.

Checks when the file loads:

- `{input.x}` is an error. `{input}` has no fields.
- A bare `{draft}` is an error; write `{draft.output}`.
- A reference to a step that does not exist, that has no `id`, that comes later, or to the step
  itself is an error. So is a reference to a `show` step.
- An unknown field is an error, except on a JSON step, where any field name is allowed.

When a run uses a JSON field that the object does not have, the step fails with the message
`{draft.titel} has no value.`

### JSON steps

A step with `output = "json"` must give one JSON object. Its top-level fields become values: a string
as it is, a number or a boolean as JSON text (`42`, `1.5`, `true`), `null` as empty text, and an object
or a list as compact JSON. Output that is not a JSON object fails the step.

### Failed steps with on_error = "continue"

When a step fails and has `on_error = "continue"`, the run goes on. Its `output` is empty and `exit`
is the real exit code. Every other field that has no value is empty text.

## Safety

- A value from a model or any other command can start with `-`, and the called script can read it as an option. There is no
  shell, but that does not prevent this. Put a `confirm` step before an `exec` step that uses model
  output, so that you see the values first.
- Run history keeps only metadata: workflow id, step states, times, exit codes and error text. It does
  not keep prompts, model output or stdout.
- The `confirm` temporary file is in the `review` folder of the plugin storage with mode 0600 and is
  deleted when the run ends. The plugin deletes the folder when it starts.
- The run history never keeps the confirm text, the draft or the window title.

## Planned, not built

- `max_chars = N` on `exec` will keep the last N characters of stdout before `output`, `last_line` and
  JSON parsing see it, so that a small on-device model gets a bounded input. It will not be allowed with
  `output = "json"`. Today the key is an error: "max_chars is not available yet."

## Example

[docs/examples/workflows/hello.toml](examples/workflows/hello.toml) uses only `/bin/echo`,
`/usr/bin/uname`, `/bin/sleep` and `/bin/date`. Add the `docs/examples/workflows` folder in Settings →
Plugins → Workflows, then type `hello` and a name. The `sleep` step waits 20 seconds, so you can try
cancel from `wf`.

[docs/examples/workflows/review.toml](examples/workflows/review.toml) has a `confirm` step: type
`review` and a line, edit the text, and press Cmd+Return. It counts the bytes of the body with
`/usr/bin/wc`.
