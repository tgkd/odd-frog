# Every launcher feature is an API 2 package

The host owns AppKit UI, fuzzy ranking, arguments, history, configuration storage, process supervision,
and reusable macOS services. The bundled features are compiled into the host: `OddFrogBuiltins` links
`BundledFeatures`, `CalendarPluginCore`, `RemindersPluginCore`, `NotesPluginCore` and
`ChatPluginCore` and runs them in-process behind the same coordinator interface external packages
use, so a bundled package ships as `plugin.toml` alone.
Installing a package uses discovery and explicit enablement, without recompiling the host; a user
package with a bundled ID replaces the built-in one and runs out-of-process over NDJSON. A new macOS
capability may still require a host release.

| Package | Activation | Responsibility |
| --- | --- | --- |
| Applications | Catalog | Application discovery and file watching |
| Commands | Catalog | Configured commands/links and action interpretation |
| Scripts | Catalog | Script folders, Raycast headers, arguments, modes |
| Calculator | Live | Arithmetic, units, offline currency and refresh |
| Windows | Declarative | Window command names and capability parameters |
| Web | Fallback | URL recognition and search template |
| Terminal | Exclusive prefix `>` | `>` input |
| Calendar | Exclusive keyword `cal` | `cal` range/filter/labels and meeting links |
| Reminders | Exclusive keyword `rem` | `rem` range/filter/labels and requested writes |
| Notes | Exclusive keyword `note` | `note` list/filter, plain-text notes in the document window |
| Chat | Exclusive keyword `chat` | `chat` list/filter, streamed conversations in the chat window over an OpenAI-compatible API |

The [API 2 contract](query-plugins.md) defines one item model, generic host actions and callbacks,
NDJSON envelopes, lifecycle, settings, search precedence, and process limits. Calendar and Reminders
are separately versioned [services](host-services.md). No API 1 runtime adapter is shipped. Local
trusted packages are supported; custom plugin screens, a marketplace, and sandboxing are out of scope.

## Migration and storage

At first launch, stage and validate legacy configuration before activating `~/.config/odd-frog/v2/`
(or `$XDG_CONFIG_HOME/odd-frog/v2/`). Application support is likewise under `odd-frog/v2/`.
Migration transfers preferences, feature settings, commands/links, item visibility/aliases, explicit
plugin enable states, history, and the currency cache. Commands receive stable IDs; history and
aliases are remapped to plugin item identities. Renames preserve command/link IDs.

Original files remain untouched. Reserved `.v2-migration` staging directories can be retried after
interruption. Application support commits first; atomic config-directory rename is the activation
point. `migration-complete` prevents overwriting an existing completed v2 configuration. Unknown
preexisting v2 directories are preserved and reported with recovery instructions. Invalid legacy
files prevent activation; the status menu exposes Retry Migration after the originals are corrected.

The settings UI has General, Items, and generated plugin controls. Manage Links appears only for an
enabled package declaring the link-management capability. Defaults and edits are validated; invalid
external settings edits preserve the last valid runtime configuration.

## Verification

`swift test` covers existing feature behavior under its new owners, real one-shot/persistent processes,
callbacks, correlated services, cancellation, recoverable errors, crashes, malformed/oversized output,
deadlines, descendant cleanup, catalog/live/fallback composition, package generations, source-bound
approval, migration retries and stable identity mapping. Bundled-package acceptance tests exercise all
nine providers, disable each package, install the independent Python counter with settings and callback,
and replace Calculator while comparing the unchanged host binary's SHA-256 digest.

`make bundle` packages and signs providers from manifest metadata and signs the resulting app.
Native UI and actual macOS permission prompts additionally require an interactive smoke test; mocked
service tests do not grant or verify privacy permissions. See the task's final verification report for
checks actually run in this environment.
