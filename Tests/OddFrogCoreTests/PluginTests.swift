import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct PluginTests {
    func temp() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-api2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func fixture(_ root: URL, source: String) throws -> URL {
        let url = root.appendingPathComponent("provider")
        try ("#!/usr/bin/python3\n" + source + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path); return url
    }
    func manifest(id: String = "fixture", mode: String = "persistent", extra: String = "activation = \"live\"") throws -> PluginManifest {
        try PluginManifest.parse("""
        id = "\(id)"
        name = "\(id)"
        version = "2.0.0"
        api_version = 2
        mode = "\(mode)"
        executable = "provider"
        \(extra)
        """)
    }
    private var echo: String { """
    import json,sys,os,time,threading
    lock=threading.Lock()
    def send(v):
      with lock: print(json.dumps(dict(apiVersion=2,**v)),flush=True)
    def run(r):
      m=r['method']; p=r.get('params',{}); q=p.get('input',{}).get('query','')
      if m=='initialize': result={'apiVersion':2}
      elif m=='catalog': result=[{'id':'catalog','title':'Catalog Item','history':True,'aliases':['2+2'],'primary':{'kind':'callback','value':'do'}}]
      elif m=='activate': result={'notification':p['input'].get('argument','done'),'refreshCatalog':False,'refreshQuery':False}
      else:
        if q=='old': time.sleep(.5)
        if q=='empty': result=[]
        elif q=='error': send({'id':r['id'],'error':{'code':'query','message':'Try another query'}}); return
        else: result=[{'id':'answer','title':q or 'answer','history':True,'primary':{'kind':'copy','value':'ok'}}]
      send({'id':r['id'],'result':result})
    for line in sys.stdin:
      r=json.loads(line)
      if r.get('method')=='shutdown': break
      if 'id' in r: threading.Thread(target=run,args=(r,),daemon=True).start()
    """ }
    @Test func manifestsValidateSettingsAndRetainIncompatiblePackages() throws {
        let m = try manifest(extra: """
        [[settings]]
        key = "count"
        title = "Count"
        type = "number"
        default = 2
        minimum = 1
        maximum = 5
        """)
        #expect(try m.validatedSettings([:])["count"] == .number(2))
        #expect(throws: (any Error).self) { try m.validatedSettings(["count": .number(0)]) }
        #expect(throws: (any Error).self) { try m.validatedSettings(["count": .string("bad")]) }
        #expect(throws: (any Error).self) { try manifest(extra: "activation = \"exclusive\"") }
        let old = try PluginManifest.parse("id='old'\nname='Old'\nversion='1'\napi_version=1\nexecutable='old'\nkeyword='old'")
        #expect(old.apiVersion == 1)
    }
    @Test func enablementIsBoundToActualSource() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let m = try manifest()
        let bundled = PluginPackage(manifest: m, directory: root.appendingPathComponent("bundled"), bundled: true)
        let user = PluginPackage(manifest: m, directory: root.appendingPathComponent("user"), bundled: false)
        #expect(bundled.isEnabled(settings: [])); #expect(!user.isEnabled(settings: []))
        #expect(!user.isEnabled(settings: [PluginSetting(id: m.id, enabled: true, source: bundled.source)]))
        #expect(user.isEnabled(settings: [PluginSetting(id: m.id, enabled: true, source: user.source)]))
        let settings = Settings(plugins: [PluginSetting(id: m.id, enabled: true, source: user.source, values: ["text": .string("hi")])])
        #expect(try Settings.parse(settings.serialized()) == settings)
    }
    @Test(arguments: [false, true]) func bothRuntimesExchangeCallbacksAndRecoverableErrors(persistent: Bool) async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let process = PluginProcess(executable: try fixture(root, source: echo), persistent: persistent)
        let initResult = try await process.request("initialize")
        #expect(initResult["apiVersion"] == .number(2))
        for query in ["hello", "error", "again"] {
            let input: JSONValue = .object(["input": .object(["query": .string(query)])])
            if query == "error" { await #expect(throws: RPCError.self) { try await process.request("query", params: input) } }
            else { #expect(try await process.request("query", params: input).array?.first?["title"].string == query) }
        }
        let effects = try await process.request("activate", params: .object(["input": .object(["argument": .string("callback argument")])]), timeout: nil)
        #expect(effects["notification"] == .string("callback argument"))
        await process.stop()
    }
    @Test(arguments: [false, true]) func correlatedServicesWorkInBothRuntimes(persistent: Bool) async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let source = """
        import json,sys
        r=json.loads(sys.stdin.readline())
        print(json.dumps({'apiVersion':2,'id':'service','method':'host.service','params':{'requestID':r['id'],'capability':'fixture.read@1','params':{'value':'from plugin'}}}),flush=True)
        reply=json.loads(sys.stdin.readline())
        print(json.dumps({'apiVersion':2,'id':r['id'],'result':reply['result']}),flush=True)
        for line in sys.stdin: pass
        """
        let process = PluginProcess(executable: try fixture(root, source: source), persistent: persistent)
        let value = try await process.request("query") { capability, params in
            #expect(capability == "fixture.read@1"); return params["value"]
        }
        #expect(value == .string("from plugin")); await process.stop()
    }
    @Test func malformedOversizedCrashTimeoutAndCancellation() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        for source in ["print('bad',flush=True)", "print('x'*(4*1024*1024+1),flush=True)", "import sys; sys.exit(7)", "import time; time.sleep(30)", "print('{\"apiVersion\":2,\"id\":\"wrong\",\"result\":[]}',flush=True)"] {
            let process = PluginProcess(executable: try fixture(root, source: source), persistent: true)
            await #expect(throws: RPCError.self) { try await process.request("query", timeout: .milliseconds(200)) }
            // Protocol failures are latched until a fresh runtime is created by Reload.
            await #expect(throws: RPCError.self) { try await process.request("query") }; await process.stop()
        }
        let process = PluginProcess(executable: try fixture(root, source: echo), persistent: true)
        let task = Task { try await process.request("query", params: .object(["input": .object(["query": .string("old")])])) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await process.request("query", params: .object(["input": .object(["query": .string("new")])])).array?.first?["title"] == .string("new"))
        try await Task.sleep(for: .milliseconds(600))
        #expect(try await process.request("initialize")["apiVersion"] == .number(2)); await process.stop()
    }
    @Test func stopKillsDescendantsAfterLeaderExit() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let source = """
        import subprocess,os,time
        child=subprocess.Popen(['/bin/sleep','30'])
        open('child.pid','w').write(str(child.pid))
        time.sleep(.1)
        os._exit(0)
        """
        let process = PluginProcess(executable: try fixture(root, source: source), persistent: true)
        await #expect(throws: RPCError.self) { try await process.request("query") }
        let pid = try #require(Int32(String(contentsOf: root.appendingPathComponent("child.pid"), encoding: .utf8)))
        await process.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(kill(pid, 0) != 0)
    }
    @Test @MainActor func registryEnforcesDeclarationAndUserActivation() async throws {
        let registry = HostServiceRegistry()
        registry.register("write@1", activationRequired: true) { _, _ in .bool(true) }
        let passive = HostServiceRegistry.Context(pluginID: "fixture", generation: UUID(), activated: false)
        await #expect(throws: RPCError.self) { try await registry.invoke("write@1", params: .null, context: passive, declared: ["write@1"]) }
        let active = HostServiceRegistry.Context(pluginID: "fixture", generation: UUID(), activated: true)
        await #expect(throws: RPCError.self) { try await registry.invoke("write@1", params: .null, context: active, declared: []) }
        #expect(try await registry.invoke("write@1", params: .null, context: active, declared: ["write@1"]) == .bool(true))
    }
    @Test @MainActor func coordinatorCatalogLiveFallbackGenerationsAndDisable() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let package = PluginPackage(manifest: try manifest(extra: "catalog = true\nactivation = 'live'"), directory: root, bundled: true)
        let fallback = PluginPackage(manifest: try manifest(id: "fallback", extra: "activation = 'fallback'"), directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        let discovery = PluginDiscovery(packages: [package, fallback])
        coordinator.reload(discovery: discovery, settings: [], storage: root)
        defer { coordinator.stop() }
        try await waitUntil { coordinator.catalogItems.count == 1 }
        let catalog = try #require(coordinator.catalogItems.first)
        #expect(catalog.aliases == ["2+2"])
        let cached = coordinator.search("2+2", items: coordinator.catalogItems, weights: [:], maxResults: 8)
        #expect(cached.first?.item.title == "Catalog Item")
        try await waitUntil { coordinator.search("2+2", items: coordinator.catalogItems, weights: [:], maxResults: 8).count == 2 }
        let merged = coordinator.search("2+2", items: coordinator.catalogItems, weights: [:], maxResults: 8)
        #expect(merged.map(\.item.title) == ["2+2", "Catalog Item"])
        guard case .plugin(let live) = merged[0].item, case .plugin(let saved) = merged[1].item else { Issue.record("Expected plugin rows"); return }
        #expect(!live.historyEligible); #expect(saved.historyEligible)
        _ = coordinator.search("old", items: [], weights: [:], maxResults: 8)
        try await Task.sleep(for: .milliseconds(150))
        _ = coordinator.search("new", items: [], weights: [:], maxResults: 8)
        try await waitUntil { coordinator.search("new", items: [], weights: [:], maxResults: 8).first?.item.title == "new" }
        try await Task.sleep(for: .milliseconds(600))
        #expect(coordinator.search("new", items: [], weights: [:], maxResults: 8).first?.item.title == "new")
        coordinator.cancel(); #expect(coordinator.catalogItems.count == 1)
        coordinator.reload(discovery: discovery, settings: [PluginSetting(id: "fixture", enabled: false, source: package.source)], storage: root)
        #expect(coordinator.catalogItems.isEmpty)
        #expect(throws: (any Error).self) { try coordinator.authorize(saved, action: saved.item.primary!) }
        #expect(coordinator.search("web", items: [], weights: [:], maxResults: 8).isEmpty)
        try await waitUntil { coordinator.search("web", items: [], weights: [:], maxResults: 8).first?.item.title == "web" }
    }
    @Test func blockedProviderInputStillHonorsDeadline() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let process = PluginProcess(executable: try fixture(root, source: "import time; time.sleep(30)"), persistent: true)
        let before = ContinuousClock.now
        await #expect(throws: RPCError.self) {
            try await process.request("query", params: .string(String(repeating: "x", count: 2 * 1024 * 1024)), timeout: .milliseconds(200))
        }
        #expect(before.duration(to: .now) < .seconds(3))
        await process.stop()
    }
    @Test @MainActor func subscriptionsAreRemovedAndRevokedOnReload() async throws {
        let registry = HostServiceRegistry()
        let generation = UUID()
        let context = HostServiceRegistry.Context(pluginID: "fixture", generation: generation, activated: false)
        var invalidations = 0
        registry.onInvalidation = { _ in invalidations += 1 }
        registry.subscribe(context, to: "changes@1")
        registry.subscribe(context, to: "changes@1")
        #expect(registry.subscriptionCount == 1)
        registry.invalidate("changes@1"); #expect(invalidations == 1)
        registry.cancelSubscriptions(generation: generation)
        registry.subscribe(context, to: "changes@1")
        registry.invalidate("changes@1")
        #expect(registry.subscriptionCount == 0); #expect(invalidations == 1)
    }
    @Test @MainActor func exclusiveTriggersSuppressCatalogsAndConflictsAreVisible() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let first = PluginPackage(manifest: try manifest(id: "one", extra: "activation = 'exclusive'\nprefix = '>'"), directory: root, bundled: true)
        let conflicting = PluginPackage(manifest: try manifest(id: "two", extra: "activation = 'exclusive'\nprefix = '>>'"), directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        coordinator.reload(discovery: PluginDiscovery(packages: [first, conflicting]), settings: [])
        #expect(coordinator.failures.count == 2)
        #expect(coordinator.search(">value", items: [], weights: [:], maxResults: 8).first?.item.title.contains("conflicts") == true)
        coordinator.reload(discovery: PluginDiscovery(packages: [first]), settings: [])
        let cached = LauncherItem.plugin(PluginResult(pluginID: "other", item: PluginItem(id: "match", title: ">value", history: true), catalog: true))
        _ = coordinator.search(">value", items: [cached], weights: [:], maxResults: 8)
        try await waitUntil { coordinator.search(">value", items: [cached], weights: [:], maxResults: 8).first?.item.title == "value" }
        #expect(coordinator.search(">value", items: [cached], weights: [:], maxResults: 8).count == 1)
    }
    @Test func bundledPreferencesSurviveMovingTheAppButNeverApproveUserReplacements() throws {
        let m = try manifest()
        let bundled = PluginPackage(manifest: m, directory: URL(fileURLWithPath: "/Applications/OddFrog.app/Contents/Resources/Plugins/fixture"), bundled: true)
        let values: [String: JSONValue] = ["count": .number(2)]
        let previous = PluginSetting(id: "fixture", enabled: false, source: "bundled:/old/app/fixture", values: values)
        #expect(!bundled.isEnabled(settings: [previous]))
        #expect(bundled.setting(in: [previous])?.values == values)
        let user = PluginPackage(manifest: m, directory: URL(fileURLWithPath: "/tmp/fixture"), bundled: false)
        #expect(!user.isEnabled(settings: [PluginSetting(id: "fixture", enabled: true, source: bundled.source)]))
    }
    @Test func publishedEnvelopeFixturesRoundTrip() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repository.appendingPathComponent("docs/api2/exchanges.ndjson"), encoding: .utf8)
        for line in text.split(separator: "\n") {
            let envelope = try PluginProtocol.decoder().decode(PluginEnvelope.self, from: Data(line.utf8))
            try envelope.validate()
            let copy = try PluginProtocol.decoder().decode(PluginEnvelope.self, from: PluginProtocol.encoder().encode(envelope))
            #expect(copy.result == envelope.result)
        }
    }
    @Test @MainActor func activateAlwaysCompletes() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = DocumentHandler()
        let package = PluginPackage(manifest: try manifest(extra: """
        activation = "live"
        [[commands]]
        id = "doc"
        title = "Doc"
        primary = { kind = "callback", value = "open" }
        """), directory: root, bundled: true)
        let discovery = PluginDiscovery(packages: [package])
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins["fixture"] = { handler }
        defer { coordinator.stop() }
        coordinator.reload(discovery: discovery, settings: [], storage: root)
        var outcomes: [Result<PluginEffects, any Error>] = []
        func start(text: String? = nil) throws {
            let result = try #require(coordinator.catalogItems.first?.result)
            let action = try #require(result.item.primary)
            _ = coordinator.activate(result, action: action, argument: nil, text: text) { outcomes.append($0) }
        }
        func view(save: JSONValue) -> JSONValue {
            .object(["refreshCatalog": .bool(false), "refreshQuery": .bool(false),
                     "view": .object(["kind": .string("editor"), "id": .string("n1"), "title": .string("T"),
                                      "text": .string("x"), "save": save])])
        }
        try start()
        try await settle { await handler.activations == 1 }
        coordinator.cancelActions()
        try await waitUntil { outcomes.count == 1 }
        #expect(throws: CancellationError.self) { try outcomes[0].get() }
        await handler.respond(view(save: .object(["kind": .string("openURL"), "value": .string("https://x")])))
        try start()
        try await waitUntil { outcomes.count == 2 }
        guard case .failure(let rejected) = outcomes[1] else { Issue.record("Expected an invalid view to be refused"); return }
        #expect((rejected as? RPCError)?.code == "protocol")
        await handler.respond(view(save: .object(["kind": .string("callback"), "value": .string("save")])))
        try start(text: "body")
        try await waitUntil { outcomes.count == 3 }
        guard case .success(let effects) = outcomes[2] else { Issue.record("Expected a document view"); return }
        #expect(effects.view?.id == "n1")
        #expect(effects.view?.text == "x")
        let input = await handler.input
        #expect(input["text"].string == "body")
        await handler.stall()
        try start()
        try await settle { await handler.activations == 4 }
        coordinator.reload(discovery: discovery, settings: [PluginSetting(id: "fixture", enabled: false, source: package.source)], storage: root)
        try await waitUntil { outcomes.count == 4 }
        guard case .failure(let stale) = outcomes[3] else { Issue.record("Expected a superseded failure"); return }
        #expect(stale is PluginError)
        #expect(String(describing: stale) == "This result belongs to a disabled or superseded plugin. Search again.")
    }
    func settle(_ condition: @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await !condition() {
            guard ContinuousClock.now < deadline else { throw RPCError("test", "Condition timed out.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    @MainActor func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RPCError("test", "Condition timed out.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor DocumentHandler: ProviderHandler {
    private(set) var activations = 0
    private(set) var input: JSONValue = .null
    private var reply: JSONValue?
    func respond(_ value: JSONValue) { reply = value }
    func stall() { reply = nil }
    func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        guard method == "activate" else { return .object(["apiVersion": .number(2)]) }
        activations += 1
        input = params["input"]
        guard let reply else {
            try await Task.sleep(for: .seconds(5))
            throw RPCError("test", "A stalled activation was never cancelled.")
        }
        return reply
    }
}
