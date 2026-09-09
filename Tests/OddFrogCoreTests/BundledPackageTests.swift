import Foundation
import CryptoKit
import Testing
import OddFrogPluginAPI
import OddFrogHostServicesAPI
import OddFrogBuiltins
@testable import OddFrogCore

@MainActor struct BundledPackageTests {
    private var repository: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var products: URL {
        if let path = ProcessInfo.processInfo.environment["ODD_FROG_TEST_PRODUCTS"] { return URL(fileURLWithPath: path) }
        return repository.appendingPathComponent(".build/debug")
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RPCError("test", "Timed out waiting for provider result.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func installBundled(to root: URL) throws -> [PluginPackage] {
        let packages = PluginDiscovery.scan(bundled: repository.appendingPathComponent("Plugins"), user: root.appendingPathComponent("absent")).packages
        return try packages.map { package in
            let folder = root.appendingPathComponent(package.manifest.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: package.directory.appendingPathComponent("plugin.toml"), to: folder.appendingPathComponent("plugin.toml"))
            return PluginPackage(manifest: package.manifest, directory: folder, bundled: true)
        }
    }
    private func registry() -> HostServiceRegistry {
        let services = HostServiceRegistry()
        for id in ["calendar.access@1", "reminders.access@1", "reminders.complete@1", "reminders.create@1", "windows.perform@1", "links.manage@1", "links.read@1", "links.write@1"] {
            services.register(id, activationRequired: true) { _, _ in throw RPCError("test", "Unexpected user activation during query.") }
        }
        services.register("calendar.read@1") { _, _ in try .encode(CalendarSnapshot(access: .notDetermined)) }
        services.register("reminders.read@1") { _, _ in try .encode(RemindersSnapshot(access: .notDetermined)) }
        return services
    }
    @Test func shippedFeaturesRunInProcessAndEachCanBeDisabled() async throws {
        let root = try PluginTests().temp(); defer { try? FileManager.default.removeItem(at: root) }
        let packages = try installBundled(to: root)
        #expect(packages.count == 9)
        let config = root.appendingPathComponent("config.toml")
        try Data("[[commands]]\nname='Docs'\nurl='https://example.com'\n".utf8).write(to: config)
        let script = root.appendingPathComponent("sample.sh")
        try Data("#!/bin/sh\n# @raycast.title Sample Script\nprintf sample\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let queries = ["applications": "Safari", "commands": "Docs", "scripts": "Sample Script", "calculator": "2+2", "windows": "maximize", "web": "a web query", "terminal": "> uptime", "calendar": "cal", "reminders": "rem"]
        for package in packages {
            let coordinator = PluginCoordinator(services: registry())
            coordinator.builtins = BuiltinProviders.factories
            var values: [String: JSONValue] = [:]
            if package.manifest.id == "calculator" { values["currency"] = .bool(false) }
            if package.manifest.id == "scripts" { values["folders"] = .array([.string(root.path)]) }
            let setting = PluginSetting(id: package.manifest.id, enabled: true, source: package.source, values: values.isEmpty ? nil : values)
            let discovery = PluginDiscovery(packages: [package])
            coordinator.reload(discovery: discovery, settings: [setting], storage: root, config: config)
            let query = queries[package.manifest.id]!
            if package.manifest.catalog { try await wait { !coordinator.catalogItems.isEmpty || !coordinator.failures.isEmpty } }
            var rows = coordinator.search(query, items: coordinator.catalogItems, weights: [:], maxResults: 8)
            try await wait {
                rows = coordinator.search(query, items: coordinator.catalogItems, weights: [:], maxResults: 8)
                return rows.contains { $0.item.result.item.primary != nil } || !coordinator.failures.isEmpty
            }
            #expect(coordinator.failures.isEmpty, "\(package.manifest.id): \(coordinator.failures)")
            #expect(!rows.isEmpty)
            if package.manifest.id == "calculator" { #expect(rows.first?.item.title == "4") }
            if package.manifest.id == "terminal" { #expect(rows.first?.item.result.item.primary?.value == "uptime") }
            coordinator.reload(discovery: discovery, settings: [PluginSetting(id: package.manifest.id, enabled: false, source: package.source)], storage: root, config: config)
            #expect(coordinator.catalogItems.isEmpty)
            #expect(coordinator.search(query, items: [], weights: [:], maxResults: 8).isEmpty)
            coordinator.stop()
        }
    }
    @Test func independentPythonSettingsCallbackAndCalculatorReplacementLeaveHostUnchanged() async throws {
        let root = try PluginTests().temp(); defer { try? FileManager.default.removeItem(at: root) }
        let host = products.appendingPathComponent("OddFrog")
        let hash = SHA256.hash(data: try Data(contentsOf: host))
        let user = root.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let folder = user.appendingPathComponent("counter")
        try FileManager.default.copyItem(at: repository.appendingPathComponent("examples/plugins/counter"), to: folder)
        let discovery = PluginDiscovery.scan(bundled: nil, user: user)
        let package = try #require(discovery.packages.first)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins = BuiltinProviders.factories
        defer { coordinator.stop() }
        var setting = PluginSetting(id: package.manifest.id, enabled: true, source: package.source, values: ["label": .string("My Counter"), "step": .number(3)])
        coordinator.reload(discovery: discovery, settings: [setting], storage: root)
        try await wait { coordinator.catalogItems.first?.title == "My Counter" }
        let item = try #require(coordinator.catalogItems.first?.result)
        var effect: PluginEffects?
        _ = coordinator.activate(item, action: item.item.primary!, argument: "note") { result in
            switch result { case .success(let value): effect = value; case .failure(let error): Issue.record("\(error)") }
        }
        try await wait { effect != nil }
        #expect(effect?.notification == "3 note")
        try await wait { coordinator.catalogItems.first?.subtitle == "3" }
        setting.values?["label"] = .string("Updated Counter")
        try coordinator.updateSettings([setting])
        try await wait { coordinator.catalogItems.first?.title == "Updated Counter" }
        let invalid = PluginSetting(id: package.manifest.id, enabled: true, source: package.source, values: ["step": .number(-1)])
        #expect(throws: (any Error).self) { try coordinator.updateSettings([invalid]) }
        #expect(coordinator.settings == [setting])
        coordinator.stop()
        let shipped = try installBundled(to: root.appendingPathComponent("bundled"))
        let replacement = user.appendingPathComponent("calculator")
        try FileManager.default.copyItem(at: repository.appendingPathComponent("examples/plugins/one-shot"), to: replacement)
        var text = try String(contentsOf: replacement.appendingPathComponent("plugin.toml"), encoding: .utf8)
        text = text.replacingOccurrences(of: "example.echo", with: "calculator").replacingOccurrences(of: "activation = \"exclusive\"\nkeyword = \"echo\"", with: "activation = \"live\"")
        try text.write(to: replacement.appendingPathComponent("plugin.toml"), atomically: true, encoding: .utf8)
        let merged = PluginDiscovery.scan(bundled: root.appendingPathComponent("bundled"), user: user)
        let replaced = try #require(merged.packages.first { $0.manifest.id == "calculator" })
        #expect(!replaced.bundled)
        let oldApproval = PluginSetting(id: "calculator", enabled: true, source: shipped.first { $0.manifest.id == "calculator" }!.source)
        #expect(!replaced.isEnabled(settings: [oldApproval]))
        coordinator.reload(discovery: PluginDiscovery(packages: [replaced]), settings: [PluginSetting(id: "calculator", enabled: true, source: replaced.source)], storage: root)
        _ = coordinator.search("2+2", items: [], weights: [:], maxResults: 8)
        try await wait { coordinator.search("2+2", items: [], weights: [:], maxResults: 8).first?.item.title == "2+2" }
        #expect(coordinator.failures.isEmpty, "\(coordinator.failures)")
        #expect(SHA256.hash(data: try Data(contentsOf: host)) == hash)
    }
}
