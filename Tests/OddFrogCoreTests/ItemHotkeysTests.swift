import Foundation
import OddFrogCore
import OddFrogPluginAPI
import Testing

struct ItemHotkeysTests {
    private func item(_ id: String, _ title: String) -> LauncherItem {
        .plugin(PluginResult(pluginID: "applications", item: PluginItem(id: id, title: title), catalog: true))
    }

    @Test func hotkeyOverridesRoundTripAndTrim() throws {
        var settings = Settings()
        settings.setOverride(ItemOverride(id: "plugin:applications:/Applications/Safari.app", hotkey: "cmd+shift+s"))
        let parsed = try Settings.parse(settings.serialized())
        #expect(parsed == settings)
        #expect(parsed.items.first?.hotkey == "cmd+shift+s")

        let trimmed = try Settings.parse("""
        [[items]]
        id = "a"
        hotkey = "  ctrl+alt+a "

        [[items]]
        id = "b"
        hotkey = ""
        """)
        #expect(trimmed.items.map(\.hotkey) == ["ctrl+alt+a", nil])
        #expect(ItemOverride(id: "x", hotkey: "cmd+x").isDefault == false)
    }

    @Test func resolutionGivesEachHotkeyToOneItemAndNamesConflicts() throws {
        let safari = item("safari", "Safari")
        let mail = item("mail", "Mail")
        let notes = item("notes", "Notes")
        var settings = Settings()
        settings.setOverride(ItemOverride(id: mail.id, hotkey: "cmd+shift+m"))
        settings.setOverride(ItemOverride(id: notes.id, hotkey: "cmd+shift+m"))
        settings.setOverride(ItemOverride(id: safari.id, hotkey: "alt+space"))
        settings.setOverride(ItemOverride(id: "gone", hotkey: "cmd+shift+g"))
        let launcher = try Hotkey.parse("alt+space")
        let resolution = ItemHotkeys.resolve(items: [safari, mail, notes], settings: settings, reserved: [launcher: "the launcher"])
        #expect(resolution.assigned == [mail.id: try Hotkey.parse("cmd+shift+m")])
        #expect(resolution.conflicts == [
            notes.id: "Hotkey ⇧⌘M is already used by Mail.",
            safari.id: "Hotkey ⌥Space is already used by the launcher.",
        ])

        settings.setOverride(ItemOverride(id: mail.id, enabled: false, hotkey: "cmd+shift+m"))
        let disabled = ItemHotkeys.resolve(items: [safari, mail, notes], settings: settings)
        #expect(disabled.assigned[notes.id] == (try Hotkey.parse("cmd+shift+m")))
        #expect(disabled.assigned[safari.id] == launcher)

        settings.setOverride(ItemOverride(id: notes.id, hotkey: "m"))
        let broken = ItemHotkeys.resolve(items: [notes], settings: settings)
        #expect(broken.assigned.isEmpty)
        #expect(broken.conflicts[notes.id]?.contains("needs at least one modifier") == true)
    }
}

extension ItemHotkeysTests {
    @Test func configHotkeysAreDefaultsThatOverridesReplace() throws {
        let config = try ConfigParser.parse("""
        [[commands]]
        name = "Dev Build"
        path = "~/Developer/odd-frog/build/OddFrog.app"
        hotkey = "ctrl+alt+o"

        [[commands]]
        name = "Plain"
        command = "true"
        hotkey = " "
        """)
        #expect(config.commands[0].hotkey == (try Hotkey.parse("ctrl+alt+o")))
        #expect(config.commands[1].hotkey == nil)
        #expect(throws: (any Error).self) {
            try ConfigParser.parse("[[commands]]\nname = \"X\"\ncommand = \"true\"\nhotkey = \"o\"\n")
        }

        let dev = LauncherItem.plugin(PluginResult(pluginID: "commands", item: PluginItem(id: config.commands[0].stableID, title: "Dev Build"), catalog: true))
        #expect(dev.id == config.commands[0].itemID)
        let defaults = [config.commands[0].itemID: try Hotkey.parse("ctrl+alt+o")]
        let fromConfig = ItemHotkeys.resolve(items: [dev], settings: Settings(), defaults: defaults)
        #expect(fromConfig.assigned == defaults)
        #expect(ItemHotkeys.requests(settings: Settings(), defaults: defaults) == [dev.id: "ctrl+alt+o"])

        var settings = Settings()
        settings.setOverride(ItemOverride(id: dev.id, hotkey: "cmd+shift+o"))
        let overridden = ItemHotkeys.resolve(items: [dev], settings: settings, defaults: defaults)
        #expect(overridden.assigned == [dev.id: try Hotkey.parse("cmd+shift+o")])
        #expect(ItemHotkeys.requests(settings: settings, defaults: defaults) == [dev.id: "cmd+shift+o"])

        settings.setOverride(ItemOverride(id: dev.id, enabled: false))
        #expect(ItemHotkeys.resolve(items: [dev], settings: settings, defaults: defaults) == ItemHotkeys.Resolution())
    }
}

extension ItemHotkeysTests {
    @Test func theCurrentHolderKeepsAHotkeyWhenTheCatalogOrderChanges() throws {
        let mail = item("mail", "Mail")
        let notes = item("notes", "Notes")
        var settings = Settings()
        settings.setOverride(ItemOverride(id: mail.id, hotkey: "cmd+shift+m"))
        settings.setOverride(ItemOverride(id: notes.id, hotkey: "cmd+shift+m"))
        let first = ItemHotkeys.resolve(items: [mail, notes], settings: settings)
        #expect(first.assigned.keys.sorted() == [mail.id])
        let reordered = ItemHotkeys.resolve(items: [notes, mail], holding: [mail.id], settings: settings)
        #expect(reordered.assigned.keys.sorted() == [mail.id])
        #expect(reordered.conflicts == [notes.id: "Hotkey ⇧⌘M is already used by Mail."])
        let fresh = ItemHotkeys.resolve(items: [notes, mail], settings: settings)
        #expect(fresh.assigned.keys.sorted() == [notes.id])
    }

    @Test func linkEditsKeepTheConfigHotkey() throws {
        let text = """
        [[commands]]
        id = "gh"
        name = "GitHub"
        aliases = ["gh"]
        url = "https://github.com"
        hotkey = "ctrl+alt+g"
        """
        let original = try #require(try ConfigParser.parse(text).commands.first)
        let edited = try LinkEditor.updating(text, original: original, draft: LinkDraft(name: "GitHub Issues", url: "https://github.com/issues", aliases: "ghi"))
        let command = try #require(try ConfigParser.parse(edited).commands.first)
        #expect(command.name == "GitHub Issues")
        #expect(command.hotkey == (try Hotkey.parse("ctrl+alt+g")))
    }
}
