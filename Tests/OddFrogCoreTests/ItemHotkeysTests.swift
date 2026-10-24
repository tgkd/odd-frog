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
        #expect(try parsed.items.first?.parsedHotkey() == Hotkey.parse("cmd+shift+s"))

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
        #expect(throws: (any Error).self) { try ItemOverride(id: "x", hotkey: "x").parsedHotkey() }
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
        #expect(fromConfig.requested == [dev.id: "ctrl+alt+o"])

        var settings = Settings()
        settings.setOverride(ItemOverride(id: dev.id, hotkey: "cmd+shift+o"))
        let overridden = ItemHotkeys.resolve(items: [dev], settings: settings, defaults: defaults)
        #expect(overridden.assigned == [dev.id: try Hotkey.parse("cmd+shift+o")])
        #expect(overridden.requested == [dev.id: "cmd+shift+o"])

        settings.setOverride(ItemOverride(id: dev.id, enabled: false))
        #expect(ItemHotkeys.resolve(items: [dev], settings: settings, defaults: defaults) == ItemHotkeys.Resolution())
    }
}

extension ItemHotkeysTests {
    @Test func retainedItemsKeepTheirHotkeyWhileTheCatalogRefills() throws {
        var settings = Settings()
        settings.setOverride(ItemOverride(id: "plugin:applications:/Applications/Mail.app", hotkey: "cmd+shift+m"))
        settings.setOverride(ItemOverride(id: "plugin:applications:/Applications/Notes.app", hotkey: "cmd+shift+m"))
        let retained = ["plugin:applications:/Applications/Mail.app": "Mail"]
        let empty = ItemHotkeys.resolve(items: [], retaining: retained, settings: settings)
        #expect(empty.assigned == ["plugin:applications:/Applications/Mail.app": try Hotkey.parse("cmd+shift+m")])
        let notes = item("/Applications/Notes.app", "Notes")
        let refilled = ItemHotkeys.resolve(items: [notes], retaining: retained, settings: settings)
        #expect(refilled.assigned[notes.id] == nil)
        #expect(refilled.conflicts[notes.id] == "Hotkey ⇧⌘M is already used by Mail.")
        #expect(ItemHotkeys.resolve(items: [], retaining: [:], settings: settings) == ItemHotkeys.Resolution())
    }
}
