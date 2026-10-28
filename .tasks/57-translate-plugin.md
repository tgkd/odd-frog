# Task: Add a bundled Translate plugin: Apple Translation offline, MyMemory online

## Goal
A new bundled plugin `translate` (keyword `tr`, on by default) translates the typed text between
two languages the user picks. Text in "your language" goes into the other one; anything else goes
into your language. Apple Translation answers offline when its language packs are installed. When a
online lookup is on (the default), a second row with MyMemory's translation appears under it. MyMemory
needs no account or key. Return pastes the translation into the app that was active, ⌘Return copies it.

## Files
- Plugins/Translate/plugin.toml                                              (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateLanguage.swift      (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateDirection.swift     (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslationOutcome.swift     (create)
- Plugins/Translate/Sources/TranslatePluginCore/AppleTranslator.swift        (create)
- Plugins/Translate/Sources/TranslatePluginCore/MyMemoryClient.swift         (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateProvider.swift      (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateHandler.swift       (create)
- Plugins/Translate/Tests/TranslateDirectionTests.swift                      (create)
- Plugins/Translate/Tests/MyMemoryClientTests.swift                          (create)
- Plugins/Translate/Tests/TranslateProviderTests.swift                       (create)
- Plugins/Translate/Tests/TranslateHandlerTests.swift                        (create)
- Package.swift                                                              (modify)
- Sources/OddFrogBuiltins/BuiltinProviders.swift                             (modify)
- Tests/OddFrogCoreTests/BundledPackageTests.swift                           (modify)
- Tests/OddFrogCoreTests/MigrationTests.swift                                (modify)
- Plugins/Chat/Sources/ChatPluginCore/ChatHandler.swift                      (read — handler shape, settings from context)
- Plugins/Chat/Sources/ChatPluginCore/ChatBackend.swift                      (read — static `urlRequest`, testable HTTP)
- Plugins/Characters/Sources/CharactersPluginCore/CharactersProvider.swift   (read — paste/copy row actions)
- Sources/OddFrogCore/PluginCoordinator.swift                                (read — 2 s query timeout, `queryInvalidated`; do not modify)

## Context
- Swift tools 6.2, Swift 6 language mode, macOS 26 deployment target, Swift Testing only.
- Bundled plugins run in-process: `BuiltinProviders.factories` maps the plugin ID to a handler factory.
  Packaging discovers every `Plugins/*/plugin.toml`.
- The coordinator debounces keystrokes by 75 ms, cancels the previous query, and gives a plugin 2 s to
  answer `query`. `emit("queryInvalidated")` re-runs the visible query and keeps the old rows on screen
  until the new answer arrives. That is how a slow answer reaches the screen without blocking `query`.
- **Apple Translation outside SwiftUI.** macOS 26 adds `TranslationSession(installedSource:target:)`.
  It works from a plain process (checked with a command-line spike), but only for language packs that
  are already installed. `LanguageAvailability().status(from:to:)` returns `installed`, `supported`
  (pack not downloaded) or `unsupported`. Translating a pair that is not installed throws
  `TranslationError` with cause `notInstalled`. An `installedSource` session cannot download packs, so
  the plugin sends the user to System Settings › General › Language & Region › Translation Languages.
  `TranslationSession` is a non-`Sendable` class; it lives inside one actor.
  `preferredStrategy` needs macOS 26.4 and is not used.
- **Language detection** uses `NLLanguageRecognizer` (NaturalLanguage, offline). It is unreliable for
  one or two words, so the two chosen languages get priority (Plan 3).
- **MyMemory API** (checked with live requests). `POST https://api.mymemory.translated.net/get` with a
  form body `q`, `langpair=en|ru` and optional `de=<email>`. GET works too, but puts the text into the URL
  and fails with HTTP 414 on long text. There is no `auto` source, so the plugin sends the detected one.
  Plain two-letter codes work for all 19 languages (`zh` answers as `zh-CN`, `nb` works).
  - Errors come with HTTP 200: `responseStatus` (a number or a string such as `"403"`) is not 200, and
    the error text replaces `responseData.translatedText`. `matches` is then `""`, not an array.
  - `q` is limited to 500 characters (`QUERY LENGTH LIMIT EXCEEDED`).
  - Free limit: 5 000 characters a day, 50 000 with `de`. A used-up limit sets `quotaFinished: true`
    or `responseStatus: 429`.
  - `responseData` is the best of `matches`, which mix a public translation memory with machine
    translation (`"created-by": "MT!"`). A fuzzy memory hit can win with a translation of a different
    sentence (`it's raining, isn't it?` → `Что-то дождь усилился`), and a memory entry can be the source
    copied verbatim (`Guten Morgen` → `Guten Morgen`). Machine translation is the reliable choice.
- Text sent online leaves the Mac, so the online lookup is a setting that says where the text goes.
- Two tests hard-code the bundled plugin count (`== 15`), and `BundledPackageTests` force-unwraps
  `queries[id]!` for every bundled package.

## Plan
1. **`plugin.toml`.** `id = "translate"`, `name = "Translate"`, `version = "0.1.0"`, `api_version = 2`,
   `keyword = "tr"`, `mode = "persistent"`, `activation = "exclusive"`, `capabilities = []`. Settings:
   - `primary_language`: title `Your language`, `choice` over the names in Plan 2, default `Russian`.
   - `secondary_language`: title `Translate your language into`, `choice`, default `English`.
   - `online`: title `Also translate with MyMemory (sends the text to mymemory.translated.net)`, `boolean`,
     default `true`.
   - `mymemory_email`: title `Email for MyMemory (optional; raises the free limit from 5,000 to 50,000
     characters a day)`, `string`, default `""`.

2. **`TranslateLanguage`** (public struct, `Sendable, Hashable`): `name`, `code` (two-letter code used by
   Apple and MyMemory). `static let all` lists: Arabic `ar`, Chinese `zh`, Danish `da`, Dutch `nl`,
   English `en`, French `fr`, German `de`, Indonesian `id`, Italian `it`, Japanese `ja`, Korean `ko`,
   Norwegian `nb`, Polish `pl`, Portuguese `pt`, Russian `ru`, Spanish `es`, Swedish `sv`, Turkish `tr`,
   Ukrainian `uk`. `named(_:)` looks up by name, `matching(code:)` by base language code
   (`Locale.Language(identifier:).languageCode`, so `zh-Hans` → Chinese).

3. **`TranslateDirection`** (public struct: `source`, `target`) with
   `static func resolve(_ text: String, primary:, secondary:) -> TranslateDirection`:
   - Ask `NLLanguageRecognizer` for up to 5 hypotheses, limited by `languageConstraints` to
     `TranslateLanguage.all`.
   - While the top hypothesis is below 0.6 (detection is unsure), `primary` or `secondary` with
     probability ≥ 0.15 wins, the more likely of the two. Otherwise the top hypothesis is the source.
     No hypothesis → `secondary`.
   - Target is `secondary` when the source is `primary`, otherwise `primary`.
   - `static func languages(_ values: [String: JSONValue]) -> (primary, secondary)` reads both choices,
     falling back to Russian and English.

4. **`TranslationOutcome`** (public enum, `Sendable, Equatable`): `text(String)`, `notInstalled`,
   `unsupported`, `failed(String)`. Protocols `OfflineTranslator` (`translate(_:from:to:) async ->
   TranslationOutcome`) and `OnlineTranslator` (`translate(_:from:to:email:) async -> TranslationOutcome`),
   both `Sendable`.

5. **`AppleTranslator`** (public struct, `OfflineTranslator`). Creates a `TranslationSession` per call:
   the class is not `Sendable`, so an actor cannot keep one. It first checks `LanguageAvailability().status(from:to:)`:
   `supported` → `notInstalled`, `unsupported` → `unsupported`. A thrown `notInstalled` →
   `notInstalled`. Any other error → `failed(localizedDescription)`.

6. **`MyMemoryClient`** (public struct, `OnlineTranslator`) over an injected `URLSession`:
   - `static let limit = 500`. Longer text → `failed("MyMemory translates up to 500 characters.")`
     without a request.
   - `static func urlRequest(_ text:, from:, to:, email:) -> URLRequest`: POST, form-encoded body (`+`, `&`,
     `=` and `|` percent-encoded), `de` only when the email is not empty, 8 s timeout.
   - `static func outcome(status: Int, data: Data, text: String) -> TranslationOutcome`. The translation
     is the machine match if there is one; otherwise the first match of at least 0.95 that differs from
     the source text (ignoring case); otherwise `responseData.translatedText`.
   - Messages: used-up limit `MyMemory's free limit for today is used up. An email in Translate settings
     raises it.`, other `responseStatus` → `MyMemory: <responseDetails in sentence case>`, non-2xx HTTP
     `MyMemory answered with HTTP <status>.`, unreadable body `MyMemory sent an answer Odd Frog can't
     read.`, network error `Can't reach MyMemory: <localizedDescription>`.

7. **`TranslateProvider`** builds rows (`kind: "Translate"`).
   - `hint(primary:secondary:online:)` → one row `hint`: `Type text to translate`, subtitle
     `Russian ⇄ English · Apple Translation` plus ` and MyMemory` when online lookup is on, symbol
     `character.bubble`, no actions.
   - `sameLanguages()` → one row `same`: `Pick two different languages in Translate settings.`
   - `respond(direction:offline:online:truncated:)`. `offline` is `TranslationOutcome?` (nil = still
     translating); `online` is `Online { off, pending, done(TranslationOutcome) }`. With `truncated`,
     every subtitle ends with ` · first 2000 characters`.
   - Apple row `apple`, subtitle `Apple · English → Russian`:
     `text` → title is the translation, symbol `translate`, primary `.paste`, secondary `.copy`;
     nil → `Translating…`, symbol `hourglass`, no actions;
     `notInstalled` → `Download English and Russian for offline translation`, subtitle
     `Press Return to open Translation Languages in System Settings.`, symbol `arrow.down.circle`,
     primary `.openURL` to `x-apple.systempreferences:com.apple.Localization-Settings.extension`;
     `unsupported` → `Apple can't translate English → Russian`; `failed` → `Apple Translation failed`
     with the message as subtitle, symbol `exclamationmark.triangle`.
   - MyMemory row `mymemory`, only when online is not `off`, same shapes with `MyMemory · English → Russian`,
     `Translating with MyMemory…` while pending, `MyMemory translation failed` on failure.
   - When both are `text` and equal, one row `apple` with subtitle `Apple and MyMemory · English → Russian`.
   - When Apple has no translation and MyMemory has one, the MyMemory row comes first, so Return pastes it.

8. **`TranslateHandler`** (public actor, `ProviderHandler`):
   `init(offline: any OfflineTranslator = AppleTranslator(), online: any OnlineTranslator = MyMemoryClient(),
   offlineWait: Duration = .milliseconds(600), onlineDelay: Duration = .milliseconds(500))`.
   - `start(emit:)` stores `emit`. `initialize` → `{"apiVersion": 2}`, `settings` → `{}`.
   - `query`: trim the text, cap it at `TranslateProvider.limit` (2 000) characters, resolve the
     direction from settings. Empty text → `hint`, equal languages → `sameLanguages`.
   - A translation that is empty after trimming becomes `failed("The translation came back empty.")`:
     a row with an empty title would make the coordinator disable the plugin.
   - Offline: results cache keyed by text + source + target. On a miss, start one job per key that
     translates and stores the result. `query` waits for the job at most `offlineWait`. If the job ends
     after `query` stopped waiting and its text is still the latest one asked for, it emits
     `queryInvalidated`.
   - Online (setting `online`, on when missing): results cache keyed by text + source + target. On a
     miss, cancel the previous online job and start a new one that sleeps `onlineDelay`, translates,
     stores, and emits `queryInvalidated`. `query` never waits for it and shows the pending row. The
     delay is a typing pause: every request spends the 5 000-character daily limit.
   - Only `text` results stay cached. Other outcomes are reused for 10 s and then retried, so installing
     a language pack or adding an email takes effect without a restart. Each cache is cleared when it
     passes 256 entries.

9. **Wiring.** `Package.swift`: `TranslatePluginCore` target (deps `OddFrogPluginAPI`), add it to
   `OddFrogBuiltins`, test target `TranslatePluginTests`. `BuiltinProviders`: `"translate": {
   TranslateHandler() }`. `BundledPackageTests`: count 16, query `"translate": "tr"`, wait until the first
   row is `hint`, expect its title. `MigrationTests`: count 16.

10. **Tests** (fake translators, no network, no Apple Translation):
    - Direction: `привет` → Russian→English, `hello` → English→Russian, a German sentence → German→Russian,
      settings fallback.
    - MyMemory: POST form body with escaped `+`/`&`, `de` only with an email, machine match preferred
      over a fuzzy memory hit, verbatim copy skipped, error `responseStatus` as a string, used-up limit,
      HTTP 500, garbage body, text over 500 characters.
    - Provider: hint row (with and without MyMemory), all Apple outcomes, pending MyMemory row, merge of equal
      results, same-language row.
    - Handler: offline answer inside `offlineWait`; slow offline answer arrives through
      `queryInvalidated`; no MyMemory row when online lookup is off; MyMemory pending row, then `queryInvalidated`, then the
      cached result; only the last of several fast queries reaches MyMemory; a failure is retried after
      expiry (inject a short retry interval).

## Constraints
- Swift 6 strict concurrency, no new warnings.
- Match surrounding code: one type per file, `RPCError`, `JSONValue`, braced early returns.
- No comments in new code unless the reason is not obvious from the code.
- No changes to the coordinator, host app, or other plugins.
- Tests never call MyMemory or Apple Translation.

## Acceptance
- `swift build` passes with no warnings beyond the pre-existing one in `UnitRegistry.swift`.
- `swift test` passes.

## Manual review
Build and launch with `make run`.
1. `tr` shows the hint row with the current pair.
2. Without Russian and English packs installed, `tr hello` shows the download row. Return opens
   Translation Languages in System Settings. If the URL lands elsewhere, find the right anchor.
3. After downloading both packs, `tr hello` shows Apple's translation. Return pastes it, ⌘Return copies.
4. `tr привет` translates into English; `tr Guten Morgen` into Russian.
5. `tr good morning` shows a MyMemory row under Apple's, or one merged row when they agree.
6. Turning off `Also translate with MyMemory` removes the row.

## Out of scope
- Downloading language packs from the launcher (needs a SwiftUI `.translationTask` host view).
- An explicit target in the query (`tr hello >de`), translating the clipboard or selection.
- A secret setting type or Keychain storage for the key.

## Open questions
none
