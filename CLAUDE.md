# Odd Frog

## Workflows

Workflows are local TOML files that list steps for Odd Frog to run in order. The bundled Workflows plugin
(`Plugins/Workflows/`) is the engine. The files themselves live only in folders the user picks in
Settings → Plugins → Workflows and never go into this repo, the same split as Scripts and script folders.
The format reference is `docs/workflows.md`; `examples/workflows/` holds a harmless example.

### Writing a workflow

- A workflow is data, not code. Steps run in a line: no branching, no loops, no expressions. Logic that
  needs more goes into an `exec` step that calls a script.
- Use only the step kinds the engine has. A new kind is an engine change, not a workflow trick.
- `exec` takes an argv and never runs a shell. Do not wrap commands in `sh -c` to get a shell back.
- Put a `confirm` step before any `exec` that uses LLM output: an LLM value can start with `-` and be read
  as an option, and no shell does not prevent that.
- The engine knows no service: no provider, URL, model or token. A step that needs one calls the
  user's own command with `exec`, and that command holds the secret. No secrets in a workflow file.
- Keep `{` literal with `{{` when a prompt shows JSON keys; any `{name}` other than `{input}` is a load error.

### Changing the engine

- The plugin owns the run state machine; the host only runs it like any other plugin. Keep host changes to
  the plugin contract (`docs/query-plugins.md`, `docs/api2/`).
- Run history keeps metadata only: no input, prompts, stdout or LLM output on disk.
- Every `exec` runs in its own process group; cancel, timeout and shutdown kill the group.
- The handler has a `closed` latch because the coordinator does not wait for shutdown.
- An app opened from Finder has no Homebrew `PATH`; the plugin's `path` setting puts it in front.
