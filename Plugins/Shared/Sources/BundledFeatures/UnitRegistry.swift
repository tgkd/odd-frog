import Foundation
import OddFrogCore

public enum UnitRegistry {
    private static let table: [String: Dimension] = {
        let entries: [(Dimension, [String])] = [
            (UnitLength.micrometers, ["um", "µm", "micrometer", "micrometers"]),
            (UnitLength.nanometers, ["nm", "nanometer", "nanometers"]),
            (UnitLength.lightyears, ["ly", "lightyear", "lightyears"]),
            (UnitLength.astronomicalUnits, ["au"]),
            (UnitLength.millimeters, ["mm", "millimeter", "millimeters"]),
            (UnitLength.centimeters, ["cm", "centimeter", "centimeters"]),
            (UnitLength.meters, ["m", "meter", "meters", "metre", "metres"]),
            (UnitLength.kilometers, ["km", "kilometer", "kilometers", "kilometre", "kilometres"]),
            (UnitLength.inches, ["in", "inch", "inches"]),
            (UnitLength.feet, ["ft", "foot", "feet"]),
            (UnitLength.yards, ["yd", "yard", "yards"]),
            (UnitLength.miles, ["mi", "mile", "miles"]),
            (UnitLength.nauticalMiles, ["nmi", "nauticalmile", "nauticalmiles"]),

            (UnitMass.micrograms, ["ug", "µg", "microgram", "micrograms"]),
            (UnitMass.carats, ["ct", "carat", "carats"]),
            (UnitMass.milligrams, ["mg", "milligram", "milligrams"]),
            (UnitMass.grams, ["g", "gram", "grams"]),
            (UnitMass.kilograms, ["kg", "kilogram", "kilograms"]),
            (UnitMass.metricTons, ["t", "tonne", "tonnes", "ton", "tons"]),
            (UnitMass.ounces, ["oz", "ounce", "ounces"]),
            (UnitMass.pounds, ["lb", "lbs", "pound", "pounds"]),
            (UnitMass.stones, ["st", "stone", "stones"]),

            (UnitTemperature.celsius, ["c", "celsius"]),
            (UnitTemperature.fahrenheit, ["f", "fahrenheit"]),
            (UnitTemperature.kelvin, ["k", "kelvin"]),

            (UnitInformationStorage.bits, ["bit", "bits"]),
            (UnitInformationStorage.bytes, ["byte", "bytes"]),
            (UnitInformationStorage.kilobytes, ["kb", "kilobyte", "kilobytes"]),
            (UnitInformationStorage.megabytes, ["mb", "megabyte", "megabytes"]),
            (UnitInformationStorage.gigabytes, ["gb", "gigabyte", "gigabytes"]),
            (UnitInformationStorage.terabytes, ["tb", "terabyte", "terabytes"]),
            (UnitInformationStorage.petabytes, ["pb", "petabyte", "petabytes"]),
            (UnitInformationStorage.kibibytes, ["kib", "kibibyte", "kibibytes"]),
            (UnitInformationStorage.mebibytes, ["mib", "mebibyte", "mebibytes"]),
            (UnitInformationStorage.gibibytes, ["gib", "gibibyte", "gibibytes"]),
            (UnitInformationStorage.tebibytes, ["tib", "tebibyte", "tebibytes"]),
            (UnitInformationStorage.pebibytes, ["pib", "pebibyte", "pebibytes"]),

            (UnitDuration.milliseconds, ["ms", "millisecond", "milliseconds"]),
            (UnitDuration.seconds, ["s", "sec", "second", "seconds"]),
            (UnitDuration.minutes, ["min", "minute", "minutes"]),
            (UnitDuration.hours, ["h", "hr", "hour", "hours"]),

            (UnitVolume.cubicMeters, ["m3"]),
            (UnitVolume.cubicCentimeters, ["cm3", "cc"]),
            (UnitVolume.cubicFeet, ["ft3"]),
            (UnitVolume.imperialGallons, ["impgal"]),
            (UnitVolume.milliliters, ["ml", "milliliter", "milliliters"]),
            (UnitVolume.liters, ["l", "liter", "liters", "litre", "litres"]),
            (UnitVolume.teaspoons, ["tsp", "teaspoon", "teaspoons"]),
            (UnitVolume.tablespoons, ["tbsp", "tablespoon", "tablespoons"]),
            (UnitVolume.fluidOunces, ["floz"]),
            (UnitVolume.cups, ["cup", "cups"]),
            (UnitVolume.pints, ["pt", "pint", "pints"]),
            (UnitVolume.quarts, ["qt", "quart", "quarts"]),
            (UnitVolume.gallons, ["gal", "gallon", "gallons"]),

            (UnitSpeed.kilometersPerHour, ["kph", "kmh", "km/h"]),
            (UnitSpeed.milesPerHour, ["mph", "mi/h"]),
            (UnitSpeed.metersPerSecond, ["mps", "m/s"]),
            (UnitSpeed.knots, ["kn", "knot", "knots"]),

            (UnitArea.squareMeters, ["sqm", "m2"]),
            (UnitArea.squareKilometers, ["sqkm", "km2"]),
            (UnitArea.squareFeet, ["sqft", "ft2"]),
            (UnitArea.squareMiles, ["sqmi", "mi2"]),
            (UnitArea.hectares, ["ha", "hectare", "hectares"]),
            (UnitArea.acres, ["acre", "acres"]),
            (UnitFrequency(symbol: "mHz", converter: UnitConverterLinear(coefficient: 0.001)), ["millihertz"]),
            (UnitFrequency.hertz, ["hz", "hertz"]),
            (UnitFrequency.kilohertz, ["kilohertz"]),
            (UnitFrequency.megahertz, ["megahertz"]),
            (UnitFrequency.gigahertz, ["gigahertz"]),
            (UnitPressure.newtonsPerMetersSquared, ["pa", "pascal", "pascals"]),
            (UnitPressure.kilopascals, ["kpa", "kilopascal", "kilopascals"]),
            (UnitPressure.bars, ["bar", "bars"]),
            (UnitPressure.millibars, ["mbar"]),
            (UnitPressure.poundsForcePerSquareInch, ["psi"]),
            (UnitPressure.millimetersOfMercury, ["mmhg"]),
            (UnitEnergy.joules, ["j", "joule", "joules"]),
            (UnitEnergy.kilojoules, ["kj", "kilojoule", "kilojoules"]),
            (UnitEnergy.calories, ["cal", "calorie", "calories"]),
            (UnitEnergy.kilocalories, ["kcal", "kilocalorie", "kilocalories"]),
            (UnitEnergy.kilowattHours, ["kwh"]),
            (UnitPower(symbol: "mW", converter: UnitConverterLinear(coefficient: 0.001)), ["milliwatt", "milliwatts"]),
            (UnitPower.watts, ["w", "watt", "watts"]),
            (UnitPower.kilowatts, ["kilowatt", "kilowatts"]),
            (UnitPower.megawatts, ["megawatt", "megawatts"]),
            (UnitPower.horsepower, ["hp", "horsepower"]),
            (UnitAcceleration.metersPerSecondSquared, ["m/s2", "m/s²"]),
            (UnitAcceleration.gravity, ["g-force"]),
            (UnitAngle.degrees, ["deg", "degree", "degrees"]),
            (UnitAngle.radians, ["rad", "radian", "radians"]),
            (UnitAngle.revolutions, ["rev", "revolution", "revolutions"]),
            (UnitSpeed(symbol: "km/s", converter: UnitConverterLinear(coefficient: 1000)), ["km/s"]),
        ]
        var out: [String: Dimension] = [:]
        for (unit, tokens) in entries {
            for token in tokens { out[token] = unit }
        }
        return out
    }()

    private static let symbols: [String: Dimension] = {
        var result: [String: Dimension] = ["b": UnitInformationStorage.bits, "B": UnitInformationStorage.bytes]
        let storage: [(String, UnitInformationStorage, UnitInformationStorage)] = [
            ("k", .kilobits, .kilobytes), ("K", .kilobits, .kilobytes), ("M", .megabits, .megabytes), ("G", .gigabits, .gigabytes),
            ("T", .terabits, .terabytes), ("P", .petabits, .petabytes),
            ("Ki", .kibibits, .kibibytes), ("Mi", .mebibits, .mebibytes), ("Gi", .gibibits, .gibibytes)
        ]
        for (prefix, bits, bytes) in storage {
            result[prefix + "b"] = bits
            result[prefix + "B"] = bytes
        }
        result["kb"] = UnitInformationStorage.kilobytes
        for (prefix, scale) in [("", 1.0), ("k", 1e3), ("K", 1e3), ("M", 1e6), ("G", 1e9), ("T", 1e12)] {
            result[prefix + "bps"] = DataRateUnit(symbol: prefix + "bps", converter: UnitConverterLinear(coefficient: scale))
            result[prefix + "Bps"] = DataRateUnit(symbol: prefix + "Bps", converter: UnitConverterLinear(coefficient: scale * 8))
        }
        for (prefix, scale) in [("n", 1e-9), ("µ", 1e-6), ("u", 1e-6), ("m", 1e-3), ("", 1.0), ("k", 1e3), ("M", 1e6), ("G", 1e9)] {
            result[prefix + "W"] = UnitPower(symbol: prefix + "W", converter: UnitConverterLinear(coefficient: scale))
            result[prefix + "Hz"] = UnitFrequency(symbol: prefix + "Hz", converter: UnitConverterLinear(coefficient: scale))
        }
        return result
    }()

    public static func unit(for token: String) -> Dimension? {
        if let symbol = symbols[token] { return symbol }
        let key = token.lowercased().replacingOccurrences(of: "°", with: "")
        guard !key.isEmpty else { return nil }
        let legacySymbols: Set<String> = ["kb", "mb", "gb", "tb", "pb", "kib", "mib", "gib", "tib", "pib"]
        if legacySymbols.contains(key), token != key { return nil }
        return table[key]
    }
}

final class DataRateUnit: Dimension, @unchecked Sendable {
    override class func baseUnit() -> Self {
        self.init(symbol: "bps", converter: UnitConverterLinear(coefficient: 1))
    }
}
