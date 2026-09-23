import Foundation
import TOMLKit

public struct GeneralConfig: Sendable, Equatable {
    public var hotkey: Hotkey
    public var shell: String
    public var maxResults: Int

    public init(hotkey: Hotkey = .default, shell: String = "/bin/zsh", maxResults: Int = 8) {
        self.hotkey = hotkey
        self.shell = shell
        self.maxResults = maxResults
    }
}

public struct Config: Sendable, Equatable {
    public var general: GeneralConfig
    public var commands: [CommandItem]

    public init(general: GeneralConfig = GeneralConfig(), commands: [CommandItem] = []) {
        self.general = general
        self.commands = commands
    }

    public static let empty = Config()
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case toml(String)
    case invalidHotkey(String)
    case invalidMaxResults(Int)
    case commandMissingAction(String)
    case commandMultipleActions(String)
    case commandInvalidURL(String, String)
    case commandTerminalWithoutShell(String)
    case duplicateCommandName(String)
    case duplicateAlias(String)
    case emptyName(Int)

    public var description: String {
        switch self {
        case .toml(let message): "TOML error: \(message)"
        case .invalidHotkey(let message): "hotkey: \(message)"
        case .invalidMaxResults(let n): "max_results must be between 1 and 50, got \(n)"
        case .commandMissingAction(let name): "command '\(name)' needs one of command, path, url"
        case .commandMultipleActions(let name): "command '\(name)' has more than one of command, path, url"
        case .commandInvalidURL(let name, let url): "command '\(name)' has an invalid url '\(url)'"
        case .commandTerminalWithoutShell(let name): "command '\(name)' sets terminal = true but has no command"
        case .duplicateCommandName(let name): "duplicate command name '\(name)'"
        case .duplicateAlias(let alias): "duplicate alias '\(alias)'"
        case .emptyName(let index): "command #\(index + 1) has an empty name"
        }
    }
}

struct RawConfig: Decodable {
    var general: RawGeneral?
    var commands: [RawCommand]?
}

struct RawGeneral: Decodable {
    var hotkey: String?
    var shell: String?
    var max_results: Int?
}

struct RawCommand: Decodable {
    var id: String?
    var name: String?
    var aliases: [String]?
    var command: String?
    var path: String?
    var url: String?
    var cwd: String?
    var terminal: Bool?
}

public enum ConfigParser {
    public static func parse(_ text: String) throws -> Config {
        let raw: RawConfig
        do {
            raw = try TOMLDecoder().decode(RawConfig.self, from: text)
        } catch let error as TOMLParseError {
            throw ConfigError.toml("\(error.source.begin.line):\(error.source.begin.column) \(error.description)")
        } catch {
            throw ConfigError.toml(String(describing: error))
        }
        return try build(raw)
    }

    static func build(_ raw: RawConfig) throws -> Config {
        var general = GeneralConfig()
        if let g = raw.general {
            if let text = g.hotkey {
                do { general.hotkey = try Hotkey.parse(text) } catch { throw ConfigError.invalidHotkey(String(describing: error)) }
            }
            if let shell = g.shell, !shell.isEmpty { general.shell = shell }
            if let n = g.max_results {
                guard (1...50).contains(n) else { throw ConfigError.invalidMaxResults(n) }
                general.maxResults = n
            }
        }

        var commands: [CommandItem] = []
        var names = Set<String>()
        var aliases = Set<String>()
        for (index, rc) in (raw.commands ?? []).enumerated() {
            let name = (rc.name ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw ConfigError.emptyName(index) }
            guard names.insert(name.lowercased()).inserted else { throw ConfigError.duplicateCommandName(name) }

            let present = [rc.command, rc.path, rc.url].compactMap { $0 }.count
            guard present > 0 else { throw ConfigError.commandMissingAction(name) }
            guard present == 1 else { throw ConfigError.commandMultipleActions(name) }

            let action: CommandAction
            if let shell = rc.command {
                action = .shell(shell)
            } else if let path = rc.path {
                action = .path(URL(fileURLWithPath: expandTilde(path)))
            } else if let text = rc.url {
                guard let url = URL(string: text), url.scheme != nil else { throw ConfigError.commandInvalidURL(name, text) }
                action = .url(url)
            } else {
                throw ConfigError.commandMissingAction(name)
            }

            let terminal = rc.terminal ?? false
            if terminal, case .shell = action {} else if terminal { throw ConfigError.commandTerminalWithoutShell(name) }

            var cleanAliases: [String] = []
            for alias in rc.aliases ?? [] {
                let trimmed = alias.trimmingCharacters(in: .whitespaces).lowercased()
                guard !trimmed.isEmpty else { continue }
                guard aliases.insert(trimmed).inserted else { throw ConfigError.duplicateAlias(trimmed) }
                cleanAliases.append(trimmed)
            }

            let cwd = rc.cwd.map { URL(fileURLWithPath: expandTilde($0)) }
            commands.append(CommandItem(name: name, aliases: cleanAliases, action: action, cwd: cwd, terminal: terminal, stableID: rc.id))
        }
        guard Set(commands.map(\.stableID)).count == commands.count, commands.allSatisfy({ !$0.stableID.isEmpty }) else { throw ConfigError.toml("Command IDs must be nonempty and unique.") }
        return Config(general: general, commands: commands)
    }

    public static func serialized(_ config: Config) throws -> String {
        struct General: Encodable { var hotkey: String; var shell: String; var max_results: Int }
        struct Entry: Encodable { var id: String; var name: String; var aliases: [String]; var command: String?; var path: String?; var url: String?; var cwd: String?; var terminal: Bool }
        struct Document: Encodable { var general: General; var commands: [Entry] }
        let commands = config.commands.map { command in
            var entry = Entry(id: command.stableID, name: command.name, aliases: command.aliases, cwd: command.cwd?.path, terminal: command.terminal)
            switch command.action {
            case .shell(let text): entry.command = text
            case .path(let url): entry.path = url.path
            case .url(let url): entry.url = URLTemplate.display(url)
            }
            return entry
        }
        return try TOMLEncoder().encode(Document(general: General(hotkey: config.general.hotkey.serialized, shell: config.general.shell, max_results: config.general.maxResults), commands: commands))
    }

    public static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

public enum ConfigLoader {
    public static var defaultDirectory: URL { legacyDirectory.appendingPathComponent("v2", isDirectory: true) }

    public static var legacyDirectory: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("odd-frog", isDirectory: true)
    }

    public static var defaultPath: URL {
        defaultDirectory.appendingPathComponent("config.toml")
    }

    public static func load(from url: URL) throws -> (config: Config, contents: Data) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw ConfigError.toml("file is not UTF-8") }
        return (try ConfigParser.parse(text), data)
    }

    public static func replacingHotkey(in text: String, with hotkey: String) -> String {
        let line = "hotkey = \"\(hotkey)\""
        var lines = text.components(separatedBy: "\n")
        var inGeneral = false
        var generalHeader: Int?
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inGeneral = trimmed.hasPrefix("[general]")
                if inGeneral { generalHeader = index }
                continue
            }
            guard inGeneral, trimmed.hasPrefix("hotkey") else { continue }
            let afterKey = trimmed.dropFirst("hotkey".count).trimmingCharacters(in: .whitespaces)
            guard afterKey.hasPrefix("=") else { continue }
            let comment = raw.range(of: "#").map { String(raw[$0.lowerBound...]) }
            lines[index] = comment.map { "\(line)  \($0)" } ?? line
            return lines.joined(separator: "\n")
        }
        if let generalHeader {
            lines.insert(line, at: generalHeader + 1)
            return lines.joined(separator: "\n")
        }
        let prefix = "[general]\n\(line)\n"
        return text.isEmpty ? prefix : prefix + "\n" + text
    }

    @discardableResult
    public static func ensureExists(at url: URL, template: URL?) throws -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return false }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let template, fm.fileExists(atPath: template.path) {
            try fm.copyItem(at: template, to: url)
        } else {
            try Data("[general]\nhotkey = \"alt+space\"\n".utf8).write(to: url)
        }
        return true
    }
}
