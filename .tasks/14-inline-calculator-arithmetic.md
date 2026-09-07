# Task: Inline calculator — arithmetic expressions as a top result row

Task 14, first of the calculator series. Tasks 15 (`15-unit-conversion.md`) and 16
(`16-currency-conversion.md`) build on the types this task introduces and must run after it.

## Goal
Typing an arithmetic expression such as `2+2`, `5 * (20 + 4) / 3` or `20% of 500` into the
launcher shows a "Calculator" row at the top of the list with the result as its title and the
expression as its subtitle. Return copies the result to the clipboard and hides the panel.
Plain text like `cal`, a bare number like `42`, or anything the parser rejects behaves exactly
as today. Everything is offline and lives in `OddFrogCore` except icon and clipboard handling.

## Files
- Sources/OddFrogCore/Arithmetic.swift              (create — tokenizer, Pratt parser, evaluator)
- Sources/OddFrogCore/QuickAction.swift             (modify — `.calculation` case, `CalculationKind`, `calculation(for:)`)
- Sources/OddFrogCore/SearchEngine.swift            (modify — calculator row first, before ranking)
- Sources/OddFrog/ActionExecutor.swift              (modify — copy result on Return)
- Sources/OddFrog/IconCache.swift                   (modify — tile for the calculator row)
- Tests/OddFrogCoreTests/ArithmeticTests.swift      (create)
- Tests/OddFrogCoreTests/QuickActionTests.swift     (modify — calculation row tests)
- Tests/OddFrogCoreTests/SearchEngineTests.swift    (modify — placement tests)
- README.md                                         (modify — Usage paragraph)
- Sources/OddFrogCore/Item.swift                    (read — `LauncherItem.quick` delegates to `QuickAction`; nothing to change)
- Sources/OddFrog/LauncherViewController.swift      (read — `.quick` rows already render `subtitle` as the detail line; nothing to change)

## Context
- SwiftPM package, Swift 6 language mode with strict concurrency, `platforms: [.macOS(.v14)]`,
  one dependency (TOMLKit). `OddFrogCore` has no AppKit import anywhere. Tests use Swift
  Testing (`import Testing`, `@Test`, `#expect`, `Issue.record`). No Xcode project; `swift test`
  and `swift build -c release` from the repo root are the whole toolchain. 83 tests pass today.
- `QuickAction` (Sources/OddFrogCore/QuickAction.swift) is `enum QuickAction: Sendable, Hashable`
  with `.openURL(URL)`, `.webSearch(query:url:)`, `.terminal(String)`, computed `id`, `title`,
  `subtitle`, `kindLabel`, and `static func fallbacks(for:searchTemplate:)`. `LauncherItem.quick`
  (Sources/OddFrogCore/Item.swift) delegates `id`/`title`/`subtitle`/`kindLabel` to it, returns
  `[]` aliases, `false` for `acceptsArgument`, and `withAliases` returns `self` — adding an enum
  case therefore needs switch arms only inside `QuickAction` itself, `IconCache.icon(for:)` and
  `ActionExecutor.run`. `ActionExecutor.runSecondary` routes `.quick` to `run`, so ⌘↩ needs
  nothing.
- `SearchEngine.search(query:items:weights:maxResults:searchTemplate:)`
  (Sources/OddFrogCore/SearchEngine.swift): trims the query; empty → `recent`; `>` prefix →
  `fallbackResults`; otherwise ranks every item, sorts with `order`, and returns
  `fallbackResults` when nothing matched, else `prefix(maxResults)`. `RankedItem(item:lexical:
  weight:exactAlias:argument:)`; fallback rows use `lexical: 0, weight: 0, exactAlias: false`.
- `LauncherViewController.detail(for:)` returns `quick.subtitle` as the detail line for
  `.quick` rows, `configure` shows `kindLabel` right-aligned in tertiary colour, `⇥` fills the
  field with `aliases.first ?? title` — for a calculator row that inserts the result, which is
  fine. `handleKeyEquivalent` already refuses ⌘I on quick rows.
- `ActionExecutor.record(_:)` skips ids with the `quick:` prefix, so calculator rows never enter
  frecency. The existing clipboard pattern (URL copy in `runSecondary`) is
  `NSPasteboard.general.clearContents(); setString(_:forType: .string)` followed by `Log.write`.
- `IconCache.tile(name:color:symbol:symbolSize:size:)` draws an SF Symbol on a rounded tile and
  caches by `name`. Existing tiles: `url` teal `link` 14, `search` indigo `magnifyingglass` 13,
  window tiles purple 13.
- Number formatting: `Double.formatted(.number.precision(.fractionLength(0...6)))` yields
  locale-grouped text (`1,234,567.891` in en_US). Tests must stay locale-independent, so assert
  on `Double` values from `Arithmetic.evaluate` and only on grouping-free strings from titles.
- Design decision, already made: the calculator is a `QuickAction` row, not a `LauncherItem`
  kind of its own — it reuses the row rendering, icon, kind label and the never-recorded id
  prefix for free. `NSExpression` is not used; the parser is hand-written (about 150 lines) so
  `%`, `of`, `^` and unicode operators behave exactly as specified.

## Plan
1. Create `Sources/OddFrogCore/Arithmetic.swift` with `public enum Arithmetic` and
   `public static func evaluate(_ text: String) -> Double?`.
   Tokenizer, over the trimmed text, whitespace ignored between tokens:
   - number: digits with at most one `.`, a leading `.5` allowed, no thousands separators
     (`1,000` → the whole call returns nil), no exponent notation;
   - operators `+ - * / ^ % ( )`; also accept `×` as `*`, `÷` as `/`, `−` as `-`, and the
     letter `x` between two numeric operands (`3x4`, `3 x 4`) as `*`;
   - the word `of` (case-insensitive, must be delimited by whitespace or digits) as an infix
     operator equivalent to `*`;
   - any other character → nil.
   Pratt parser, precedence low to high: `+ -` (1, left) < `* / of` (2, left) < unary `-`/`+`
   (3) < `^` (4, right-assoc) < postfix `%` (5). So `-2^2` is `-4`, `2^3^2` is `512`,
   `20%` is `0.2`. Percent on the right of `+` or `-`, when the right operand is exactly a
   number literal followed by `%` (no parentheses), is relative to the left operand:
   `500 + 20%` is `600`, `500 - 20%` is `400`. Everywhere else `n%` is `n / 100`:
   `500 * 20%` is `100`, `20% of 500` is `100`.
   Return nil when: the text contains no binary operator and no `%` (a bare number or `(42)`),
   the parse does not consume every token, a division by zero occurs, or the result is not
   finite. Depth is bounded by the expression length; no recursion guard needed beyond a
   sensible cap of 64 nested parentheses (return nil beyond).
2. `QuickAction.swift`:
   - add `public enum CalculationKind: Sendable, Hashable { case arithmetic }` (tasks 15 and
     16 add cases);
   - add `case calculation(input: String, value: Double, kind: CalculationKind)` (`Double`
     is `Hashable`, so the enum stays `Hashable`);
   - `id`: `"quick:calc:\(input)"`; `title`: `value.formatted(.number.precision(
     .fractionLength(0...6)))`; `subtitle`: `input`; `kindLabel`: `"Calculator"` for
     `.arithmetic`;
   - add `public var copyText: String?`: for `.calculation`, `value.formatted(.number
     .grouping(.never).precision(.fractionLength(0...6)))`; nil for every other case. Keep it
     a switch over cases — tasks 15 and 16 add cases that carry pre-formatted strings;
   - add `public static func calculation(for query: String) -> QuickAction?`: trim; run
     `Arithmetic.evaluate`; on a value return `.calculation(input: <trimmed query>, value:
     value, kind: .arithmetic)`, else nil;
   - `fallbacks(for:searchTemplate:)` is unchanged.
3. `SearchEngine.search`: after the `>` branch and before ranking, compute
   `let calculation = QuickAction.calculation(for: trimmed)`. Build the ranked list as today.
   If `calculation` is non-nil: return `[RankedItem(item: .quick(calculation), lexical: 0,
   weight: 0, exactAlias: false)] + ranked.prefix(max(0, maxResults - 1))` — and do NOT fall
   back to `fallbackResults` when `ranked` is empty (the calculation is the answer; a
   "Search for 2+2" row underneath is noise). If nil, behaviour is exactly as before.
4. `ActionExecutor.run`, `.quick` arm: add `case .calculation:` that puts `quick.copyText` on
   the general pasteboard (clear, then `setString(_:forType: .string)`), then
   `Log.write("copied calculator result \(text)")`. No notification. Do not call `record`.
5. `IconCache.icon(for:)`, `.quick` arm: `.calculation` → `tile(name: "calc", color:
   .systemOrange, symbol: "plus.forwardslash.minus", symbolSize: 13, size: size)`.
6. Tests.
   - `ArithmeticTests.swift`: `evaluate` returns `4` for `2+2`, `40` for `5 * (20 + 4) / 3`,
     `-4` for `-2^2`, `512` for `2^3^2`, `600` for `500 + 20%`, `400` for `500 - 20%`,
     `100` for `500 * 20%`, `100` for `20% of 500`, `12` for `3x4` and `3 × 4`, `2.5` for
     `5 ÷ 2`, `0.75` for `.5 + .25`; returns nil for `42`, `(42)`, `1,000`, `2 +`, `cal 2`,
     `1/0`, `2 ** 3`, `hello`, and the empty string. Compare doubles with an absolute
     tolerance of `1e-9` where the value is not exactly representable.
   - `QuickActionTests.swift`: `calculation(for: "2+2")` has title `"4"`, subtitle `"2+2"`,
     kind label `"Calculator"`, id `"quick:calc:2+2"`, `copyText == "4"`;
     `calculation(for: "0.1+0.2")` has title `"0.3"` (six-place rounding);
     `calculation(for: "safari")` and `calculation(for: "42")` are nil.
   - `SearchEngineTests.swift`: `calculatorRowComesFirst` — items
     `[cmd("Double It", aliases: ["2+2"])]`, query `2+2`, `maxResults: 8`: first result is
     `.quick(.calculation)` with title `"4"`, followed by the command, so the calculator wins
     even over an exact alias (an arithmetic expression cannot fuzzy-match an ordinary app
     title, since operators are not letters); `calculatorRowReplacesFallbacks` — query `2*3`
     over `[app("Zed")]` with a search template returns exactly one row, the calculation;
     `bareNumberStillSearches` — query `1` over `[app("1Password")]` returns just the app.
7. `README.md`, Usage section, after the fallback paragraph: one paragraph saying an
   arithmetic expression shows a Calculator row first, listing the supported operators
   (`+ - * / ^ %`, parentheses, `x` or `×` for multiply, `of`), the percent rule with the
   `500 + 20%` example, and that Return copies the result.

## Constraints
- No code comments of any kind, in any file.
- Swift 6 strict concurrency: new Core types are `public`, `Sendable`, `Hashable`; no AppKit in
  `OddFrogCore`; no new dependencies; no `NSExpression`.
- Braces on every `if`/`guard` body, including single-line returns, in new code; match the
  surrounding file's style when editing (existing files use `guard … else { return nil }` on
  one line, which is fine).
- Swift Testing only; tests must not depend on the machine locale beyond en-style `.`
  decimals in inputs.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes (from the repo root), including the new suites.
- `swift build -c release` succeeds.
- Manual after `make run`: ⌥Space, type `5 * (20 + 4) / 3` → first row "40", subtitle the
  expression, kind "Calculator", orange ± tile; ↩ hides the panel and ⌘V pastes `40`. Type
  `500 + 20%` → "600". Type `1` → only 1Password-style app matches, no calculator row. Type
  `cal` → Calendar/Calculator apps as before. `~/Library/Application Support/odd-frog/frecency.json`
  gains no `quick:` ids.

## Out of scope
- Unit and currency conversion (tasks 15, 16). Functions (`sqrt`, `sin`, `log`), modulo,
  bitwise operators, hex/binary literals, variables, `ans`.
- A Settings switch to disable the calculator.
- Showing the result inline in the search field.

## Open questions
none
