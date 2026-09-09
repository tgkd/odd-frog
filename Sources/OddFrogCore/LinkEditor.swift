import Foundation
import TOMLKit

public struct LinkDraft: Sendable {
    public var name: String
    public var url: String
    public var aliases: String

    public init(name: String, url: String, aliases: String) {
        self.name = name
        self.url = url
        self.aliases = aliases
    }

    public func command() throws -> CommandItem {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LinkEditError.message("Enter a name for this link.") }
        guard !address.contains(where: { $0.isWhitespace }),
              let url = URL(string: address), let scheme = url.scheme, !scheme.isEmpty else {
            throw LinkEditError.message("Enter a full URL, such as https://github.com or obsidian://open.")
        }
        if ["http", "https"].contains(scheme.lowercased()), url.host?.isEmpty != false {
            throw LinkEditError.message("Web URLs need a host, such as https://github.com.")
        }
        var seen = Set<String>()
        let aliases = aliases.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty && seen.insert($0).inserted }
        return CommandItem(name: name, aliases: aliases, action: .url(url), cwd: nil, terminal: false)
    }
}

public enum LinkEditError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

public enum LinkEditor {
    // Change only the selected [[commands]] block. Other commands, comments, and
    // hand-edited settings stay byte-for-byte intact.
    public static func updating(_ text: String, original: CommandItem?, draft: LinkDraft?) throws -> String {
        let config = try ConfigParser.parse(text)
        var replacement = try draft?.command()
        if let original { replacement?.stableID = original.stableID }
        var commands = config.commands
        var index: Int?
        if let original {
            guard case .url = original.action else { throw LinkEditError.message("Only URL commands can be changed here.") }
            guard let found = commands.firstIndex(where: { $0.id == original.id }), commands[found] == original else {
                throw LinkEditError.message("This link changed outside this window. Reopen Manage Links and try again.")
            }
            index = found
            if let replacement { commands[found] = replacement } else { commands.remove(at: found) }
        } else if let replacement {
            commands.append(replacement)
        } else {
            return text
        }

        let block = try replacement.map { try serialized($0) } ?? ""
        let updated: String
        if let index {
            let ranges = try commandRanges(in: text)
            guard ranges.count == config.commands.count else {
                throw LinkEditError.message("This config uses an unsupported command layout. Use [[commands]] sections to edit links here.")
            }
            var copy = text
            copy.replaceSubrange(ranges[index], with: block)
            updated = copy
        } else {
            updated = text + (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + "\n" + block
        }
        // Validate the entire result, including duplicate names/aliases and preservation
        // of every unrelated command, before allowing it to reach disk.
        let parsed = try ConfigParser.parse(updated)
        guard parsed == Config(general: config.general, commands: commands) else {
            throw LinkEditError.message("Could not safely update this config layout. No changes were saved.")
        }
        return updated
    }

    @discardableResult
    public static func save(to url: URL, original: CommandItem?, draft: LinkDraft?) throws -> (config: Config, contents: Data) {
        let loaded = try ConfigLoader.load(from: url)
        let text = String(decoding: loaded.contents, as: UTF8.self)
        let updated = try updating(text, original: original, draft: draft)
        let config = try ConfigParser.parse(updated)
        let data = Data(updated.utf8)
        guard try Data(contentsOf: url) == loaded.contents else {
            throw LinkEditError.message("The config changed while saving. Please try again.")
        }
        try data.write(to: url, options: .atomic)
        return (config, data)
    }

    private static func serialized(_ command: CommandItem) throws -> String {
        struct Entry: Encodable {
            let id: String
            let name: String
            let aliases: [String]
            let url: String
        }
        guard case .url(let url) = command.action else { return "" }
        let value = Entry(id: command.stableID, name: command.name, aliases: command.aliases, url: URLTemplate.display(url))
        return "[[commands]]\n" + (try TOMLEncoder().encode(value)) + "\n\n"
    }

    private static func commandRanges(in text: String) throws -> [Range<String.Index>] {
        let header = try NSRegularExpression(pattern: #"^\s*\[\s*\[\s*(?:commands|"commands"|'commands')\s*\]\s*\]\s*(?:#.*)?$"#)
        var ranges: [Range<String.Index>] = []
        var commandStart: String.Index?
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[start..<end])
            // Parsing the prefix distinguishes real headers from header-shaped lines
            // inside multiline shell strings without inventing another TOML parser.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("["),
               (try? TOMLTable(string: String(text[..<start]))) != nil {
                if let commandStart { ranges.append(commandStart..<start) }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                commandStart = header.firstMatch(in: line, range: range) != nil ? start : nil
            }
            start = end == text.endIndex ? end : text.index(after: end)
        }
        if let commandStart { ranges.append(commandStart..<text.endIndex) }
        return ranges
    }
}
