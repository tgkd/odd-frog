# Task: Add a bundled Translate plugin: Apple Translation offline, DeepL Free online

## Goal
A new bundled plugin `translate` (keyword `tr`, on by default) translates the typed text between
two languages the user picks. Text in "your language" goes into the other one; anything else goes
into your language. Apple Translation answers offline when its language packs are installed. When a
DeepL API key is set, a second row with DeepL's translation appears under it. Return pastes the
translation into the app that was active, ⌘Return copies it.

## Files
- Plugins/Translate/plugin.toml                                              (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateLanguage.swift      (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateDirection.swift     (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslationOutcome.swift     (create)
- Plugins/Translate/Sources/TranslatePluginCore/AppleTranslator.swift        (create)
- Plugins/Translate/Sources/TranslatePluginCore/DeepLClient.swift            (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateProvider.swift      (create)
- Plugins/Translate/Sources/TranslatePluginCore/TranslateHandler.swift       (create)
- Plugins/Translate/Tests/TranslateDirectionTests.swift                      (create)
- Plugins/Translate/Tests/DeepLClientTests.swift                             (create)
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
- **DeepL API.** `POST /v2/translate` on `https://api-free.deepl.com` for Free keys (they end with
  `:fx`) and `https://api.deepl.com` otherwise. Header `Authorization: DeepL-Auth-Key <key>`, JSON body
  `{"text": ["…"], "target_lang": "RU"}`, no `source_lang` (DeepL detects it). Answer
  `{"translations": [{"detected_source_language": "EN", "text": "…"}]}`. Status 403 is a bad key,
  456 a used-up quota, 429 too many requests. English and Portuguese targets need a variant
  (`EN-US`, `PT-BR`); Chinese uses `ZH-HANS`.
- The key is a plain `string` setting, stored in the config file like Chat's `api_key`. There is no
  secret setting type, and adding one is out of scope.
- Two tests hard-code the bundled plugin count (`== 15`), and `BundledPackageTests` force-unwraps
  `queries[id]!` for every bundled package.

## Plan
1. **`plugin.toml`.** `id = "translate"`, `name = "Translate"`, `version = "0.1.0"`, `api_version = 2`,
   `keyword = "tr"`, `mode = "persistent"`, `activation = "exclusive"`, `capabilities = []`. Settings:
   - `primary_language`: title `Your language`, `choice` over the names in Plan 2, default `Russian`.
   - `secondary_language`: title `Translate your language into`, `choice`, default `English`.
   - `deepl_key`: title `DeepL API key (optional; Free keys end with :fx)`, `string`, default `""`.

2. **`TranslateLanguage`** (public struct, `Sendable, Hashable`): `name`, `code` (Apple/BCP-47 base
   code), `deepLTarget`. `static let all` lists the languages both engines support: Arabic `ar` AR,
   Chinese `zh` ZH-HANS, Danish `da` DA, Dutch `nl` NL, English `en` EN-US, French `fr` FR, German `de`
   DE, Indonesian `id` ID, Italian `it` IT, Japanese `ja` JA, Korean `ko` KO, Norwegian `nb` NB, Polish
   `pl` PL, Portuguese `pt` PT-BR, Russian `ru` RU, Spanish `es` ES, Swedish `sv` SV, Turkish `tr` TR,
   Ukrainian `uk` UK. `named(_:)` looks up by name, `matching(code:)` by base language code
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
   TranslationOutcome`) and `OnlineTranslator` (`translate(_:to:key:) async -> TranslationOutcome`),
   both `Sendable`.

5. **`AppleTranslator`** (public struct, `OfflineTranslator`). Creates a `TranslationSession` per call:
   the class is not `Sendable`, so an actor cannot keep one. It first checks `LanguageAvailability().status(from:to:)`:
   `supported` → `notInstalled`, `unsupported` → `unsupported`. A thrown `notInstalled` →
   `notInstalled`. Any other error → `failed(localizedDescription)`.

6. **`DeepLClient`** (public struct, `OnlineTranslator`) over an injected `URLSession`:
   - `static func endpoint(for key:) -> URL`, `static func urlRequest(_ text:, target:, key:) throws ->
     URLRequest` (8 s timeout), `static func outcome(status: Int, data: Data) -> TranslationOutcome`.
   - Messages: 403 `DeepL rejected the API key. Check it in Translate settings.`, 456
     `The DeepL quota for this month is used up.`, 429 `DeepL is busy. Try again in a moment.`, other
     non-2xx `DeepL answered with HTTP <status>.`, unreadable body `DeepL sent an answer Odd Frog can't
     read.`, network error `Can't reach DeepL: <localizedDescription>`.

7. **`TranslateProvider`** builds rows (`kind: "Translate"`).
   - `hint(primary:secondary:deepL:)` → one row `hint`: `Type text to translate`, subtitle
     `Russian ⇄ English · Apple Translation` plus ` and DeepL` when a key is set, symbol
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
   - DeepL row `deepl`, only when online is not `off`, same shapes with `DeepL · English → Russian`,
     `Translating with DeepL…` while pending, `DeepL translation failed` on failure.
   - When both are `text` and equal, one row `apple` with subtitle `Apple and DeepL · English → Russian`.
   - When Apple has no translation and DeepL has one, the DeepL row comes first, so Return pastes it.

8. **`TranslateHandler`** (public actor, `ProviderHandler`):
   `init(offline: any OfflineTranslator = AppleTranslator(), online: any OnlineTranslator = DeepLClient(),
   offlineWait: Duration = .milliseconds(600), onlineDelay: Duration = .milliseconds(350))`.
   - `start(emit:)` stores `emit`. `initialize` → `{"apiVersion": 2}`, `settings` → `{}`.
   - `query`: trim the text, cap it at `TranslateProvider.limit` (2 000) characters, resolve the
     direction from settings. Empty text → `hint`, equal languages → `sameLanguages`.
   - A translation that is empty after trimming becomes `failed("The translation came back empty.")`:
     a row with an empty title would make the coordinator disable the plugin.
   - Offline: results cache keyed by text + source + target. On a miss, start one job per key that
     translates and stores the result. `query` waits for the job at most `offlineWait`. If the job ends
     after `query` stopped waiting and its text is still the latest one asked for, it emits
     `queryInvalidated`.
   - Online (key not empty): results cache keyed by text + target + key. On a miss, cancel the previous
     online job and start a new one that sleeps `onlineDelay` (typing pauses), translates, stores, and
     emits `queryInvalidated`. `query` never waits for it and shows the pending row.
   - Only `text` results stay cached. Other outcomes are reused for 10 s and then retried, so installing
     a language pack or fixing the key takes effect without a restart. Each cache is cleared when it
     passes 256 entries.

9. **Wiring.** `Package.swift`: `TranslatePluginCore` target (deps `OddFrogPluginAPI`), add it to
   `OddFrogBuiltins`, test target `TranslatePluginTests`. `BuiltinProviders`: `"translate": {
   TranslateHandler() }`. `BundledPackageTests`: count 16, query `"translate": "tr"`, wait until the first
   row is `hint`, expect its title. `MigrationTests`: count 16.

10. **Tests** (fake translators, no network, no Apple Translation):
    - Direction: `привет` → Russian→English, `hello` → English→Russian, a German sentence → German→Russian,
      settings fallback.
    - DeepL: Free vs Pro endpoint, headers and JSON body, `EN-US` target, parsing, 403/456/429/500 and
      garbage body messages.
    - Provider: hint row (with and without DeepL), all Apple outcomes, pending DeepL row, merge of equal
      results, same-language row.
    - Handler: offline answer inside `offlineWait`; slow offline answer arrives through
      `queryInvalidated`; no DeepL row without a key; DeepL pending row, then `queryInvalidated`, then the
      cached result; only the last of several fast queries reaches DeepL; a failure is retried after
      expiry (inject a short retry interval).

## Constraints
- Swift 6 strict concurrency, no new warnings.
- Match surrounding code: one type per file, `RPCError`, `JSONValue`, braced early returns.
- No comments in new code unless the reason is not obvious from the code.
- No changes to the coordinator, host app, or other plugins.
- Tests never call DeepL or Apple Translation.

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
5. Put a DeepL Free key into Settings › Plugins › Translate. `tr good morning` shows a DeepL row
   under Apple's, or one merged row when they agree.
6. A broken key shows `DeepL rejected the API key…`. Fixing it works within 10 s.

## Out of scope
- Downloading language packs from the launcher (needs a SwiftUI `.translationTask` host view).
- An explicit target in the query (`tr hello >de`), translating the clipboard or selection.
- A secret setting type or Keychain storage for the key.

## Open questions
none
