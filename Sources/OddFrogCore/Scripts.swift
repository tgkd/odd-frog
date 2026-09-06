import Foundation

public enum ScriptScanner {
    static let headerBytes = 4096

    public static func scan(folders: [URL]) -> [ScriptItem] {
        let fm = FileManager.default
        var seen = Set<String>()
        var items: [ScriptItem] = []
        for folder in folders {
            guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isExecutableKey], options: [.skipsHiddenFiles]) else { continue }
            for url in entries {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
                guard values?.isRegularFile == true else { continue }
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard seen.insert(canonical).inserted else { continue }
                guard let item = parse(url: URL(fileURLWithPath: canonical), executable: values?.isExecutable == true) else { continue }
                items.append(item)
            }
        }
        return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public static func parse(url: URL, executable: Bool) -> ScriptItem? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headerBytes), !data.isEmpty else { return nil }
        guard data.first == UInt8(ascii: "#"), let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(header: text, url: url, executable: executable)
    }

    static func parse(header: String, url: URL, executable: Bool) -> ScriptItem? {
        var fields: [String: String] = [:]
        for line in header.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let body = trimmed.drop { $0 == "#" || $0 == " " }
            guard body.hasPrefix("@raycast.") else { continue }
            let rest = body.dropFirst("@raycast.".count)
            guard let space = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let key = String(rest[..<space])
            let value = rest[space...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        guard executable, header.hasPrefix("#!") else { return nil }
        let title = fields["title"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        let mode = fields["mode"].flatMap(ScriptMode.init(rawValue:)) ?? .silent
        let icon = fields["icon"].flatMap { value -> String? in
            guard let scalar = value.unicodeScalars.first, scalar.properties.isEmojiPresentation || scalar.properties.isEmoji && scalar.value > 0x2000 else { return nil }
            return value
        }
        let argument = fields["argument1"].flatMap(parseArgument)
        return ScriptItem(url: url, title: title, mode: mode, icon: icon, package: fields["packageName"], argument: argument)
    }

    static func parseArgument(_ json: String) -> ScriptArgument? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ScriptArgument(placeholder: "argument", optional: false)
        }
        let placeholder = (object["placeholder"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "argument"
        let optional = object["optional"] as? Bool ?? false
        return ScriptArgument(placeholder: placeholder, optional: optional)
    }
}
