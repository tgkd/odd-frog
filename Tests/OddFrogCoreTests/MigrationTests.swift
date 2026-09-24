import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct MigrationTests {
    private func roots() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-migration-\(UUID().uuidString)")
        let config = root.appendingPathComponent("config"), support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return (root, config, support)
    }
    private let legacy = """
    [general]
    hotkey = "cmd+shift+space"
    terminal = "terminal"
    max_results = 12
    [[commands]]
    name = "Docs"
    aliases = ["docs"]
    url = "https://example.com/?q={query}"
    [[commands]]
    name = "Build"
    command = "make test"
    """
    @Test func populatedMigrationPreservesHistoryAliasesSettingsAndStableLinkIDs() throws {
        let (root, config, support) = try roots(); defer { try? FileManager.default.removeItem(at: root) }
        try Data(legacy.utf8).write(to: config.appendingPathComponent("config.toml"))
        var settings = Settings(scripts: .init(folders: ["/tmp/scripts"], watch: false), currency: .init(enabled: false), window: .init(enabled: true, cascadeStep: 40))
        settings.setOverride(ItemOverride(id: "command:Docs", enabled: false, aliases: ["documentation"]))
        settings.setOverride(ItemOverride(id: "/Applications/Safari.app", aliases: ["saf"]))
        _ = try SettingsLoader.save(settings, to: config.appendingPathComponent("settings.toml"))
        let entry = FrecencyEntry(weight: 4, lastUsed: Date(timeIntervalSince1970: 1_700_000_000))
        let history = FrecencyTable(entries: ["command:Docs": entry, "script:/tmp/scripts/test.sh": entry, "window:maximize": entry, "/Applications/Safari.app": entry])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: support.appendingPathComponent("frecency.json"))
        let cache = Data("{\"base\":\"USD\",\"timestamp\":\"2026-09-01T00:00:00Z\",\"rates\":{\"USD\":1,\"EUR\":0.9}}".utf8)
        try cache.write(to: support.appendingPathComponent("rates.json"))
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let packages = PluginDiscovery.scan(bundled: repository.appendingPathComponent("Plugins"), user: root.appendingPathComponent("none")).packages
        #expect(packages.count == 12)
        try V2Migration.migrate(configRoot: config, supportRoot: support, packages: packages)
        let v2 = config.appendingPathComponent("v2")
        let result = try ConfigLoader.load(from: v2.appendingPathComponent("config.toml")).config
        #expect(result.general.maxResults == 12)
        let id = result.commands[0].stableID
        let migrated = try SettingsLoader.load(from: v2.appendingPathComponent("settings.toml")).settings
        #expect(migrated.override(for: "plugin:commands:" + id)?.aliases == ["documentation"])
        #expect(migrated.override(for: "plugin:commands:" + id)?.enabled == false)
        #expect(migrated.plugins.first { $0.id == "scripts" }?.values?["watch"] == .bool(false))
        #expect(migrated.plugins.first { $0.id == "calculator" }?.values?["currency"] == .bool(false))
        #expect(migrated.plugins.first { $0.id == "windows" }?.enabled == true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let mapped = try decoder.decode(FrecencyTable.self, from: Data(contentsOf: support.appendingPathComponent("v2/frecency.json")))
        #expect(mapped.entries["plugin:commands:" + id] == entry)
        #expect(mapped.entries["plugin:scripts:/tmp/scripts/test.sh"] == entry)
        #expect(mapped.entries["plugin:windows:maximize"] == entry)
        #expect(mapped.entries["plugin:applications:/Applications/Safari.app"] == entry)
        #expect(try Data(contentsOf: support.appendingPathComponent("v2/plugins/calculator/rates.json")) == cache)
        #expect(try String(contentsOf: config.appendingPathComponent("config.toml"), encoding: .utf8) == legacy)
        let renamed = try LinkEditor.save(to: v2.appendingPathComponent("config.toml"), original: result.commands[0], draft: LinkDraft(name: "New Docs", url: "https://example.com/new", aliases: "new"))
        #expect(renamed.config.commands[0].stableID == id)
        let revision = try LinkService.read(from: v2.appendingPathComponent("config.toml"))["revision"]
        _ = try LinkService.write(.object(["revision": revision, "id": .string(id), "name": .string("Docs again"), "url": .string("https://example.com")]), to: v2.appendingPathComponent("config.toml"))
        #expect(throws: RPCError.self) { try LinkService.write(.object(["revision": revision, "id": .string(id), "delete": .bool(true)]), to: v2.appendingPathComponent("config.toml")) }
    }
    @Test func malformedInputsDoNotActivateAndCanBeRetried() throws {
        for file in ["config.toml", "settings.toml", "frecency.json", "rates.json"] {
            let (root, config, support) = try roots(); defer { try? FileManager.default.removeItem(at: root) }
            let url = (file.hasSuffix("toml") ? config : support).appendingPathComponent(file)
            try Data("invalid [ {".utf8).write(to: url)
            #expect(throws: (any Error).self) { try V2Migration.migrate(configRoot: config, supportRoot: support) }
            #expect(!FileManager.default.fileExists(atPath: config.appendingPathComponent("v2").path))
            try FileManager.default.removeItem(at: url)
            try V2Migration.migrate(configRoot: config, supportRoot: support)
            #expect(FileManager.default.fileExists(atPath: config.appendingPathComponent("v2/migration-complete").path))
        }
    }
    @Test func interruptedStagesAndExistingCompletedV2AreHandled() throws {
        let (root, config, support) = try roots(); defer { try? FileManager.default.removeItem(at: root) }
        for url in [config.appendingPathComponent(".v2-migration"), support.appendingPathComponent("v2")] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try Data().write(to: support.appendingPathComponent("v2/migration-owned"))
        try V2Migration.migrate(configRoot: config, supportRoot: support)
        let committed = try Data(contentsOf: config.appendingPathComponent("v2/config.toml"))
        try Data("broken [".utf8).write(to: config.appendingPathComponent("config.toml"))
        try V2Migration.migrate(configRoot: config, supportRoot: support)
        #expect(try Data(contentsOf: config.appendingPathComponent("v2/config.toml")) == committed)
    }
    @Test func unownedExistingV2IsNeverOverwritten() throws {
        let (root, config, support) = try roots(); defer { try? FileManager.default.removeItem(at: root) }
        let v2 = config.appendingPathComponent("v2")
        try FileManager.default.createDirectory(at: v2, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: v2.appendingPathComponent("config.toml"))
        #expect(throws: (any Error).self) { try V2Migration.migrate(configRoot: config, supportRoot: support) }
        #expect(try String(contentsOf: v2.appendingPathComponent("config.toml"), encoding: .utf8) == "keep")
    }
}
