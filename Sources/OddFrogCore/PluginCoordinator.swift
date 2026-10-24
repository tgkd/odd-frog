import Foundation
import OddFrogPluginAPI

@MainActor public final class PluginCoordinator {
    public typealias BuiltinProviderFactory = @Sendable () -> any ProviderHandler
    public var builtins: [String: BuiltinProviderFactory] = [:]
    public private(set) var packages: [PluginPackage] = []
    public private(set) var discoveryErrors: [String] = []
    public private(set) var failures: [String: String] = [:]
    public private(set) var settings: [PluginSetting] = []
    public private(set) var catalogs: [String: [PluginResult]] = [:]
    public var onChange: (() -> Void)?
    public var onMessageDelta: ((String, PluginMessageDelta) -> Void)?
    public let services: HostServiceRegistry
    private var generation = UUID()
    private var queryGeneration = UUID()
    private var processes: [String: any ProviderTransport] = [:]
    private var initialization: [String: Task<Void, any Error>] = [:]
    private var catalogDirty = Set<String>()
    private var settingsTasks: [String: Task<Void, Never>] = [:]
    private var catalogTasks: [String: Task<Void, Never>] = [:]
    private var actionTasks: [UUID: Task<Void, Never>] = [:]
    private var queryTask: Task<Void, Never>?
    private var currentQuery: String?
    private var currentLimit = 8
    private var live: [String: [PluginResult]] = [:]
    private var queryErrors: [String: String] = [:]
    private var completed = Set<String>()
    private var contexts: [String: PluginContext] = [:]
    public init(services: HostServiceRegistry) {
        self.services = services
        services.onInvalidation = { [weak self] context in
            guard let self, context.generation == generation else { return }
            invalidate()
        }
    }
    public var catalogItems: [LauncherItem] { packages.flatMap { catalogs[$0.manifest.id] ?? [] }.map(LauncherItem.plugin) }
    private var enabled: [PluginPackage] { packages.filter { $0.isEnabled(settings: settings) && failures[$0.manifest.id] == nil } }
    public func reload(discovery: PluginDiscovery, settings: [PluginSetting], storage: URL? = nil, config: URL? = nil) {
        stop()
        packages = discovery.packages.sorted { a, b in a.manifest.order == b.manifest.order ? a.manifest.id < b.manifest.id : a.manifest.order < b.manifest.order }; discoveryErrors = discovery.errors; self.settings = settings; failures = [:]
        let selected = packages.filter { $0.isEnabled(settings: settings) }
        let exclusives = selected.filter { $0.manifest.activation == .exclusive }
        for (index, a) in exclusives.enumerated() {
            guard let trigger = try? a.trigger(in: settings) else {
                continue
            }
            for b in exclusives.dropFirst(index + 1) {
                guard let other = try? b.trigger(in: settings), trigger.conflicts(with: other) else {
                    continue
                }
                failures[a.manifest.id] = "Exclusive trigger conflicts with \(b.manifest.name)."
                failures[b.manifest.id] = "Exclusive trigger conflicts with \(a.manifest.name)."
            }
        }
        for package in packages {
            let m = package.manifest, id = m.id
            if m.apiVersion != PluginProtocol.version { failures[id] = "Unsupported plugin API \(m.apiVersion). Upgrade this package to API 2."; continue }
            let missing = Set(m.capabilities).subtracting(services.capabilities)
            if !missing.isEmpty { failures[id] = "Unsupported capabilities: \(missing.sorted().joined(separator: ", "))."; continue }
            if m.mode != .declarative && !(package.bundled && builtins[id] != nil) {
                if package.bundled && m.executable == nil {
                    failures[id] = "No built-in provider for \(id)."
                    continue
                }
                if m.executable == nil || !FileManager.default.isExecutableFile(atPath: package.executable.path) {
                    failures[id] = "Missing or non-executable provider: \(m.executable ?? "")."
                    continue
                }
            }
            do {
                _ = try package.trigger(in: settings)
                _ = try package.hotkey(in: settings)
                let values = package.setting(in: settings)?.values ?? [:]
                contexts[id] = PluginContext(settings: try m.validatedSettings(values),
                                             storagePath: (storage ?? StoragePaths.support).appendingPathComponent("plugins/\(id)").path,
                                             configPath: (config ?? ConfigLoader.defaultPath).path)
                try validateItems(m.commands, package: package)
            } catch { failures[id] = String(describing: error) }
        }
        for package in enabled {
            catalogs[package.manifest.id] = wrap(package.manifest.commands, package: package, catalog: true)
            if package.manifest.catalog { refreshCatalog(package) }
            else if package.manifest.background { let _ = initialize(package) }
        }
        onChange?()
    }
    public func cancel() {
        queryGeneration = UUID(); queryTask?.cancel(); queryTask = nil
        currentQuery = nil; live = [:]; completed = []; queryErrors = [:]
    }
    public func stop() {
        services.cancelSubscriptions(generation: generation)
        cancel(); generation = UUID()
        for task in initialization.values { task.cancel() }; initialization = [:]
        for task in settingsTasks.values { task.cancel() }; settingsTasks = [:]
        catalogDirty = []
        for task in catalogTasks.values { task.cancel() }; catalogTasks = [:]
        for task in actionTasks.values { task.cancel() }; actionTasks = [:]
        for process in processes.values { Task { await process.stop() } }; processes = [:]
        catalogs = [:]; contexts = [:]
    }
    public func invalidate() {
        queryGeneration = UUID(); queryTask?.cancel(); queryTask = nil; currentQuery = nil
        // Retain visible rows until the refreshed query completes.
        completed = []; queryErrors = [:]
        onChange?()
    }
    public func refreshCatalogs() { for package in enabled where package.manifest.catalog { refreshCatalog(package) } }
    private func process(_ package: PluginPackage) -> any ProviderTransport {
        let id = package.manifest.id
        if let process = processes[id] { return process }
        let token = generation
        let event: PluginProcess.Event = { [weak self] method, params in
            await self?.event(method, params: params, package: package, generation: token)
        }
        let transport: any ProviderTransport
        if package.bundled, let factory = builtins[id] {
            transport = LocalProvider(handler: factory(), event: event)
        } else {
            transport = PluginProcess(executable: package.executable, persistent: package.manifest.mode == .persistent, event: event)
        }
        processes[id] = transport
        return transport
    }
    private func event(_ method: String, params: JSONValue, package: PluginPackage, generation token: UUID) {
        guard token == generation, package.isEnabled(settings: settings) else { return }
        switch method {
        case "catalogChanged": if package.manifest.catalog { refreshCatalog(package) }
        case "queryInvalidated": invalidate()
        case "messageDelta":
            do {
                let delta = try params.decode(PluginMessageDelta.self)
                onMessageDelta?(package.manifest.id, delta)
            } catch {
                fail(package, error: RPCError("protocol", "Invalid messageDelta event."))
            }
        case "failure": fail(package, error: RPCError("protocol", params.string ?? "Provider failed."))
        default: break
        }
    }
    private func initialize(_ package: PluginPackage) -> Task<Void, any Error> {
        let id = package.manifest.id
        if let task = initialization[id] { return task }
        let token = generation
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            do {
                let result = try await perform("initialize", package: package, params: .object([:]), timeout: .seconds(30))
                guard result["apiVersion"].number == 2 else { throw RPCError("protocol", "Initialization must acknowledge API 2.") }
            } catch {
                if token == generation, !(error is CancellationError) { fail(package, error: error) }
                throw error
            }
        }
        initialization[id] = task; return task
    }
    private func refreshCatalog(_ package: PluginPackage) {
        let id = package.manifest.id, token = generation
        guard catalogTasks[id] == nil else { catalogDirty.insert(id); return }
        catalogTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == generation {
                    catalogTasks[id] = nil
                    if catalogDirty.remove(id) != nil && failures[id] == nil { refreshCatalog(package) }
                }
            }
            do {
                try await initialize(package).value
                let result = try await perform("catalog", package: package, params: .object([:]), timeout: .seconds(30))
                let items = try result.decode([PluginItem].self)
                try validateItems(package.manifest.commands + items, package: package)
                guard token == generation, !Task.isCancelled else { return }
                catalogs[id] = wrap(package.manifest.commands + items, package: package, catalog: true)
                onChange?()
            } catch {
                guard token == generation, !(error is CancellationError) else { return }
                fail(package, error: error)
            }
        }
    }
    private func perform(_ method: String, package: PluginPackage, params: JSONValue, timeout: Duration?, activated: Bool = false) async throws -> JSONValue {
        let token = generation
        var fields: [String: JSONValue] = ["context": try .encode(contexts[package.manifest.id] ?? PluginContext()), "input": params]
        fields["apiVersion"] = .number(2)
        let registry = services
        let context = HostServiceRegistry.Context(pluginID: package.manifest.id, generation: token, activated: activated)
        let result = try await process(package).request(method, params: .object(fields), timeout: timeout) { [weak self] capability, params in
            guard await self?.isCurrent(package, token: token) == true else { throw CancellationError() }
            return try await registry.invoke(capability, params: params, context: context, declared: package.manifest.capabilities)
        }
        guard isCurrent(package, token: token) else { throw CancellationError() }
        return result
    }
    private func isCurrent(_ package: PluginPackage, token: UUID) -> Bool {
        token == generation && package.isEnabled(settings: settings) && failures[package.manifest.id] == nil
    }
    /// Cached catalog ranking is synchronous. Live answers preserve provider and row ordering.
    public func search(_ query: String, items: [LauncherItem], weights: [String: Double], maxResults: Int) -> [RankedItem] {
        let applicable = packages.filter { $0.isEnabled(settings: settings) && $0.query(from: query, settings: settings) != nil }
        let exclusive = applicable.filter { $0.manifest.activation == .exclusive }
        let providers = exclusive.isEmpty ? applicable : exclusive
        if currentQuery != query || currentLimit != maxResults {
            let same = currentQuery == nil
            queryTask?.cancel(); queryGeneration = UUID(); currentQuery = query; currentLimit = maxResults
            if !same { live = [:] }; completed = []; queryErrors = [:]
            let token = queryGeneration, packageToken = generation
            queryTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(75)); try Task.checkCancellation() } catch { return }
                guard let self else { return }
                await withTaskGroup(of: Void.self) { group in
                    for package in providers where failures[package.manifest.id] == nil { group.addTask { await self.runQuery(package, query: query, limit: maxResults, token: token, packageToken: packageToken) } }
                }
            }
        }
        let ranked = exclusive.isEmpty ? SearchEngine.search(query: query, items: items, weights: weights, maxResults: maxResults) : []
        let normal = providers.filter { $0.manifest.activation != .fallback }
        var answer = normal.flatMap { live[$0.manifest.id] ?? [] }.map { RankedItem(item: .plugin($0), lexical: 0, weight: 0, exactAlias: false) }
        answer += ranked
        if answer.isEmpty && normal.allSatisfy({ completed.contains($0.manifest.id) || failures[$0.manifest.id] != nil }) && providers.allSatisfy({ completed.contains($0.manifest.id) || failures[$0.manifest.id] != nil }) {
            answer = providers.filter { $0.manifest.activation == .fallback }.flatMap { live[$0.manifest.id] ?? [] }
                .map { RankedItem(item: .plugin($0), lexical: 0, weight: 0, exactAlias: false) }
        }
        if answer.isEmpty, let package = exclusive.first {
            let error = failures[package.manifest.id] ?? queryErrors[package.manifest.id]
            if let error { answer = status(package, title: "\(package.manifest.name): \(error)") }
            else if !completed.contains(package.manifest.id) { answer = status(package, title: "Loading \(package.manifest.name)…") }
        }
        return Array(answer.prefix(maxResults))
    }
    private func runQuery(_ package: PluginPackage, query: String, limit: Int, token: UUID, packageToken: UUID) async {
        let id = package.manifest.id
        do {
            try await initialize(package).value; try Task.checkCancellation()
            let input = PluginQuery(query: package.query(from: query, settings: settings) ?? query, fullQuery: query, maxResults: limit)
            let output = try await perform("query", package: package, params: .encode(input), timeout: .seconds(2))
            let items = try output.decode([PluginItem].self)
            guard items.count <= 50 else { throw RPCError("protocol", "Query returned more than 50 rows.") }
            try validateItems(items, package: package)
            guard token == queryGeneration, packageToken == generation, !Task.isCancelled else { return }
            live[id] = wrap(Array(items.prefix(limit)), package: package, catalog: false)
        } catch {
            guard token == queryGeneration, packageToken == generation, !(error is CancellationError) else { return }
            live[id] = []; queryErrors[id] = String(describing: error)
            if (error as? RPCError)?.code == "protocol" || error is DecodingError { fail(package, error: error) }
        }
        guard token == queryGeneration, packageToken == generation else { return }
        completed.insert(id); onChange?()
    }
    private func fail(_ package: PluginPackage, error: any Error) {
        let id = package.manifest.id
        failures[id] = String(describing: error); catalogs[id] = nil; live[id] = nil
        if let process = processes.removeValue(forKey: id) { Task { await process.stop() } }
        onChange?()
    }
    private func wrap(_ items: [PluginItem], package: PluginPackage, catalog: Bool) -> [PluginResult] {
        items.map { PluginResult(pluginID: package.manifest.id, item: $0, generation: generation, catalog: catalog, directory: package.directory) }
    }
    private func status(_ package: PluginPackage, title: String) -> [RankedItem] {
        wrap([PluginItem(id: "host-status", title: title, symbol: "puzzlepiece.extension")], package: package, catalog: false)
            .map { RankedItem(item: .plugin($0), lexical: 0, weight: 0, exactAlias: false) }
    }
    public func authorize(_ result: PluginResult, action: PluginAction) throws -> PluginPackage {
        guard result.generation == generation, let package = enabled.first(where: { $0.manifest.id == result.pluginID }) else {
            throw PluginError.superseded
        }
        try validate(action, package: package); return package
    }
    public func activate(_ result: PluginResult, action: PluginAction, argument: String?, text: String? = nil, completion: @escaping (Result<PluginEffects, any Error>) -> Void) -> UUID {
        let id = UUID(), token = generation
        actionTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { actionTasks[id] = nil }
            do {
                let package = try authorize(result, action: action)
                let output: JSONValue
                if action.kind == .callback {
                    try await initialize(package).value
                    let input = PluginActivation(actionID: action.value, payload: action.payload ?? .null, item: result.item, argument: argument, text: text)
                    output = try await perform("activate", package: package, params: .encode(input), timeout: nil, activated: true)
                } else {
                    output = try await services.invoke(action.value, params: action.payload ?? .object([:]),
                        context: .init(pluginID: result.pluginID, generation: token, activated: true), declared: package.manifest.capabilities)
                }
                try Task.checkCancellation()
                guard token == generation else { completion(.failure(PluginError.superseded)); return }
                let effects = try output.decode(PluginEffects.self)
                if let view = effects.view {
                    try validate(view, package: package)
                }
                if effects.refreshCatalog { refreshCatalog(package) }
                if effects.refreshQuery { invalidate() }
                completion(.success(effects))
            } catch {
                if token != generation { completion(.failure(PluginError.superseded)) }
                else { completion(.failure(error)) }
            }
        }
        return id
    }
    public func cancelAction(_ id: UUID) { actionTasks[id]?.cancel() }
    public func cancelActions() { for task in actionTasks.values { task.cancel() } }
    public func updateSettings(_ updated: [PluginSetting]) throws {
        try validateSettings(updated)
        let previous = settings; settings = updated
        for package in enabled {
            let id = package.manifest.id
            let values = package.setting(in: updated)?.values ?? [:]
            guard values != (package.setting(in: previous)?.values ?? [:]) else { continue }
            contexts[id]?.settings = try package.manifest.validatedSettings(values)
            guard package.manifest.mode != .declarative, initialization[id] != nil else { continue }
            let token = generation
            settingsTasks[id]?.cancel()
            settingsTasks[id] = Task { [weak self] in
                guard let self else { return }
                do {
                    try await initialize(package).value
                    _ = try await perform("settings", package: package, params: .object([:]), timeout: .seconds(30))
                    guard token == generation, !Task.isCancelled else { return }
                    if package.manifest.catalog { refreshCatalog(package) }; invalidate()
                } catch {
                    if token == generation, !(error is CancellationError) { fail(package, error: error) }
                }
            }
        }
        onChange?()
    }
    public func validateSettings(_ updated: [PluginSetting]) throws {
        for package in packages { _ = try package.manifest.validatedSettings(package.setting(in: updated)?.values ?? [:]) }
        for package in packages {
            _ = try package.trigger(in: updated)
            _ = try package.hotkey(in: updated)
        }
    }
    private func validateItems(_ items: [PluginItem], package: PluginPackage) throws {
        guard Set(items.map(\.id)).count == items.count, items.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }) else {
            throw RPCError("protocol", "Provider returned empty or duplicate item IDs/titles.")
        }
        for item in items { for action in [item.primary, item.secondary].compactMap({ $0 }) { try validate(action, package: package) } }
    }
    private func validate(_ view: PluginView, package: PluginPackage) throws {
        guard !view.id.isEmpty, !view.title.isEmpty else {
            throw RPCError("protocol", "Invalid view.")
        }
        switch view.kind {
        case .editor:
            guard let save = view.save, save.kind == .callback else {
                throw RPCError("protocol", "Invalid document view.")
            }
            try validate(save, package: package)
        case .chat:
            guard let send = view.send, send.kind == .callback, let messages = view.messages,
                  messages.allSatisfy({ !$0.id.isEmpty }), Set(messages.map(\.id)).count == messages.count else {
                throw RPCError("protocol", "Invalid chat view.")
            }
            try validate(send, package: package)
        case .month:
            break
        }
    }
    private func validate(_ action: PluginAction, package: PluginPackage) throws {
        if action.kind == .service && !package.manifest.capabilities.contains(action.value) { throw RPCError("protocol", "Action uses an undeclared capability.") }
        if action.kind == .callback && (package.manifest.mode == .declarative || action.value.isEmpty) { throw RPCError("protocol", "Invalid callback action.") }
        if [.openURL, .openPath, .openApplication, .reveal, .execute, .service].contains(action.kind) && action.value.isEmpty { throw RPCError("protocol", "Empty action target.") }
        if action.kind == .execute && !action.value.hasPrefix("/") { throw RPCError("protocol", "Execute requires an absolute executable path.") }
        if action.kind == .openURL {
            guard let url = URL(string: action.value), let scheme = url.scheme, !["javascript", "data"].contains(scheme.lowercased()) else {
                throw RPCError("protocol", "Invalid URL action.")
            }
        }
    }
}
