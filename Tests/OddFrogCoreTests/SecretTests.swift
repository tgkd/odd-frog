import Foundation
import Synchronization
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct SecretTests {
    private let helpers = PluginTests()
    private static let secretSettings = """
    activation = "live"
    [[settings]]
    key = "service"
    title = "Service"
    type = "choice"
    choices = ["Local", "Custom"]
    default = "Local"

    [[settings]]
    key = "api_key"
    title = "API key"
    type = "secret"
    default = ""
    visible_when = { service = ["Custom"] }
    """

    @Test func secretDefaultMustBeEmpty() throws {
        #expect(throws: (any Error).self) {
            try helpers.manifest(extra: """
            [[settings]]
            key = "api_key"
            title = "API key"
            type = "secret"
            default = "sk-default"
            """)
        }
        let manifest = try helpers.manifest(extra: Self.secretSettings)
        #expect(manifest.settings.last?.type == .secret)
    }

    @Test func validatedSettingsNeverReturnStoredSecret() throws {
        let manifest = try helpers.manifest(extra: Self.secretSettings)
        let settings = try manifest.validatedSettings(["service": .string("Custom"), "api_key": .string("sk-stored")])
        #expect(settings["api_key"] == .string(""))
        #expect(settings["service"] == .string("Custom"))
    }

    @Test @MainActor func visibleSecretReachesContextAndHiddenSecretIsNotRead() async throws {
        let root = try helpers.temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CountingSecretStore()
        let handler = ContextHandler()
        let package = PluginPackage(manifest: try helpers.manifest(extra: Self.secretSettings), directory: root, bundled: true)
        let reference = SecretReference(package: package, key: "api_key")
        try store.write("sk-live", for: reference)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins["fixture"] = { handler }
        coordinator.secrets = store
        defer { coordinator.stop() }
        let custom = [PluginSetting(id: "fixture", enabled: true, source: package.source, values: ["service": .string("Custom")])]
        coordinator.reload(discovery: PluginDiscovery(packages: [package]), settings: custom, storage: root)
        _ = coordinator.search("first", items: [], weights: [:], maxResults: 8)
        try await helpers.settle { await handler.context("query")?["settings"]["api_key"] == .string("sk-live") }
        #expect(await handler.context("initialize")?["settings"]["api_key"] == .string("sk-live"))
        #expect(store.reads == 1)

        let local = [PluginSetting(id: "fixture", enabled: true, source: package.source, values: ["service": .string("Local")])]
        coordinator.reload(discovery: PluginDiscovery(packages: [package]), settings: local, storage: root)
        await handler.reset()
        let readsBefore = store.reads
        _ = coordinator.search("second", items: [], weights: [:], maxResults: 8)
        try await helpers.settle { await handler.context("query") != nil }
        #expect(await handler.context("query")?["settings"]["api_key"] == .string(""))
        #expect(store.reads == readsBefore)
    }

    @Test @MainActor func secretDidChangeSendsTheNewValue() async throws {
        let root = try helpers.temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CountingSecretStore()
        let handler = ContextHandler()
        let package = PluginPackage(manifest: try helpers.manifest(extra: Self.secretSettings), directory: root, bundled: true)
        let reference = SecretReference(package: package, key: "api_key")
        try store.write("sk-old", for: reference)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins["fixture"] = { handler }
        coordinator.secrets = store
        defer { coordinator.stop() }
        let custom = [PluginSetting(id: "fixture", enabled: true, source: package.source, values: ["service": .string("Custom")])]
        coordinator.reload(discovery: PluginDiscovery(packages: [package]), settings: custom, storage: root)
        _ = coordinator.search("first", items: [], weights: [:], maxResults: 8)
        try await helpers.settle { await handler.context("query")?["settings"]["api_key"] == .string("sk-old") }

        try store.write("sk-new", for: reference)
        _ = coordinator.search("cached", items: [], weights: [:], maxResults: 8)
        try await helpers.settle { await handler.queries.contains("cached") }
        #expect(await handler.context("query")?["settings"]["api_key"] == .string("sk-old"))

        coordinator.secretDidChange(pluginID: "fixture")
        try await helpers.settle { await handler.context("settings")?["settings"]["api_key"] == .string("sk-new") }
        _ = coordinator.search("next", items: [], weights: [:], maxResults: 8)
        try await helpers.settle { await handler.queries.contains("next") }
        #expect(await handler.context("query")?["settings"]["api_key"] == .string("sk-new"))
        coordinator.secretDidChange(pluginID: "unknown")
    }

    @Test @MainActor func failedReadReportsOnceAndPluginKeepsWorking() async throws {
        let root = try helpers.temp(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CountingSecretStore(failing: true)
        let handler = ContextHandler()
        let package = PluginPackage(manifest: try helpers.manifest(extra: Self.secretSettings), directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins["fixture"] = { handler }
        coordinator.secrets = store
        var reports: [(String, String)] = []
        coordinator.onSecretFailure = { reports.append(($0, $1)) }
        defer { coordinator.stop() }
        let custom = [PluginSetting(id: "fixture", enabled: true, source: package.source, values: ["service": .string("Custom")])]
        coordinator.reload(discovery: PluginDiscovery(packages: [package]), settings: custom, storage: root)
        try await helpers.waitUntil { coordinator.search("first", items: [], weights: [:], maxResults: 8).first?.item.title == "first" }
        try await helpers.waitUntil { coordinator.search("again", items: [], weights: [:], maxResults: 8).first?.item.title == "again" }
        #expect(await handler.context("query")?["settings"]["api_key"] == .string(""))
        #expect(reports.count == 1)
        #expect(reports.first?.0 == "fixture")
        #expect(reports.first?.1.contains("API key") == true)
        #expect(reports.first?.1.contains("Settings › Plugins") == true)
        #expect(store.reads == 1)
        #expect(coordinator.failures["fixture"] == nil)
    }

    @Test func extractMovesSecretsOutOfSettings() throws {
        let root = try helpers.temp(); defer { try? FileManager.default.removeItem(at: root) }
        let package = PluginPackage(manifest: try helpers.manifest(extra: Self.secretSettings), directory: root, bundled: false)
        let other = PluginPackage(manifest: try helpers.manifest(id: "other"), directory: root.appendingPathComponent("other"), bundled: false)
        let plain = [PluginSetting(id: "fixture", enabled: true, source: package.source,
                                   values: ["service": .string("Custom"), "api_key": .string("sk-plain")]),
                     PluginSetting(id: "other", enabled: true, source: other.source)]
        let extracted = SecretMigration.extract(from: plain, packages: [package, other])
        #expect(extracted.secrets == [SecretReference(package: package, key: "api_key"): "sk-plain"])
        #expect(extracted.settings[0].values == ["service": .string("Custom")])
        #expect(extracted.settings[1] == plain[1])
        let serialized = try Settings(plugins: extracted.settings).serialized()
        #expect(!serialized.contains("sk-plain"))
        #expect(serialized.contains("Custom"))

        let onlySecret = [PluginSetting(id: "fixture", enabled: true, source: package.source, values: ["api_key": .string("")])]
        let emptied = SecretMigration.extract(from: onlySecret, packages: [package])
        #expect(emptied.secrets.isEmpty)
        #expect(emptied.settings[0].values == nil)

        #expect(SecretMigration.extract(from: extracted.settings, packages: [package, other]).settings == extracted.settings)
    }
}

private final class CountingSecretStore: SecretStore {
    private let values = Mutex<[SecretReference: String]>([:])
    private let readCount = Mutex(0)
    private let failing: Bool
    init(failing: Bool = false) { self.failing = failing }
    var reads: Int { readCount.withLock { $0 } }
    func contains(_ reference: SecretReference) -> Bool { values.withLock { $0[reference] != nil } }
    func read(_ reference: SecretReference) throws -> String? {
        readCount.withLock { $0 += 1 }
        if failing { throw PluginError.message("User interaction is not allowed.") }
        return values.withLock { $0[reference] }
    }
    func write(_ value: String, for reference: SecretReference) throws { values.withLock { $0[reference] = value } }
    func remove(_ reference: SecretReference) throws { values.withLock { $0[reference] = nil } }
}

private actor ContextHandler: ProviderHandler {
    private var contexts: [String: JSONValue] = [:]
    private(set) var queries: [String] = []
    func context(_ method: String) -> JSONValue? { contexts[method] }
    func reset() { contexts = [:]; queries = [] }
    func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        contexts[method] = params["context"]
        switch method {
        case "initialize": return .object(["apiVersion": .number(2)])
        case "query":
            let query = params["input"]["query"].string ?? ""
            queries.append(query)
            return try .encode([PluginItem(id: "answer", title: query)])
        default: return .object([:])
        }
    }
}
