import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

struct PluginTests {
    func temp() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-api2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    /// /usr/bin/python3 is a Command Line Tools shim. With a cold xcrun cache its first launches take
    /// seconds, and the parallel tests would all pay for it inside the 2 s request timeout.
    static let providerTimeout: Duration = .seconds(30)
    private static let pythonWarmUp: Void = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "pass"]
        try? process.run()
        process.waitUntilExit()
    }()
    func fixture(_ root: URL, source: String) throws -> URL {
        Self.pythonWarmUp
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
        let initResult = try await process.request("initialize", timeout: Self.providerTimeout)
        #expect(initResult["apiVersion"] == .number(2))
        for query in ["hello", "error", "again"] {
            let input: JSONValue = .object(["input": .object(["query": .string(query)])])
            if query == "error" { await #expect(throws: RPCError.self) { try await process.request("query", params: input, timeout: Self.providerTimeout) } }
            else { #expect(try await process.request("query", params: input, timeout: Self.providerTimeout).array?.first?["title"].string == query) }
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
        let value = try await process.request("query", timeout: Self.providerTimeout) { capability, params in
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
        let task = Task { try await process.request("query", params: .object(["input": .object(["query": .string("old")])]), timeout: Self.providerTimeout) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await process.request("query", params: .object(["input": .object(["query": .string("new")])]), timeout: Self.providerTimeout).array?.first?["title"] == .string("new"))
        try await Task.sleep(for: .milliseconds(600))
        #expect(try await process.request("initialize", timeout: Self.providerTimeout)["apiVersion"] == .number(2)); await process.stop()
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
        await #expect(throws: RPCError.self) { try await process.request("query", timeout: Self.providerTimeout) }
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
    @Test func actionAfterCallbackRoundTripsAndIsOptional() throws {
        let action = PluginAction(.openPath, "/tmp/a", after: PluginAfter("track", payload: .object(["n": .number(1)])))
        let decoded = try JSONValue.encode(action).decode(PluginAction.self)
        #expect(decoded == action)
        #expect(decoded.after?.callback == "track")
        let plain = try JSONDecoder().decode(PluginAction.self, from: Data(#"{"kind":"openPath","value":"/tmp/a"}"#.utf8))
        #expect(plain.after == nil)
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
    @Test func triggerOverridesReplaceTheManifestTrigger() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyword = PluginPackage(manifest: try manifest(id: "cal", extra: "activation = 'exclusive'\nkeyword = 'cal'"), directory: root, bundled: true)
        let shortened = [PluginSetting(id: "cal", enabled: true, source: keyword.source, trigger: "c")]
        #expect(try keyword.trigger(in: shortened) == .keyword("c"))
        #expect(keyword.query(from: "c month", settings: shortened) == "month")
        #expect(keyword.query(from: "C", settings: shortened) == "")
        #expect(keyword.query(from: "cal month", settings: shortened) == nil)
        #expect(keyword.query(from: "cal month", settings: []) == "month")
        let prefixed = PluginPackage(manifest: try manifest(id: "term", extra: "activation = 'exclusive'\nprefix = '>'"), directory: root, bundled: true)
        let doubled = [PluginSetting(id: "term", enabled: true, source: prefixed.source, trigger: ">>")]
        #expect(try prefixed.trigger(in: doubled) == .prefix(">>"))
        #expect(prefixed.query(from: ">> ls", settings: doubled) == "ls")
        #expect(prefixed.query(from: "> ls", settings: doubled) == nil)
        let live = PluginPackage(manifest: try manifest(id: "live"), directory: root, bundled: true)
        let ignored = [PluginSetting(id: "live", enabled: true, source: live.source, trigger: "x")]
        #expect(try live.trigger(in: ignored) == nil)
        #expect(live.query(from: "x hi", settings: ignored) == "x hi")
        let invalid = [PluginSetting(id: "cal", enabled: true, source: keyword.source, trigger: "Bad Word")]
        #expect(throws: (any Error).self) { try keyword.trigger(in: invalid) }
        #expect(keyword.query(from: "cal month", settings: invalid) == nil)
    }
    @Test func triggerOverridesRoundTripThroughSettings() throws {
        let overridden = Settings(plugins: [PluginSetting(id: "cal", enabled: true, source: "bundled", trigger: "c")])
        let parsed = try Settings.parse(overridden.serialized())
        #expect(parsed == overridden)
        #expect(parsed.plugins.first?.trigger == "c")
        let plain = Settings(plugins: [PluginSetting(id: "cal", enabled: true, source: "bundled")])
        #expect(try Settings.parse(plain.serialized()).plugins.first?.trigger == nil)
    }
    @Test func hotkeysComeFromTheManifestAndCanBeOverriddenOrTurnedOff() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = PluginPackage(manifest: try manifest(id: "clip", extra: "activation = 'exclusive'\nkeyword = 'clip'\nhotkey = 'cmd+shift+v'"),
                                 directory: root, bundled: true)
        #expect(try clip.hotkey(in: [])?.serialized == "cmd+shift+v")
        #expect(try clip.trigger(in: [])?.launchQuery == "clip ")
        let moved = [PluginSetting(id: "clip", enabled: true, source: clip.source, hotkey: "ctrl+alt+c")]
        #expect(try clip.hotkey(in: moved)?.serialized == "ctrl+alt+c")
        let off = [PluginSetting(id: "clip", enabled: true, source: clip.source, hotkey: "")]
        #expect(try clip.hotkey(in: off) == nil)
        let invalid = [PluginSetting(id: "clip", enabled: true, source: clip.source, hotkey: "v")]
        #expect(throws: (any Error).self) { try clip.hotkey(in: invalid) }
        let prefixed = PluginPackage(manifest: try manifest(id: "term", extra: "activation = 'exclusive'\nprefix = '>'"), directory: root, bundled: true)
        #expect(try prefixed.hotkey(in: []) == nil)
        #expect(try prefixed.trigger(in: [])?.launchQuery == ">")
        let added = [PluginSetting(id: "term", enabled: true, source: prefixed.source, hotkey: "cmd+alt+t")]
        #expect(try prefixed.hotkey(in: added)?.serialized == "cmd+alt+t")
        #expect(throws: (any Error).self) { try manifest(id: "live", extra: "hotkey = 'cmd+shift+v'") }
        #expect(throws: (any Error).self) { try manifest(id: "bad", extra: "activation = 'exclusive'\nkeyword = 'bad'\nhotkey = 'hyper+v'") }
        let parsed = try Settings.parse(Settings(plugins: moved).serialized())
        #expect(parsed.plugins.first?.hotkey == "ctrl+alt+c")
    }
    @Test func hotkeyResolutionGivesEachHotkeyToOnePackageAndNamesConflicts() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        func package(_ id: String, _ hotkey: String?) throws -> PluginPackage {
            let line = hotkey.map { "\nhotkey = '\($0)'" } ?? ""
            return PluginPackage(manifest: try manifest(id: id, extra: "activation = 'exclusive'\nkeyword = '\(id)'" + line), directory: root, bundled: true)
        }
        let clip = try package("clip", "cmd+shift+v")
        let notes = try package("notes", "cmd+shift+v")
        let cal = try package("cal", "ctrl+alt+c")
        let plain = try package("plain", nil)
        let launcher = try Hotkey.parse("alt+space")
        let all = PluginHotkeys.resolve(packages: [clip, notes, cal, plain], settings: [], reserved: launcher)
        #expect(all.assigned == ["clip": try Hotkey.parse("cmd+shift+v"), "cal": try Hotkey.parse("ctrl+alt+c")])
        #expect(all.conflicts == ["notes": "Hotkey ⇧⌘V is also used by clip."])
        let stealing = [PluginSetting(id: "cal", enabled: true, source: cal.source, hotkey: "alt+space")]
        let reserved = PluginHotkeys.resolve(packages: [clip, notes, cal], settings: stealing, reserved: launcher)
        #expect(reserved.assigned["cal"] == nil)
        #expect(reserved.conflicts["cal"] == "Hotkey ⌥Space is used by the launcher.")
        let disabled = [PluginSetting(id: "clip", enabled: false, source: clip.source)]
        #expect(PluginHotkeys.resolve(packages: [clip, notes], settings: disabled).assigned == ["notes": try Hotkey.parse("cmd+shift+v")])
        #expect(PluginHotkeys.resolve(packages: [clip, notes], settings: [], failures: ["clip"]).assigned.keys.contains("notes"))
        let broken = [PluginSetting(id: "clip", enabled: true, source: clip.source, hotkey: "v")]
        #expect(PluginHotkeys.resolve(packages: [clip], settings: broken) == PluginHotkeys.Resolution())
    }
    @Test @MainActor func triggerConflictsUseOverrides() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let first = PluginPackage(manifest: try manifest(id: "one", extra: "activation = 'exclusive'\nkeyword = 'one'"), directory: root, bundled: true)
        let second = PluginPackage(manifest: try manifest(id: "two", extra: "activation = 'exclusive'\nkeyword = 'two'"), directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        let overridden = [PluginSetting(id: "two", enabled: true, source: second.source, trigger: "one")]
        coordinator.reload(discovery: PluginDiscovery(packages: [first, second]), settings: overridden)
        #expect(coordinator.failures.count == 2)
        #expect(second.triggerConflict(.keyword("one"), among: [first, second], settings: overridden)?.manifest.id == "one")
        #expect(second.triggerConflict(.keyword("three"), among: [first, second], settings: overridden) == nil)
        let disabled = [PluginSetting(id: "one", enabled: false, source: first.source)]
        #expect(second.triggerConflict(.keyword("one"), among: [first, second], settings: disabled) == nil)
        #expect(throws: (any Error).self) {
            try coordinator.validateSettings([PluginSetting(id: "one", enabled: true, source: first.source, trigger: "Bad Word")])
        }
        let renamed = [PluginSetting(id: "one", enabled: true, source: first.source, trigger: "x")]
        coordinator.reload(discovery: PluginDiscovery(packages: [first]), settings: renamed)
        #expect(coordinator.failures.isEmpty)
        try await waitUntil { coordinator.search("x hi", items: [], weights: [:], maxResults: 8).first?.item.title == "hi" }
    }
    @Test @MainActor func exclusivePluginsAppearAsRootSearchRows() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let clip = PluginPackage(manifest: try manifest(id: "clip", extra: "activation = 'exclusive'\nkeyword = 'clip'\nhotkey = 'cmd+shift+v'"),
                                 directory: root, bundled: true)
        let term = PluginPackage(manifest: try manifest(id: "term", extra: "activation = 'exclusive'\nprefix = '>'"), directory: root, bundled: true)
        let live = PluginPackage(manifest: try manifest(id: "live"), directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        coordinator.reload(discovery: PluginDiscovery(packages: [clip, term, live]), settings: [])
        let rows = coordinator.catalogItems.filter { coordinator.pluginEntry(for: $0) != nil }
        #expect(rows.map(\.id) == ["plugin:clip:host-plugin", "plugin:term:host-plugin"])
        let row = try #require(rows.first)
        #expect(row.title == "clip" && row.subtitle == "clip · ⇧⌘V" && row.kindLabel == "Plugin" && row.aliases == ["clip"])
        #expect(row.result.item.primary == nil && row.result.historyEligible)
        #expect(rows.last?.subtitle == ">")
        #expect(coordinator.pluginEntry(for: row)?.trigger == .keyword("clip"))
        #expect(coordinator.pluginEntries.map(\.package.manifest.id) == ["clip", "term"])
        let items = coordinator.catalogItems
        #expect(coordinator.search("cli", items: items, weights: [:], maxResults: 8).first?.item.id == row.id)
        #expect(SearchEngine.search(query: "clip", items: items, weights: [:], maxResults: 8).first?.exactAlias == true)
        #expect(coordinator.search("", items: items, weights: [row.id: 2], maxResults: 8).map(\.item.id) == [row.id, "plugin:term:host-plugin"])
        #expect(coordinator.search("clip x", items: items, weights: [:], maxResults: 8).allSatisfy { coordinator.pluginEntry(for: $0.item) == nil })
        let renamed = [PluginSetting(id: "clip", enabled: true, source: clip.source, trigger: "cb", hotkey: "")]
        coordinator.reload(discovery: PluginDiscovery(packages: [clip, term]), settings: renamed)
        let moved = try #require(coordinator.catalogItems.first { $0.id == row.id })
        #expect(moved.subtitle == "cb" && moved.aliases == ["cb"])
        coordinator.reload(discovery: PluginDiscovery(packages: [clip, term]), settings: [PluginSetting(id: "clip", enabled: false, source: clip.source)])
        #expect(coordinator.catalogItems.map(\.id) == ["plugin:term:host-plugin"])
        let conflicting = PluginPackage(manifest: try manifest(id: "two", extra: "activation = 'exclusive'\nprefix = '>>'"), directory: root, bundled: true)
        coordinator.reload(discovery: PluginDiscovery(packages: [term, conflicting]), settings: [])
        #expect(coordinator.catalogItems.isEmpty)
    }
    @Test @MainActor func exclusivePluginAddsRootResultsToKeywordlessQueries() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let files = PluginPackage(manifest: try manifest(id: "files", extra: "activation = 'exclusive'\nkeyword = 'f'\nroot_results = 2"),
                                  directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        coordinator.reload(discovery: PluginDiscovery(packages: [files]), settings: [])
        let items = coordinator.catalogItems
        func titles(_ query: String) -> [String] { coordinator.search(query, items: items, weights: [:], maxResults: 8).map(\.item.title) }
        try await waitUntil { titles("hello").contains("hello") }
        // The keyword form stays exclusive: no entry row, only the plugin's own answer.
        try await waitUntil { titles("f hello") == ["hello"] }
        #expect(titles("").contains("files"))
    }
    private func catalogRows(_ count: Int, directory: URL) -> [LauncherItem] {
        (0..<count).map {
            .plugin(PluginResult(pluginID: "cat", item: PluginItem(id: "c\($0)", title: "hello \($0)"), generation: UUID(), catalog: true, directory: directory))
        }
    }
    @Test @MainActor func rootRowsKeepTheirSlotsWhenCatalogMatchesFillTheList() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let files = PluginPackage(manifest: try manifest(id: "files", extra: "activation = 'exclusive'\nkeyword = 'f'\nroot_results = 2"),
                                  directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        coordinator.reload(discovery: PluginDiscovery(packages: [files]), settings: [])
        let items = catalogRows(10, directory: root)
        func titles() -> [String] { coordinator.search("hello", items: items, weights: [:], maxResults: 8).map(\.item.title) }
        try await waitUntil { titles().last == "hello" }
        #expect(titles().count == 8 && titles().filter { $0.hasPrefix("hello ") }.count == 7)
    }
    @Test @MainActor func emptyLauncherKeepsEveryPluginEntryVisibleAmongRecents() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let clip = PluginPackage(manifest: try manifest(id: "clip", extra: "activation = 'exclusive'\nkeyword = 'clip'"), directory: root, bundled: true)
        let term = PluginPackage(manifest: try manifest(id: "term", extra: "activation = 'exclusive'\nprefix = '>'"), directory: root, bundled: true)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        coordinator.reload(discovery: PluginDiscovery(packages: [clip, term]), settings: [])
        let recents = catalogRows(8, directory: root)
        let items = recents + coordinator.catalogItems
        let weights = Dictionary(uniqueKeysWithValues: recents.map { ($0.id, 1.0) })
        let entryIDs = ["plugin:clip:host-plugin", "plugin:term:host-plugin"]
        let shown = coordinator.search("", items: items, weights: weights, maxResults: 8).map(\.item.id)
        #expect(shown.count == 8 && entryIDs.allSatisfy(shown.contains))
        coordinator.showsEntriesWhenEmpty = false
        #expect(coordinator.search("", items: items, weights: weights, maxResults: 8).map(\.item.id) == recents.map(\.id))
    }
    @Test @MainActor func userOverrideChangesOrSilencesRootResults() async throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, source: echo)
        let files = PluginPackage(manifest: try manifest(id: "files", extra: "activation = 'exclusive'\nkeyword = 'f'\nroot_results = 3"),
                                  directory: root, bundled: true)
        let plain = PluginPackage(manifest: try manifest(id: "plain", extra: "activation = 'exclusive'\nkeyword = 'p'"), directory: root, bundled: true)
        func setting(_ package: PluginPackage, _ count: Int?) -> [PluginSetting] {
            [PluginSetting(id: package.manifest.id, enabled: true, source: package.source, rootResults: count)]
        }
        #expect(try files.rootResults(in: []) == 3)
        #expect(try files.rootResults(in: setting(files, 0)) == 0)
        #expect(try files.rootResults(in: setting(files, 7)) == 7)
        #expect(throws: (any Error).self) { try files.rootResults(in: setting(files, 11)) }
        #expect(try plain.rootResults(in: setting(plain, 5)) == 0)
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        defer { coordinator.stop() }
        coordinator.reload(discovery: PluginDiscovery(packages: [files]), settings: setting(files, 0))
        #expect(throws: (any Error).self) { try coordinator.validateSettings(setting(files, -1)) }
        _ = coordinator.search("hello", items: [], weights: [:], maxResults: 8)
        try await Task.sleep(for: .milliseconds(400))
        #expect(coordinator.search("hello", items: [], weights: [:], maxResults: 8).isEmpty)
    }
    @Test func rootResultsOverrideAndLauncherToggleSurviveSettingsRoundTrip() throws {
        let settings = Settings(plugins: [PluginSetting(id: "files", enabled: true, source: "bundled", rootResults: 5)],
                                launcher: .init(showPlugins: false))
        let text = try settings.serialized()
        #expect(text.contains("root_results") && text.contains("show_plugins"))
        let parsed = try Settings.parse(text)
        #expect(parsed.plugins.first?.rootResults == 5 && !parsed.launcher.showPlugins)
        #expect(try Settings.parse("").launcher.showPlugins)
    }
    @Test func rootResultsRequireExclusiveActivationAndASmallCount() throws {
        #expect(throws: (any Error).self) { try manifest(extra: "activation = 'live'\nroot_results = 1") }
        #expect(throws: (any Error).self) { try manifest(extra: "activation = 'exclusive'\nkeyword = 'f'\nroot_results = 11") }
        #expect(try manifest(extra: "activation = 'exclusive'\nkeyword = 'f'\nroot_results = 3").rootResults == 3)
    }
    @Test func queryKeywordIsTheFirstTypedWord() {
        #expect(PluginQuery(query: "", fullQuery: "  CaL  month").keyword == "cal")
        #expect(PluginQuery(query: "", fullQuery: "").keyword == "")
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
    @Test @MainActor func monthViewsNeedOnlyAnIDAndTitle() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = DocumentHandler()
        let package = PluginPackage(manifest: try manifest(extra: """
        activation = "live"
        [[commands]]
        id = "month"
        title = "Month"
        primary = { kind = "callback", value = "month" }
        """), directory: root, bundled: true)
        let discovery = PluginDiscovery(packages: [package])
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins["fixture"] = { handler }
        defer { coordinator.stop() }
        coordinator.reload(discovery: discovery, settings: [], storage: root)
        var outcomes: [Result<PluginEffects, any Error>] = []
        func start() throws {
            let result = try #require(coordinator.catalogItems.first?.result)
            let action = try #require(result.item.primary)
            _ = coordinator.activate(result, action: action, argument: nil) { outcomes.append($0) }
        }
        func month(id: String) -> JSONValue {
            .object(["refreshCatalog": .bool(false), "refreshQuery": .bool(false),
                     "view": .object(["kind": .string("month"), "id": .string(id), "title": .string("Calendar")])])
        }
        await handler.respond(month(id: "month"))
        try start()
        try await waitUntil { outcomes.count == 1 }
        guard case .success(let effects) = outcomes[0] else {
            Issue.record("Expected a month view")
            return
        }
        #expect(effects.view?.kind == .month)
        await handler.respond(month(id: ""))
        try start()
        try await waitUntil { outcomes.count == 2 }
        guard case .failure(let rejected) = outcomes[1] else {
            Issue.record("Expected a month view without an ID to be refused")
            return
        }
        #expect((rejected as? RPCError)?.code == "protocol")
    }
    @Test @MainActor func chatViewsAreValidatedAndDeltasAreRouted() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ChatHandler()
        let package = PluginPackage(manifest: try manifest(extra: """
        activation = "live"
        [[commands]]
        id = "chat"
        title = "Chat"
        primary = { kind = "callback", value = "open" }
        """), directory: root, bundled: true)
        let discovery = PluginDiscovery(packages: [package])
        let coordinator = PluginCoordinator(services: HostServiceRegistry())
        coordinator.builtins["fixture"] = { handler }
        defer { coordinator.stop() }
        coordinator.reload(discovery: discovery, settings: [], storage: root)
        var deltas: [(String, PluginMessageDelta)] = []
        coordinator.onMessageDelta = { pluginID, delta in deltas.append((pluginID, delta)) }
        var outcomes: [Result<PluginEffects, any Error>] = []
        func start() throws {
            let result = try #require(coordinator.catalogItems.first?.result)
            let action = try #require(result.item.primary)
            _ = coordinator.activate(result, action: action, argument: nil, text: "hello") { outcomes.append($0) }
        }
        func chat(_ fields: [String: JSONValue]) -> JSONValue {
            var view: [String: JSONValue] = ["kind": .string("chat"), "id": .string("c1"), "title": .string("Chat")]
            for (key, value) in fields { view[key] = value }
            return .object(["refreshCatalog": .bool(false), "refreshQuery": .bool(false), "view": .object(view)])
        }
        let send = JSONValue.object(["kind": .string("callback"), "value": .string("send")])
        let hello = JSONValue.object(["id": .string("m1"), "role": .string("user"), "text": .string("hello")])
        await handler.respond(chat(["messages": .array([hello])]))
        try start()
        try await waitUntil { outcomes.count == 1 }
        guard case .failure(let missing) = outcomes[0] else { Issue.record("Expected a chat view without send to be refused"); return }
        #expect((missing as? RPCError)?.code == "protocol")
        await handler.respond(chat(["messages": .array([hello, hello]), "send": send]))
        try start()
        try await waitUntil { outcomes.count == 2 }
        guard case .failure(let duplicated) = outcomes[1] else { Issue.record("Expected duplicate message IDs to be refused"); return }
        #expect((duplicated as? RPCError)?.code == "protocol")
        await handler.respond(chat(["messages": .array([hello]), "send": send]))
        try start()
        try await waitUntil { outcomes.count == 3 }
        guard case .success(let effects) = outcomes[2] else { Issue.record("Expected a chat view"); return }
        #expect(effects.view?.kind == .chat)
        #expect(effects.view?.messages == [PluginMessage(id: "m1", role: .user, text: "hello")])
        #expect(effects.view?.send?.value == "send")
        try await waitUntil { deltas.count == 3 }
        #expect(deltas.last?.0 == "fixture")
        #expect(deltas.last?.1 == PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi"))
    }
    @Test func processAcceptsMessageDeltaEvents() async throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let source = """
        import json,sys
        def send(v): print(json.dumps(dict(apiVersion=2,**v)),flush=True)
        for line in sys.stdin:
          r=json.loads(line)
          m=r.get('method')
          if m=='shutdown': break
          if m=='activate':
            send({'method':'messageDelta','params':{'viewID':'c1','messageID':'m2','delta':'Hi'}})
            send({'id':r['id'],'result':{'refreshCatalog':False,'refreshQuery':False}})
          elif m=='bogus':
            send({'method':'bogus','params':{}})
          else:
            send({'id':r['id'],'result':{'apiVersion':2}})
        """
        let log = DeltaLog()
        let process = PluginProcess(executable: try fixture(root, source: source), persistent: true) { method, params in
            await log.record(method, params: params)
        }
        let result = try await process.request("activate", timeout: .seconds(5))
        #expect(result["refreshCatalog"] == .bool(false))
        try await settle { await log.events.count >= 1 }
        #expect(await log.events.first?.method == "messageDelta")
        #expect(await log.events.first?.params["delta"].string == "Hi")
        do {
            _ = try await process.request("bogus", timeout: .seconds(5))
            Issue.record("Expected an unknown provider event to fail the request")
        } catch let error as RPCError {
            #expect(error.message.contains("Unknown provider event."))
        }
        await process.stop()
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

private actor DeltaLog {
    private(set) var events: [(method: String, params: JSONValue)] = []
    func record(_ method: String, params: JSONValue) {
        events.append((method, params))
    }
}

private actor ChatHandler: ProviderHandler {
    private(set) var activations = 0
    private var reply: JSONValue?
    func respond(_ value: JSONValue) { reply = value }
    func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        guard method == "activate" else { return .object(["apiVersion": .number(2)]) }
        activations += 1
        try await operation.emit("messageDelta", params: .encode(PluginMessageDelta(viewID: "c1", messageID: "m2", delta: "Hi")))
        guard let reply else { throw RPCError("test", "No reply configured.") }
        return reply
    }
}
