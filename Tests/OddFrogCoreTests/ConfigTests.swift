import Foundation
import Testing
@testable import OddFrogCore

struct ConfigTests {
    @Test func parsesExample() throws {
        let text = """
        [general]
        hotkey = "cmd+shift+k"
        terminal = "iterm"
        max_results = 5

        [[commands]]
        name = "Build"
        aliases = ["build", " B "]
        command = "make"
        cwd = "~/Projects"

        [[commands]]
        name = "Repos"
        path = "~/Projects"

        [[commands]]
        name = "Site"
        url = "https://example.com"
        """
        let config = try ConfigParser.parse(text)
        #expect(config.general.hotkey.keyCode == 40)
        #expect(config.general.hotkey.modifiers == Hotkey.cmdKey | Hotkey.shiftKey)
        #expect(config.general.terminal == .iterm)
        #expect(config.general.maxResults == 5)
        #expect(config.commands.count == 3)
        #expect(config.commands[0].aliases == ["build", "b"])
        #expect(config.commands[0].cwd?.path == NSHomeDirectory() + "/Projects")
        #expect(config.commands[1].action == .path(URL(fileURLWithPath: NSHomeDirectory() + "/Projects")))
        #expect(config.commands[2].action == .url(URL(string: "https://example.com")!))
    }

    @Test func defaultsWhenEmpty() throws {
        let config = try ConfigParser.parse("")
        #expect(config.general == GeneralConfig())
        #expect(config.commands.isEmpty)
    }

    @Test func rejectsMissingAction() {
        #expect(throws: ConfigError.commandMissingAction("X")) {
            try ConfigParser.parse("[[commands]]\nname = \"X\"\n")
        }
    }

    @Test func rejectsMultipleActions() {
        #expect(throws: ConfigError.commandMultipleActions("X")) {
            try ConfigParser.parse("[[commands]]\nname = \"X\"\ncommand = \"a\"\nurl = \"https://b\"\n")
        }
    }

    @Test func rejectsDuplicateAlias() {
        let text = """
        [[commands]]
        name = "A"
        aliases = ["x"]
        command = "a"
        [[commands]]
        name = "B"
        aliases = ["X"]
        command = "b"
        """
        #expect(throws: ConfigError.duplicateAlias("x")) { try ConfigParser.parse(text) }
    }

    @Test func rejectsTerminalWithoutCommand() {
        #expect(throws: ConfigError.commandTerminalWithoutShell("X")) {
            try ConfigParser.parse("[[commands]]\nname = \"X\"\npath = \"/tmp\"\nterminal = true\n")
        }
    }

    @Test func rejectsBadHotkey() {
        #expect(throws: ConfigError.self) { try ConfigParser.parse("[general]\nhotkey = \"space\"\n") }
        #expect(throws: ConfigError.self) { try ConfigParser.parse("[general]\nhotkey = \"hyper+space\"\n") }
    }

    @Test func reportsTOMLSyntaxErrors() {
        #expect(throws: ConfigError.self) { try ConfigParser.parse("[general\nhotkey = 1") }
    }

    @Test func hotkeySerializationRoundTrips() throws {
        for text in ["cmd+shift+space", "ctrl+alt+k", "alt+f5", "cmd+enter"] {
            let h = try Hotkey.parse(text)
            #expect(h.serialized == text)
            let rebuilt = Hotkey(keyCode: h.keyCode, modifiers: h.modifiers)
            #expect(rebuilt == h)
        }
        #expect(Hotkey(keyCode: 49, modifiers: 0) == nil)
    }

    @Test func replacingHotkeyKeepsTheRestOfTheFile() throws {
        let original = """
        # my config
        [general]
        hotkey = "alt+space"   # main
        shell = "/bin/zsh"

        [[commands]]
        name = "X"
        command = "true"
        """
        let updated = ConfigLoader.replacingHotkey(in: original, with: "cmd+shift+space")
        #expect(updated.contains("hotkey = \"cmd+shift+space\"  # main"))
        #expect(!updated.contains("alt+space"))
        #expect(updated.contains("# my config"))
        #expect(updated.contains("name = \"X\""))
        #expect(try ConfigParser.parse(updated).general.hotkey.serialized == "cmd+shift+space")

        let noHotkey = "[general]\nshell = \"/bin/sh\"\n"
        #expect(ConfigLoader.replacingHotkey(in: noHotkey, with: "ctrl+k") == "[general]\nhotkey = \"ctrl+k\"\nshell = \"/bin/sh\"\n")

        let noGeneral = "[[commands]]\nname = \"X\"\ncommand = \"true\"\n"
        let withGeneral = ConfigLoader.replacingHotkey(in: noGeneral, with: "ctrl+k")
        #expect(withGeneral.hasPrefix("[general]\nhotkey = \"ctrl+k\"\n"))
        #expect(try ConfigParser.parse(withGeneral).commands.count == 1)
        #expect(ConfigLoader.replacingHotkey(in: "", with: "ctrl+k") == "[general]\nhotkey = \"ctrl+k\"\n")
    }

    @Test func hotkeyParsing() throws {
        let h = try Hotkey.parse("Ctrl+Alt+Space")
        #expect(h.keyCode == 49)
        #expect(h.modifiers == Hotkey.controlKey | Hotkey.optionKey)
        #expect(h.description == "⌃⌥Space")
        #expect(try Hotkey.parse("cmd+f12").keyCode == 111)
    }
}
