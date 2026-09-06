import Foundation
import Testing
@testable import OddFrogCore

struct LinkEditorTests {
    private let config = """
    # Keep this comment and custom settings.
    [general]
    hotkey = "cmd+shift+space"
    shell = "/bin/zsh"

    [[commands]]
    name = "Build"
    aliases = ["b"]
    command = "make test"
    terminal = true
    cwd = "~/Projects"

    [[commands]]
    name = "GitHub"
    aliases = ["gh"]
    url = "https://github.com"

    [extra]
    note = "untouched"
    """

    @Test func addEditDeletePreservesOtherConfig() throws {
        let initial = try ConfigParser.parse(config)
        let added = try LinkEditor.updating(config, original: nil, draft: LinkDraft(
            name: " Notes ", url: "obsidian://open?vault=Work", aliases: " N, notes, n "
        ))
        #expect(added.hasPrefix(config))
        let notes = try #require(try ConfigParser.parse(added).commands.last)
        #expect(notes.name == "Notes")
        #expect(notes.aliases == ["n", "notes"])
        let edited = try LinkEditor.updating(added, original: initial.commands[1], draft: LinkDraft(
            name: "GitHub Issues", url: "https://github.com/issues?q=is%3Aopen", aliases: "ghi"
        ))
        let parsed = try ConfigParser.parse(edited)
        #expect(parsed.general == initial.general)
        #expect(parsed.commands[0] == initial.commands[0])
        #expect(parsed.commands[1].name == "GitHub Issues")
        #expect(parsed.commands[1].aliases == ["ghi"])
        #expect(edited.contains("[extra]\nnote = \"untouched\""))
        #expect(edited.hasPrefix(String(config.prefix(through: config.range(of: "[[commands]]")!.lowerBound))))
        let deleted = try LinkEditor.updating(edited, original: parsed.commands[1], draft: nil)
        #expect(try ConfigParser.parse(deleted).commands == [initial.commands[0], notes])
        #expect(deleted.contains("# Keep this comment and custom settings."))
    }

    @Test func validatesBeforeWriting() throws {
        for address in ["github.com", "https://", "https:///path", "https://git hub.com", ""] {
            #expect(throws: LinkEditError.self) {
                try LinkDraft(name: "Test", url: address, aliases: "").command()
            }
        }
        #expect(throws: LinkEditError.self) { try LinkDraft(name: "  ", url: "https://example.com", aliases: "").command() }
        #expect(throws: ConfigError.duplicateAlias("b")) {
            try LinkEditor.updating(config, original: nil, draft: LinkDraft(name: "Another", url: "https://example.com", aliases: "B"))
        }
        #expect(throws: ConfigError.duplicateCommandName("github")) {
            try LinkEditor.updating(config, original: nil, draft: LinkDraft(name: "github", url: "https://example.com", aliases: ""))
        }
    }

    @Test func preservesMultilineShellStringsAndQuotedHeaders() throws {
        let text = #"""
        [[commands]]
        name = "Shell"
        command = '''echo hello
        [[commands]]
        name = "not a real entry"
        '''

        [[ "commands" ]] # real link
        name = "Link"
        url = "https://example.com"

        [general]
        hotkey = "alt+space"
        """#
        let original = try ConfigParser.parse(text)
        let changed = try LinkEditor.updating(text, original: original.commands[1], draft: LinkDraft(
            name: "Quoted \"name\"", url: "things:///show?id=today", aliases: "today"
        ))
        let parsed = try ConfigParser.parse(changed)
        #expect(parsed.commands[0] == original.commands[0])
        #expect(parsed.commands[1].name == "Quoted \"name\"")
        #expect(parsed.general == original.general)
        let removed = try LinkEditor.updating(changed, original: parsed.commands[1], draft: nil)
        #expect(try ConfigParser.parse(removed).commands == [original.commands[0]])
    }

    @Test func saveRoundTripAndStaleEditProtection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.toml")
        try Data(config.utf8).write(to: file)
        let original = try ConfigParser.parse(config).commands[1]
        let saved = try LinkEditor.save(to: file, original: original, draft: LinkDraft(
            name: "GitHub", url: "https://github.com/pulls", aliases: "pr"
        ))
        #expect(try Data(contentsOf: file) == saved.contents)
        #expect(try ConfigLoader.load(from: file).config == saved.config)
        #expect(throws: LinkEditError.self) { try LinkEditor.save(to: file, original: original, draft: nil) }
        #expect(try Data(contentsOf: file) == saved.contents)
        #expect(throws: ConfigError.self) {
            try LinkEditor.save(to: file, original: nil, draft: LinkDraft(name: "Build", url: "https://example.com", aliases: ""))
        }
        #expect(try Data(contentsOf: file) == saved.contents)
    }
}
