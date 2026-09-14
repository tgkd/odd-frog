import Foundation

public struct ResolvedZone: Sendable, Hashable {
    public let timeZone: TimeZone
    public let label: String

    public init(timeZone: TimeZone, label: String) {
        self.timeZone = timeZone
        self.label = label
    }
}

public enum TimeZoneResolver {
    static let fixedOffsets: [String: Int] = [
        "utc": 0, "gmt": 0, "z": 0,
        "est": -5 * 3600, "edt": -4 * 3600,
        "cst": -6 * 3600, "cdt": -5 * 3600,
        "mst": -7 * 3600, "mdt": -6 * 3600,
        "pst": -8 * 3600, "pdt": -7 * 3600,
        "cet": 1 * 3600, "cest": 2 * 3600,
        "eet": 2 * 3600, "eest": 3 * 3600,
        "msk": 3 * 3600,
        "hkt": 8 * 3600, "sgt": 8 * 3600,
        "jst": 9 * 3600, "kst": 9 * 3600,
        "aest": 10 * 3600, "aedt": 11 * 3600,
    ]

    static let aliases: [String: String] = [
        "et": "America/New_York", "ct": "America/Chicago", "mt": "America/Denver", "pt": "America/Los_Angeles",
        "nyc": "America/New_York",
        "sf": "America/Los_Angeles", "san_francisco": "America/Los_Angeles", "california": "America/Los_Angeles",
        "uk": "Europe/London",
        "india": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata", "new_delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
        "japan": "Asia/Tokyo",
        "china": "Asia/Shanghai", "beijing": "Asia/Shanghai",
        "korea": "Asia/Seoul",
        "germany": "Europe/Berlin",
        "france": "Europe/Paris",
        "israel": "Asia/Jerusalem",
        "ireland": "Europe/Dublin",
    ]

    static let identifiers: [String: String] = Dictionary(
        TimeZone.knownTimeZoneIdentifiers.filter { !$0.hasPrefix("Etc/") }.map { ($0.lowercased(), $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static let suffixes = suffixIndex(TimeZone.knownTimeZoneIdentifiers)

    static func suffixIndex(_ identifiers: [String]) -> [String: Set<String>] {
        var index: [String: Set<String>] = [:]
        for identifier in identifiers where !identifier.hasPrefix("Etc/") {
            let parts = identifier.split(separator: "/")
            guard parts.count > 1, let last = parts.last else { continue }
            index[last.lowercased(), default: []].insert(identifier)
        }
        return index
    }

    public static func zone(named name: String) -> ResolvedZone? {
        zone(named: name, suffixes: suffixes)
    }

    static func zone(named name: String, suffixes: [String: Set<String>]) -> ResolvedZone? {
        let key = name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "_")
        if let seconds = fixedOffsets[key], let timeZone = TimeZone(secondsFromGMT: seconds) {
            return ResolvedZone(timeZone: timeZone, label: seconds == 0 ? "UTC" : key.uppercased())
        }
        guard let identifier = identifiers[key] ?? aliases[key] ?? unique(suffixes[key]),
              let timeZone = TimeZone(identifier: identifier) else { return nil }
        return named(timeZone)
    }

    public static func zone(offsetSign sign: Int, hours: Int, minutes: Int) -> ResolvedZone? {
        guard (0...14).contains(hours), (0...59).contains(minutes), hours * 60 + minutes <= 14 * 60 else { return nil }
        let seconds = sign * (hours * 3600 + minutes * 60)
        guard let timeZone = TimeZone(secondsFromGMT: seconds) else { return nil }
        return ResolvedZone(timeZone: timeZone, label: offsetLabel(seconds))
    }

    public static func named(_ timeZone: TimeZone) -> ResolvedZone {
        let city = timeZone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        return ResolvedZone(timeZone: timeZone, label: city ?? timeZone.identifier)
    }

    static func offsetLabel(_ seconds: Int) -> String {
        guard seconds != 0 else { return "UTC" }
        let magnitude = abs(seconds)
        let sign = seconds < 0 ? "-" : "+"
        let hours = magnitude / 3600
        let minutes = magnitude % 3600 / 60
        guard minutes != 0 else { return "UTC\(sign)\(hours)" }
        return "UTC\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    private static func unique(_ matches: Set<String>?) -> String? {
        guard let matches, matches.count == 1 else { return nil }
        return matches.first
    }
}
