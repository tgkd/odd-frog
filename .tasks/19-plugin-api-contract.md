# Task: Plugin system rework 1/13 — the shared `OddFrogPluginAPI` contract library

First of thirteen tasks (19–31) that turn every launcher feature into a separately packaged plugin.
This task adds a new, host-independent library and nothing else; the host keeps working unchanged.
Later tasks (20 onward) depend on the exact names defined here, so treat every type, field, and
string in this spec as fixed.

## Goal
A new SwiftPM library target `OddFrogPluginAPI` exists with serializable manifests, items, actions,
icon specs, settings definitions, protocol messages, a `PluginServer` loop for provider executables,
and a manifest parser with validation. It has its own test target and `swift test` passes with the
new tests included. `OddFrogCore` and `OddFrog` are untouched apart from `Package.swift`.

## Files
- Package.swift                                              (modify — add two targets)
- Sources/OddFrogPluginAPI/PluginAPI.swift                   (create — version constant, JSONValue)
- Sources/OddFrogPluginAPI/PluginItem.swift                  (create — PluginItem, ArgumentSpec, IconSpec, IconColor)
- Sources/OddFrogPluginAPI/PluginAction.swift                (create — PluginAction and its nested enums)
- Sources/OddFrogPluginAPI/PluginManifest.swift              (create — manifest model + SettingDefinition + SettingValue)
- Sources/OddFrogPluginAPI/ManifestParser.swift              (create — TOML parsing + validation)
- Sources/OddFrogPluginAPI/Protocol.swift                    (create — request/response/event envelopes, params, results, Link)
- Sources/OddFrogPluginAPI/PluginServer.swift                (create — provider-side NDJSON loop)
- Tests/OddFrogPluginAPITests/ManifestParserTests.swift      (create)
- Tests/OddFrogPluginAPITests/WireCodingTests.swift          (create)
- Tests/OddFrogPluginAPITests/PluginServerTests.swift        (create)
- Sources/OddFrogCore/Config.swift                           (read — TOMLKit decoding + error mapping pattern to mirror)
- Sources/OddFrogCore/Settings.swift                         (read — `init(from:)` with `decodeIfPresent` defaults pattern)
- Tests/OddFrogCoreTests/ConfigTests.swift                   (read — Swift Testing style to mirror)

## Context
- SwiftPM package, `swift-tools-version: 6.0`, Apple Swift 6.4, `platforms: [.macOS(.v14)]`. Existing
  targets: `OddFrogCore` (library; depends on product `TOMLKit` from `https://github.com/LebJe/TOMLKit`
  0.6.0), `OddFrog` (executable, depends on OddFrogCore), `OddFrogCoreTests` (Swift Testing,
  `resources: [.copy("Fixtures")]`).
- TOMLKit usage pattern (Sources/OddFrogCore/Config.swift): `try TOMLDecoder().decode(RawConfig.self,
  from: text)`; `TOMLParseError` exposes `error.source.begin.line`/`.column` and `description`.
  Encoding: `try TOMLEncoder().encode(value)`.
- Swift 6 strict concurrency is on for every target. All public model types must be `Sendable`.
- Tests use `import Testing`, `struct XTests { @Test func … }`, `#expect`, `#require`. Fixtures are
  loaded via `Bundle.module` only when a test target declares resources; these new tests need no
  fixture files (use inline strings).
- The library must stay Foundation-only (no AppKit, no CoreGraphics) so plugin executables can link it
  without the host. TOMLKit is its only dependency.
- Design decisions already made and fixed for all thirteen tasks (do not re-decide):
  - API version is the integer `1`.
  - Wire format is newline-delimited JSON (one object per line, UTF-8). Requests carry integer `id`,
    `method`, `params` (object). Responses carry `id` and either `result` (object) or `error`
    (`{code, message}`). Events carry `event` (string) and optional `params` (object) and no `id`.
  - Error codes: `invalid`, `conflict`, `unsupported`, `internal`.
  - Global item identity is `"<plugin id>:<local item id>"` (built by the host in later tasks; this
    library only exposes local ids).
  - Plugin id pattern `^[a-z0-9][a-z0-9-]{0,63}$`; setting key pattern `^[a-z][a-z0-9_]{0,31}$`; the
    setting key `enabled` is reserved for the host and rejected in manifests.
  - Icon colors are one of the names `red orange yellow green mint teal cyan blue indigo purple pink
    brown gray` or `#rrggbb` (case-insensitive hex).
  - Services: `open, clipboard, launch, exec, terminal, window, notify`. Provided capabilities: `links`.
    Action → required service: `open`→open, `copy`→clipboard, `launch`/`reveal`→launch, `exec`/`shell`
    →exec, `terminal`→terminal, `window`→window, `callback`→none.
  - Argument placeholder token in actions is the literal string `{argument}` (substituted by the host).

## Plan
1. `Package.swift`: add `.target(name: "OddFrogPluginAPI", dependencies: [.product(name: "TOMLKit",
   package: "TOMLKit")])` and `.testTarget(name: "OddFrogPluginAPITests", dependencies:
   ["OddFrogPluginAPI"])`. Leave the other targets exactly as they are (OddFrogCore does not depend on
   the new library yet; task 20 adds that).

2. `PluginAPI.swift`:
   - `public enum PluginAPI { public static let version = 1 }`.
   - `public enum JSONValue: Codable, Hashable, Sendable` with cases `string(String)`, `number(Double)`,
     `bool(Bool)`, `null`, `array([JSONValue])`, `object([String: JSONValue])`. Custom `init(from:)`
     tries in order: `Bool`, `Double`, `String`, `[JSONValue]`, `[String: JSONValue]`, then `decodeNil`
     → `.null`; `encode(to:)` mirrors. Add `ExpressibleByStringLiteral`, `ExpressibleByIntegerLiteral`,
     `ExpressibleByFloatLiteral`, `ExpressibleByBooleanLiteral`, `ExpressibleByArrayLiteral`,
     `ExpressibleByDictionaryLiteral` conformances so tests can write literals.

3. `PluginItem.swift`:
   - `public struct ArgumentSpec: Codable, Hashable, Sendable { public var placeholder: String; public
     var optional: Bool }` with a public init (`optional` defaults to `false`); decoding treats a
     missing `optional` as false and a missing/empty `placeholder` as `"argument"`.
   - `public struct IconColor: Codable, Hashable, Sendable, RawRepresentable` wrapping `rawValue:
     String`. `public static let names: Set<String>` with the thirteen names. `init?(rawValue:)` accepts a
     name (lowercased) or `#rrggbb` (6 hex digits, stored lowercased); anything else returns nil, and
     decoding an invalid value throws `DecodingError.dataCorrupted`. Provide `public var hex: String?`
     (nil for names) and `public var name: String?` (nil for hex).
   - `public enum IconSpec: Codable, Hashable, Sendable`: `file(path: String)`, `emoji(String)`,
     `symbol(name: String, color: IconColor, size: Double?)`, `glyph(text: String, color: IconColor,
     size: Double?)`. Wire form is a single-key-family object: `{"file": "…"}`, `{"emoji": "…"}`,
     `{"symbol": "link", "color": "teal", "size": 14}`, `{"glyph": "$", "color": "#292929"}`. Decoding
     picks the case by which of `file`/`emoji`/`symbol`/`glyph` is present (exactly one, else throw);
     `color` is required for symbol/glyph; `size` optional.
   - `public struct PluginItem: Codable, Hashable, Sendable` with `id: String`, `title: String`,
     `subtitle: String?`, `kind: String?`, `icon: IconSpec?`, `aliases: [String]` (default `[]`),
     `argument: ArgumentSpec?`, `completion: String?`, `action: PluginAction`, `secondary:
     PluginAction?`, `recordable: Bool` (default `true`). Public memberwise init with those defaults.
     Custom `init(from:)` with `decodeIfPresent` defaults for `aliases`/`recordable`; encoding writes
     every field (nil fields omitted via `encodeIfPresent`). `id` and `title` must be non-empty after
     trimming whitespace; otherwise throw `DecodingError.dataCorrupted` with message "item id is empty"
     / "item title is empty". Aliases are trimmed and lowercased on decode; empty ones dropped.

4. `PluginAction.swift`:
   - `public enum ExecOutput: String, Codable, Sendable { case notify, silent }`.
   - `public enum WindowOperation: String, Codable, Sendable { case place, maximize, tidy }`.
   - `public enum PluginAction: Codable, Hashable, Sendable` with cases and wire keys:
     - `copy(text: String)` → `{"type":"copy","text":…}`
     - `open(url: String)` → `{"type":"open","url":…}`
     - `launch(path: String)` → `{"type":"launch","path":…}`
     - `reveal(path: String)` → `{"type":"reveal","path":…}`
     - `exec(executable: String, arguments: [String], cwd: String?, output: ExecOutput)` →
       `{"type":"exec","executable":…,"arguments":[…],"cwd":…,"output":"notify"}`; `arguments` default
       `[]`, `output` default `notify`.
     - `shell(command: String, cwd: String?)` → `{"type":"shell","command":…,"cwd":…}`
     - `terminal(command: String, cwd: String?)` → `{"type":"terminal","command":…,"cwd":…}`
     - `window(operation: WindowOperation, edge: String?, numerator: Int?, denominator: Int?)` →
       `{"type":"window","operation":"place","edge":"left","numerator":1,"denominator":2}`
     - `callback(name: String, payload: [String: JSONValue])` → `{"type":"callback","name":…,"payload":{…}}`;
       `payload` default `{}`.
     Decoding an unknown `type` throws `DecodingError.dataCorrupted` "unknown action type 'x'".
   - `public enum HostService: String, Codable, Sendable, CaseIterable { case open, clipboard, launch,
     exec, terminal, window, notify }` and `public enum ProvidedCapability: String, Codable, Sendable,
     CaseIterable { case links }`.
   - `public extension PluginAction { var requiredService: HostService? }` per the mapping in Context
     (`callback` → nil).

5. `PluginManifest.swift`:
   - `public enum ProviderMode: String, Codable, Sendable { case persistent, oneshot }`.
   - `public enum QueryRole: String, Codable, Sendable { case exclusive, live, fallback }`.
   - `public enum QueryActivation: String, Codable, Sendable { case all, keyword }`.
   - `public struct ProviderSpec: Hashable, Sendable { mode: ProviderMode; executable: String;
     arguments: [String]; catalog: Bool }` with a public memberwise init (defaults `arguments: []`,
     `catalog: false`).
   - `public struct QuerySpec: Hashable, Sendable { role: QueryRole; prefix: String?; activation:
     QueryActivation; keywords: [String]; priority: Int }` with a public memberwise init (defaults
     `prefix: nil`, `activation: .keyword`, `keywords: []`, `priority: 100`). Every struct in this
     file has a public init so host tests (tasks 21–23) can build manifests without TOML.
   - `public enum SettingType: String, Codable, Sendable { case bool, string, number, choice, folders }`.
   - `public enum SettingValue: Hashable, Sendable { case bool(Bool), string(String), number(Double),
     folders([String]) }` (choice values are stored as `.string`). Add `public var json: JSONValue` and
     `public init?(json: JSONValue, type: SettingType)` (returns nil on a type mismatch; integers decode
     as `.number`).
   - `public struct SettingDefinition: Hashable, Sendable { key: String; type: SettingType; title:
     String; description: String?; defaultValue: SettingValue; min: Double?; max: Double?; choices:
     [String]; mustContain: String? }` with a public memberwise init (defaults `description: nil`,
     `min: nil`, `max: nil`, `choices: []`, `mustContain: nil`), plus `public func validate(_ value: SettingValue) -> SettingValue?`
     returning the value when it matches the type and constraints (number within min/max when set;
     choice within `choices`; string containing `mustContain` when set; folders is an array of
     non-empty strings), nil otherwise.
   - `public struct PluginManifest: Hashable, Sendable { id: String; name: String; version: String;
     api: Int; description: String?; defaultEnabled: Bool; provider: ProviderSpec?; query: QuerySpec?;
     uses: Set<HostService>; provides: Set<ProvidedCapability>; settings: [SettingDefinition]; items:
     [PluginItem] }` with a public memberwise init (defaults: `description nil`, `defaultEnabled true`,
     `provider nil`, `query nil`, `uses []`, `provides []`, `settings []`, `items []`).
   - `public func effectiveSettings(stored: [String: JSONValue]) -> [String: SettingValue]` on the
     manifest: for each definition, `stored[key]` converted with `SettingValue(json:type:)` and
     `validate`; falls back to `defaultValue`. Also `public var settingsJSON(from:)`-style helper
     `public func settingsJSON(_ values: [String: SettingValue]) -> [String: JSONValue]`.

6. `ManifestParser.swift`:
   - `public enum ManifestError: Error, Equatable, CustomStringConvertible` with cases `toml(String)`,
     `missing(String)` ("plugin.id is required"), `invalid(String)` (free-form message). `description`
     returns the message; `toml` is prefixed `"TOML error: "` with `line:column` like ConfigParser does.
   - `public enum ManifestParser { public static func parse(_ text: String) throws -> PluginManifest;
     public static func load(from url: URL) throws -> PluginManifest }` (`load` reads UTF-8 text and
     calls `parse`; a non-UTF-8 file → `.toml("file is not UTF-8")`).
   - Decode through private `Raw*` `Decodable` structs mirroring the TOML schema below, then build
     and validate. Rules (each violated rule throws with the quoted message):
     - `[plugin]` table required with `id`, `name`, `version`, `api` → `missing("plugin.<key> is required")`.
     - id matches `^[a-z0-9][a-z0-9-]{0,63}$` → `invalid("plugin id 'X' is not lowercase letters, digits and dashes")`.
     - `api` must equal `PluginAPI.version` → `invalid("plugin 'X' needs API N, this host provides 1")`.
     - `[provider]`: `mode` one of persistent/oneshot; `executable` non-empty; `catalog` default false;
       `arguments` default `[]`.
     - `[query]`: `role` required; `prefix` required for exclusive (non-empty, no whitespace) and
       rejected for other roles ("query.prefix is only valid for role = \"exclusive\""); `activation`
       default `keyword`; `keywords` required non-empty for keyword activation, each lowercased with no
       whitespace; `priority` default 100. A `[query]` table without a `[provider]` table →
       `invalid("query needs a provider")`.
     - `[services].uses`/`provides`: unknown names → `invalid("unknown service 'x'")` /
       `invalid("unknown capability 'x'")`. `provides` containing `links` requires `provider.mode ==
       .persistent` → `invalid("links requires a persistent provider")`.
     - `[[settings]]`: key pattern and reserved `enabled` ("setting key 'enabled' is reserved");
       duplicate keys; `type` valid; `title` non-empty; `default` present and type-correct (bool → TOML
       bool, string/choice → string, number → int or float, folders → array of strings); `choices`
       non-empty for choice and `default` a member; `min <= max`; `must_contain` only for string.
     - `[[items]]`: decode each as `PluginItem` (the TOML table shape equals the JSON shape); duplicate
       ids → `invalid("duplicate item id 'x'")`; an action or secondary whose `requiredService` is not
       in `uses` → `invalid("item 'x' uses service 'open' which is not declared in services.uses")`;
       `callback` actions in items when `provider == nil` → `invalid("item 'x' uses a callback but the
       package has no provider")`.
     Decoding `[[items]]` through TOMLKit: decode the items array as `[PluginItem]` directly with
     `TOMLDecoder` (the `Codable` implementation from step 3 must therefore not rely on
     JSON-only features; `JSONValue` decoding through TOMLKit must work for `callback.payload` — cover
     this in a test).

7. `Protocol.swift`:
   - `public struct Request: Codable, Sendable { id: Int; method: String; params: JSONValue }`
     (params default `.object([:])`).
   - `public struct ResponseError: Codable, Hashable, Sendable { code: ErrorCode; message: String }`
     with `public enum ErrorCode: String, Codable, Sendable { case invalid, conflict, unsupported, internal }`.
   - `public struct Response: Codable, Sendable { id: Int; result: JSONValue?; error: ResponseError? }`.
   - `public struct Event: Codable, Sendable { event: String; params: JSONValue? }` and
     `public enum EventName { public static let catalogChanged = "catalog_changed"; public static let
     refresh = "refresh" }`.
   - `public enum Method` with static string constants: `initialize`, `catalog`, `query`, `activate`,
     `configure`, `cancel`, `shutdown`, `linksList = "links.list"`, `linksCreate = "links.create"`,
     `linksUpdate = "links.update"`, `linksDelete = "links.delete"`.
   - Typed params/results, all `Codable, Hashable, Sendable`, snake_case wire keys via `CodingKeys`:
     `InitializeParams {api: Int, hostVersion: String, pluginId: String, settings: [String: JSONValue],
     configDir: String, dataDir: String}`, `InitializeResult {api: Int, name: String, version: String}`,
     `CatalogResult {items: [PluginItem]}`, `QueryParams {queryId: Int, text: String, input: String,
     keyword: String?, settings: [String: JSONValue]?}` (settings only used by one-shot providers),
     `QueryResult {items: [PluginItem]}`, `ActivateParams {itemId: String, name: String, payload:
     [String: JSONValue], argument: String?, secondary: Bool}`, `ActivateResult {action: PluginAction?,
     message: String?}`, `ConfigureParams {settings: [String: JSONValue]}`, `CancelParams {queryId: Int}`,
     `Link {id: String, revision: Int, name: String, url: String, aliases: [String]}`, `LinksListResult
     {links: [Link]}`, `LinkCreateParams {name, url, aliases}`, `LinkUpdateParams {id, revision, name,
     url, aliases}`, `LinkDeleteParams {id, revision}`, `LinkResult {link: Link}`.
   - `public enum Wire` helpers: `static func encodeLine<T: Encodable>(_ value: T) throws -> Data`
     (JSONEncoder with `.sortedKeys`, `.withoutEscapingSlashes`, appends `\n`), `static func decode<T:
     Decodable>(_ type: T.Type, from line: Data) throws -> T`, `static let maxLineBytes = 4 * 1024 *
     1024`, plus `static func decodeParams<T: Decodable>(_ type: T.Type, from value: JSONValue) throws
     -> T` and `static func encodeResult<T: Encodable>(_ value: T) throws -> JSONValue` (round-trip
     through `JSONEncoder`/`JSONDecoder`).

8. `PluginServer.swift` (provider side):
   - `public protocol PluginHandler: AnyObject, Sendable` with async throwing methods taking the typed
     params above: `initialize(_:) -> InitializeResult`, `catalog() -> CatalogResult`, `query(_:) ->
     QueryResult`, `activate(_:) -> ActivateResult`, `configure(_:)`, `cancel(_:)`, `shutdown()`,
     `linksList() -> LinksListResult`, `linksCreate(_:) -> LinkResult`, `linksUpdate(_:) -> LinkResult`,
     `linksDelete(_:)`. Provide a protocol extension with defaults: `catalog`/`query` return empty
     results, `activate` returns `ActivateResult(action: nil, message: nil)`, `configure`/`cancel`/
     `shutdown` do nothing, `links*` throw `PluginError.unsupported("links")`.
   - `public struct PluginError: Error, Sendable { code: ResponseError.ErrorCode; message: String }`
     with static constructors `invalid(_:)`, `conflict(_:)`, `unsupported(_:)`, `internal(_:)`.
   - `public final class PluginServer: Sendable` (use an internal lock or actor for output
     serialization). `public init(handler: any PluginHandler, input: FileHandle = .standardInput,
     output: FileHandle = .standardOutput)`. `public func run() async` reads the input line by line
     (accumulate bytes until `\n`; lines longer than `Wire.maxLineBytes` → write an `internal` error
     response when an id can be salvaged, otherwise skip), decodes a `Request`, dispatches by `method`
     to the handler inside a `Task` per request so `cancel` can arrive while a `query` runs, encodes the
     `Response` (result via `Wire.encodeResult`, thrown `PluginError` → its code/message, any other
     error → `internal` with `String(describing:)`), and writes it atomically (one `write` call per
     line under the lock). Unknown method → `unsupported` error. EOF on stdin → call `handler.shutdown()`
     and return. `shutdown` request → respond, then return from `run()` after the response is written.
   - `public func emit(_ event: Event)` writes an event line under the same lock.
   - `public static func main(handler:)`-style convenience: `public static func serve(_ handler: any
     PluginHandler) async` creating a server on standard streams and running it.

9. Tests (`Tests/OddFrogPluginAPITests/`):
   - `ManifestParserTests`: a full valid manifest string (use the calculator example from the schema
     with a `[[settings]]` bool, a `[[items]]` declarative item with a `window` action, `services.uses
     = ["clipboard", "window"]`) parses into the expected `PluginManifest`; each rule in step 6
     has one failing case asserting the thrown `ManifestError` description (missing id, bad id pattern,
     api mismatch, exclusive without prefix, keyword activation without keywords, query without
     provider, unknown service, reserved setting key, choice default not in choices, duplicate item id,
     undeclared service for an item action, callback item without provider). One test decodes a
     `[[items]]` entry with `action = { type = "callback", name = "x", payload = { a = 1, b = "y" } }` in
     a manifest that has a provider and checks the payload is `["a": 1, "b": "y"]`.
   - `WireCodingTests`: JSON round trip for every `PluginAction` case, every `IconSpec` case, a full
     `PluginItem` with defaults omitted (`{"id":"a","title":"A","action":{"type":"copy","text":"x"}}`
     decodes with `aliases == []`, `recordable == true`, `secondary == nil`), invalid `IconColor`
     rejected, unknown action type rejected, `effectiveSettings` overlays valid stored values and
     ignores invalid ones (wrong type, out-of-range number, bad choice, missing `must_contain`),
     `Request`/`Response`/`Event` line encoding ends with `\n` and contains no unescaped newlines.
   - `PluginServerTests`: drive a `PluginServer` over `Pipe`s with a test handler (a `final class`
     conforming to `PluginHandler`) that answers `initialize`, `query` (echoes `input` as one item), and
     `linksList` throwing unsupported; assert: responses carry the request id; unknown method →
     `unsupported`; a `query` that sleeps 200 ms can be `cancel`led (the handler records the cancel);
     closing the write end makes `run()` return and calls `shutdown()`; `emit` writes an event line
     that decodes as `Event`.

## Constraints
- No code comments of any kind, in any file.
- Every `if`/`guard` body is braced on its own lines (`if x { return nil }` on one line is fine; the
  brace is what matters, never a brace-less form).
- Swift 6 strict concurrency: every public model type is `Sendable`; `PluginServer` must compile
  without `@unchecked Sendable` on model types (an `NSLock`-guarded output writer may be
  `@unchecked Sendable`).
- `OddFrogPluginAPI` imports only `Foundation` and `TOMLKit`. No AppKit, no CoreGraphics.
- Swift Testing only. Tests never read the user's home directory or the network.
- Do not modify `Sources/OddFrogCore`, `Sources/OddFrog`, `Tests/OddFrogCoreTests`, `Makefile`, or
  `README.md`.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift build` succeeds (from the repo root).
- `swift test` passes, including the three new suites, and the existing 109 OddFrogCore tests still pass.
- `swift test --filter OddFrogPluginAPITests` runs only the new suites and passes.

## Out of scope
- Any host-side use of the library (task 20 starts that).
- Plugin executables, discovery, process supervision, bundling.
- A `plugin.toml` for any bundled plugin (task 25 onward).

## Open questions
none
