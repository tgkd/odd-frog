# Task: Inline calculator — unit conversion through Foundation `Measurement`

Task 15 of the calculator series. Requires task 14 (`14-inline-calculator-arithmetic.md`):
`QuickAction.calculation`, `CalculationKind`, `QuickAction.calculation(for:)`, the
`SearchEngine` placement and the `ActionExecutor`/`IconCache` arms all exist. Task 16 follows.

## Goal
Typing `100 km in miles`, `50 kg to lb`, `20 c in f`, `512 gb in gib`, `1.5h in min` or
`100km mi` shows a "Units" row first with the converted value and unit as the title (for
example `62.1371 mi`) and the normalised input as the subtitle. Return copies the numeric
result. Conversion factors come from Foundation's `Measurement`/`Dimension` classes; the task
adds only a token registry and a tiny grammar. Incompatible dimensions (`100 kg in miles`)
produce no row.

## Files
- Sources/OddFrogCore/UnitRegistry.swift            (create — token → unit table)
- Sources/OddFrogCore/UnitConversion.swift          (create — grammar + evaluation)
- Sources/OddFrogCore/QuickAction.swift             (modify — `.measurement` kind, second evaluator)
- Sources/OddFrog/IconCache.swift                   (modify — tile for the Units kind)
- Tests/OddFrogCoreTests/UnitConversionTests.swift  (create)
- Tests/OddFrogCoreTests/QuickActionTests.swift     (modify — one row test)
- README.md                                         (modify — Usage paragraph)
- Sources/OddFrogCore/Arithmetic.swift              (read — number token rules to mirror)

## Context
- Everything in task 14's Context still holds. After task 14, `QuickAction` has
  `case calculation(input: String, value: Double, kind: CalculationKind)` whose `title` is the
  grouped number and `copyText` the ungrouped one, `kindLabel` switches on `kind`, and
  `SearchEngine.search` puts `QuickAction.calculation(for:)` first when non-nil.
- Verified on this machine (macOS 27, Swift 6):
  `Measurement(value: 100, unit: UnitLength.kilometers).converted(to: .miles).value` is
  `62.13711922373339`; `.formatted(.measurement(width: .abbreviated, usage: .asProvided,
  numberFormatStyle: .number.precision(.fractionLength(0...4))))` prints `62.1371 mi`;
  20 °C → `68°F`; 512 GB → `476.8372 GiB`; 1.5 hr → `90 min`. `usage: .asProvided` is
  required — the default usage re-picks units for the locale. `UnitLength.kilometers.symbol`
  is `km`, `UnitDuration.hours.symbol` is `hr`, `UnitInformationStorage.gibibytes.symbol` is
  `GiB`. `UnitDuration` has no days or weeks; `UnitInformationStorage` has bits, bytes, and
  the kilo…peta plus kibi…pebi families for both.
- `Dimension` subclasses are `NSObject`s and not `Sendable`; `Measurement<UnitLength>` etc.
  are fine to use inside a synchronous function but must not be stored in `QuickAction`
  (which is `Sendable, Hashable`). Store the formatted strings.
- Two units are compatible when `type(of: a) == type(of: b)`; `Measurement.converted(to:)`
  traps on a mismatch, so the check is mandatory before converting. Verified:
  `type(of: UnitLength.kilometers) == type(of: UnitMass.kilograms)` is `false`.
- Task 14's number token: digits with at most one `.`, leading `.5` allowed, no thousands
  separators, no exponent. Reuse the same rule (copy the small scanner or expose it as
  `Arithmetic.scanNumber(_:) -> (Double, Substring)?` — either is acceptable; if exposing,
  keep it `static` and internal).
- Decision, already made: the conversion row is a second `CalculationKind`, so the executor,
  the icon cache switch, the row rendering and the never-recorded id all come from task 14.
  Arithmetic is tried first, then conversion; each query yields at most one calculator row.

## Plan
1. Create `Sources/OddFrogCore/UnitRegistry.swift`:
   `public enum UnitRegistry` with `static func unit(for token: String) -> Dimension?`
   (lookup is case-insensitive on the lowercased token; `°` is stripped first so `°c` and
   `°f` resolve). The table, grouped by dimension — every listed spelling must resolve:
   - `UnitLength`: `mm millimeter(s)`, `cm centimeter(s)`, `m meter(s) metre(s)`,
     `km kilometer(s) kilometre(s)`, `in inch inches` (`in` as a unit is only valid in the
     position of a unit token — see step 2), `ft foot feet`, `yd yard(s)`, `mi mile(s)`,
     `nmi nautical mile(s)`.
   - `UnitMass`: `mg milligram(s)`, `g gram(s)`, `kg kilogram(s)`, `t tonne(s) ton(s)`
     (`.metricTons`), `oz ounce(s)`, `lb lbs pound(s)`, `st stone(s)`.
   - `UnitTemperature`: `c celsius`, `f fahrenheit`, `k kelvin`.
   - `UnitInformationStorage`: `bit(s)`, `byte(s)`, `kb kilobyte(s)`, `mb megabyte(s)`,
     `gb gigabyte(s)`, `tb terabyte(s)`, `pb petabyte(s)`, `kib kibibyte(s)`,
     `mib mebibyte(s)`, `gib gibibyte(s)`, `tib tebibyte(s)`, `pib pebibyte(s)`.
   - `UnitDuration`: `ms millisecond(s)`, `s sec second(s)`, `min minute(s)`,
     `h hr hour(s)`.
   - `UnitVolume`: `ml milliliter(s)`, `l liter(s) litre(s)`, `tsp teaspoon(s)`,
     `tbsp tablespoon(s)`, `floz`, `cup(s)`, `pt pint(s)`, `qt quart(s)`, `gal gallon(s)`
     (US variants: `.fluidOunces`, `.cups`, `.pints`, `.quarts`, `.gallons`).
   - `UnitSpeed`: `kph kmh`, `mph`, `mps`, `kn knot(s)`.
   - `UnitArea`: `sqm m2`, `sqkm km2`, `sqft ft2`, `sqmi mi2`, `ha hectare(s)`, `acre(s)`.
   Build the table once as a `static let` dictionary `[String: Dimension]`; Foundation's unit
   singletons are safe to store under `nonisolated(unsafe)` — mark the dictionary
   `nonisolated(unsafe) static let` to satisfy strict concurrency, since `Dimension` is not
   `Sendable`.
2. Create `Sources/OddFrogCore/UnitConversion.swift`:
   `public struct UnitConversion: Sendable, Hashable { public let input: String; public let
   value: Double; public let result: String }` and `public static func evaluate(_ text:
   String) -> UnitConversion?`.
   Grammar over the trimmed, lowercased text:
   `<number> <ws?> <unit> <ws> (in|to|as|->|=|→) <ws> <unit>` or, without a keyword,
   `<number> <ws?> <unit> <ws> <unit>`. The number may touch the unit (`100km`). Source and
   target unit tokens are single words (letters, digits `2`, `°`). The word `in` is a keyword
   when it sits between two unit tokens and a unit only when it is the last token or the
   source token (`5 in to cm`, `10 cm in in`). Both tokens must resolve and share a dimension;
   otherwise return nil (no row, search proceeds). Any trailing text → nil.
   Compute `Measurement(value:unit:).converted(to:)`, `value` = the converted `.value`,
   `result` = the converted measurement formatted with `.measurement(width: .abbreviated,
   usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...4)))`,
   `input` = `"<number as typed> <source.symbol> → <target.symbol>"` (e.g. `100 km → mi`).
3. `QuickAction.swift`:
   - `CalculationKind` gains `case measurement(result: String)`; `title` for
     `.calculation` returns `result` when the kind is `.measurement`, the grouped number
     otherwise; `kindLabel` returns `"Units"` for it; `copyText` returns the ungrouped
     `value` for both kinds.
   - `calculation(for:)`: after `Arithmetic.evaluate` returns nil, try
     `UnitConversion.evaluate`; on a hit return `.calculation(input: conversion.input,
     value: conversion.value, kind: .measurement(result: conversion.result))`.
4. `IconCache.icon(for:)`: switch on the kind inside `.calculation` — `.measurement` →
   `tile(name: "units", color: .systemGreen, symbol: "ruler", symbolSize: 13, size: size)`;
   `.arithmetic` keeps task 14's tile.
5. Tests.
   - `UnitConversionTests.swift`: `100 km in miles` → `value ≈ 62.1371` (tolerance `1e-3`)
     and `result == "62.1371 mi"`; `20 c in f` → `68` and result `"68°F"`; `512 gb in gib` →
     `≈ 476.8372`; `1.5h in min` → `90`; `100km mi` (no keyword) → `≈ 62.1371`;
     `5 in to cm` → `12.7`; `10 cm in in` → `≈ 3.937`; `2 cups in ml` → `480` (Foundation's cup is 240 mL) with result `"480 mL"`;
     `100 kg in miles` → nil; `100 km in` → nil; `km in mi` → nil; `100 km in mi extra` →
     nil; `1,5 km in mi` → nil. Result-string assertions rely on the `en` symbol set only
     (`mi`, `°F`), which Foundation emits regardless of the machine's region.
   - `QuickActionTests.swift`: `calculation(for: "100 km in mi")` has title `"62.1371 mi"`,
     kind label `"Units"`, subtitle `"100 km → mi"`, `copyText == "62.137119"`;
     `calculation(for: "2+2")` is still the arithmetic row.
6. `README.md`, the calculator paragraph from task 14: add two sentences on unit conversion
   with `100 km in mi`, `20 c in f`, `512 gb in gib` examples, the accepted keywords
   (`in`, `to`, `as`, `->`), and that mismatched dimensions show nothing.

## Constraints
- No code comments of any kind, in any file.
- Swift 6 strict concurrency; `OddFrogCore` stays AppKit-free; `QuickAction` and
  `UnitConversion` stay `Sendable, Hashable` — never store a `Dimension` or `Measurement` in
  them. No new dependencies.
- Braces on every `if`/`guard` body in new code.
- Swift Testing only.
- Surgical changes only; do not touch anything outside Files without saying why.

## Acceptance
- `swift test` passes (from the repo root).
- `swift build -c release` succeeds.
- Manual after `make run`: `100 km in miles` → "62.1371 mi" first, green ruler tile, kind
  "Units"; ↩ then ⌘V pastes `62.137119`. `20 c in f` → "68°F". `100 kg in miles` → no
  calculator row, the usual search results. `2+2` still shows the Calculator row.

## Out of scope
- Currency (task 16). Compound units (`5 ft 10 in`), arithmetic on measurements
  (`2 * 5 km`), days/weeks, fuel economy, pressure, energy, power, angles.
- Localised unit spellings in the input; the registry is English only.

## Open questions
none
