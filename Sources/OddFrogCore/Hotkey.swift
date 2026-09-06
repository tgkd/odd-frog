import Foundation

public struct Hotkey: Sendable, Hashable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let description: String

    public static let cmdKey: UInt32 = 1 << 8
    public static let shiftKey: UInt32 = 1 << 9
    public static let optionKey: UInt32 = 1 << 11
    public static let controlKey: UInt32 = 1 << 12

    public static let `default` = try! Hotkey.parse("alt+space")

    public init(keyCode: UInt32, modifiers: UInt32, description: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.description = description
    }

    public init?(keyCode: UInt32, modifiers: UInt32) {
        guard modifiers != 0, let name = Hotkey.keyName(for: keyCode) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, description: Hotkey.symbolic(modifiers: modifiers, keyName: name))
    }

    public var serialized: String {
        var parts: [String] = []
        if modifiers & Self.cmdKey != 0 { parts.append("cmd") }
        if modifiers & Self.controlKey != 0 { parts.append("ctrl") }
        if modifiers & Self.optionKey != 0 { parts.append("alt") }
        if modifiers & Self.shiftKey != 0 { parts.append("shift") }
        parts.append(Hotkey.keyName(for: keyCode) ?? "space")
        return parts.joined(separator: "+")
    }

    public static func keyName(for keyCode: UInt32) -> String? {
        let preferred = ["space", "enter", "tab", "esc", "delete"]
        let names = keyCodes.filter { $0.value == keyCode }.map(\.key)
        return preferred.first { names.contains($0) } ?? names.sorted().first
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case unknownModifier(String)
        case unknownKey(String)
        case noModifier

        public var description: String {
            switch self {
            case .empty: "hotkey is empty"
            case .unknownModifier(let m): "unknown modifier '\(m)'"
            case .unknownKey(let k): "unknown key '\(k)'"
            case .noModifier: "hotkey needs at least one modifier"
            }
        }
    }

    public static func parse(_ text: String) throws -> Hotkey {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty else { throw ParseError.empty }
        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘": modifiers |= cmdKey
            case "alt", "option", "opt", "⌥": modifiers |= optionKey
            case "ctrl", "control", "⌃": modifiers |= controlKey
            case "shift", "⇧": modifiers |= shiftKey
            default: throw ParseError.unknownModifier(modifier)
            }
        }
        guard modifiers != 0 else { throw ParseError.noModifier }
        guard let keyCode = keyCodes[keyName] else { throw ParseError.unknownKey(keyName) }
        return Hotkey(keyCode: keyCode, modifiers: modifiers, description: symbolic(modifiers: modifiers, keyName: keyName))
    }

    private static func symbolic(modifiers: UInt32, keyName: String) -> String {
        var out = ""
        if modifiers & controlKey != 0 { out += "⌃" }
        if modifiers & optionKey != 0 { out += "⌥" }
        if modifiers & shiftKey != 0 { out += "⇧" }
        if modifiers & cmdKey != 0 { out += "⌘" }
        switch keyName {
        case "space": out += "Space"
        case "return", "enter": out += "↩"
        case "tab": out += "⇥"
        case "escape", "esc": out += "⎋"
        default: out += keyName.uppercased()
        }
        return out
    }

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103,
        "f13": 105, "f14": 107, "f10": 109, "f12": 111, "f15": 113, "f4": 118, "f2": 120, "f1": 122,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
