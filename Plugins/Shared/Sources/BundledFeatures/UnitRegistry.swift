import Foundation
import OddFrogCore

public enum UnitRegistry {
    private static let table: [String: Dimension] = {
        let entries: [(Dimension, [String])] = [
            (UnitLength.millimeters, ["mm", "millimeter", "millimeters"]),
            (UnitLength.centimeters, ["cm", "centimeter", "centimeters"]),
            (UnitLength.meters, ["m", "meter", "meters", "metre", "metres"]),
            (UnitLength.kilometers, ["km", "kilometer", "kilometers", "kilometre", "kilometres"]),
            (UnitLength.inches, ["in", "inch", "inches"]),
            (UnitLength.feet, ["ft", "foot", "feet"]),
            (UnitLength.yards, ["yd", "yard", "yards"]),
            (UnitLength.miles, ["mi", "mile", "miles"]),
            (UnitLength.nauticalMiles, ["nmi", "nauticalmile", "nauticalmiles"]),

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

            (UnitVolume.milliliters, ["ml", "milliliter", "milliliters"]),
            (UnitVolume.liters, ["l", "liter", "liters", "litre", "litres"]),
            (UnitVolume.teaspoons, ["tsp", "teaspoon", "teaspoons"]),
            (UnitVolume.tablespoons, ["tbsp", "tablespoon", "tablespoons"]),
            (UnitVolume.fluidOunces, ["floz"]),
            (UnitVolume.cups, ["cup", "cups"]),
            (UnitVolume.pints, ["pt", "pint", "pints"]),
            (UnitVolume.quarts, ["qt", "quart", "quarts"]),
            (UnitVolume.gallons, ["gal", "gallon", "gallons"]),

            (UnitSpeed.kilometersPerHour, ["kph", "kmh"]),
            (UnitSpeed.milesPerHour, ["mph"]),
            (UnitSpeed.metersPerSecond, ["mps"]),
            (UnitSpeed.knots, ["kn", "knot", "knots"]),

            (UnitArea.squareMeters, ["sqm", "m2"]),
            (UnitArea.squareKilometers, ["sqkm", "km2"]),
            (UnitArea.squareFeet, ["sqft", "ft2"]),
            (UnitArea.squareMiles, ["sqmi", "mi2"]),
            (UnitArea.hectares, ["ha", "hectare", "hectares"]),
            (UnitArea.acres, ["acre", "acres"]),
        ]
        var out: [String: Dimension] = [:]
        for (unit, tokens) in entries {
            for token in tokens { out[token] = unit }
        }
        return out
    }()

    public static func unit(for token: String) -> Dimension? {
        let key = token.lowercased().replacingOccurrences(of: "°", with: "")
        guard !key.isEmpty else { return nil }
        return table[key]
    }
}
