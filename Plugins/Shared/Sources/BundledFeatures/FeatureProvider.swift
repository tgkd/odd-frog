import Foundation
import OddFrogCore
import OddFrogPluginAPI

public actor FeatureProvider: ProviderHandler {
    public enum Feature: String, Sendable { case applications, commands, scripts, calculator, web, terminal }
    private let feature: Feature
    private let watcher = DirectoryWatcher()
    private let indexer = AppIndexer()
    private var rates: CurrencyRateStore?
    private var refresh: Task<Void, Never>?
    private var emit: (@Sendable (String) async -> Void)?
    public init(_ feature: Feature) { self.feature = feature }
    public func start(emit: @escaping @Sendable (String) async -> Void) async {
        self.emit = emit
    }
    public func shutdown() async {
        refresh?.cancel()
        refresh = nil
        watcher.stop()
    }
    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        let context = try params["context"].decode(PluginContext.self)
        switch method {
        case "initialize", "settings":
            setup(context)
            return .object(["apiVersion": .number(2)])
        case "catalog":
            switch feature {
            case .applications: return try .encode(await indexer.refresh().map(Self.application))
            case .scripts:
                let folders = (context.settings["folders"]?.array ?? []).compactMap(\.string).map { URL(fileURLWithPath: ConfigParser.expandTilde($0)) }
                return try .encode(ScriptScanner.scan(folders: folders).map(Self.script))
            case .commands:
                let config = try ConfigLoader.load(from: URL(fileURLWithPath: context.configPath)).config
                return try .encode(config.commands.map { Self.command($0, shell: config.general.shell) })
            default: return .array([])
            }
        case "query":
            let query = try params["input"].decode(PluginQuery.self)
            let items: [PluginItem]
            switch feature {
            case .calculator:
                let cached = context.settings["currency"]?.bool == false ? nil : await rates?.current()
                items = QuickAction.calculation(for: query.query, rates: cached).map { [Self.quick($0)] } ?? []
            case .web: items = QuickAction.fallbacks(for: query.query, searchTemplate: context.settings["url"]?.string ?? Settings.Search.defaultURL).map(Self.quick)
            case .terminal:
                items = query.query.isEmpty ? [] : [PluginItem(id: "run", title: "Run in Terminal", subtitle: query.query, kind: "Terminal", symbol: "terminal", primary: PluginAction(.terminal, query.query))]
            default: items = []
            }
            return try .encode(items)
        default: throw RPCError("method", "Unsupported method: \(method)")
        }
    }
    private func setup(_ context: PluginContext) {
        refresh?.cancel(); refresh = nil
        let emit = self.emit
        switch feature {
        case .applications:
            watcher.watch(AppScanner.watchedDirectories(roots: AppScanner.defaultRoots)) { Task { await emit?("catalogChanged") } }
        case .scripts:
            let folders = (context.settings["folders"]?.array ?? []).compactMap(\.string).map { URL(fileURLWithPath: ConfigParser.expandTilde($0)) }
            watcher.watch(context.settings["watch"]?.bool == false ? [] : folders) { Task { await emit?("catalogChanged") } }
            // Periodic rescanning also catches folders created after startup and watch=false refreshes.
            refresh = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    await emit?("catalogChanged")
                }
            }
        case .commands:
            watcher.watch([URL(fileURLWithPath: context.configPath).deletingLastPathComponent()]) { Task { await emit?("catalogChanged") } }
        case .calculator:
            guard context.settings["currency"]?.bool != false else { rates = nil; return }
            let store = CurrencyRateStore(url: URL(fileURLWithPath: context.storagePath).appendingPathComponent("rates.json"), provider: ExchangeRateAPIProvider())
            rates = store
            refresh = Task {
                while !Task.isCancelled {
                    let before = await store.current()
                    let after = await store.refreshIfStale()
                    if before != after { await emit?("queryInvalidated") }
                    do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                }
            }
        case .web, .terminal: break
        }
    }
    public static func application(_ app: AppItem) -> PluginItem {
        PluginItem(id: app.url.path, title: app.name, icon: app.url.path, aliases: app.aliases,
                   primary: PluginAction(.openApplication, app.url.path), secondary: PluginAction(.reveal, app.url.path), history: true)
    }
    public static func command(_ command: CommandItem, shell: String) -> PluginItem {
        let primary: PluginAction, secondary: PluginAction, kind: String, symbol: String
        var argument: PluginArgument?
        switch command.action {
        case .url(let url):
            primary = PluginAction(.openURL, URLTemplate.display(url)); secondary = PluginAction(.copy, URLTemplate.display(url))
            kind = "URL"; symbol = "link"
            if URLTemplate.accepts(url) { argument = PluginArgument(placeholder: "Query", optional: true) }
        case .path(let url):
            primary = PluginAction(.openPath, url.path)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            secondary = isDirectory.boolValue ? PluginAction(.terminal, "exec \(ShellCommand.quote(shell)) -l", cwd: url.path) : PluginAction(.reveal, url.path)
            kind = "Folder"; symbol = "folder"
        case .shell(let text):
            let terminal = PluginAction(.terminal, text, cwd: command.cwd?.path)
            primary = command.terminal ? terminal : PluginAction(.execute, shell, argv: ShellCommand.backgroundArguments(command: text), cwd: command.cwd?.path)
            secondary = terminal; kind = command.terminal ? "Terminal" : "Shell"; symbol = "terminal"
        }
        return PluginItem(id: command.stableID, title: command.name, subtitle: commandSubtitle(command),
                          kind: kind, symbol: symbol, aliases: command.aliases, argument: argument,
                          primary: primary, secondary: secondary, history: true)
    }
    private static func commandSubtitle(_ command: CommandItem) -> String? {
        switch command.action {
        case .shell: return nil
        case .path(let url): return LauncherItem.abbreviate(url.path)
        case .url(let url):
            guard let host = url.host else { return URLTemplate.display(url) }
            var text = host + url.path
            while text.hasSuffix("/") { text.removeLast() }
            return text.replacingOccurrences(of: URLTemplate.encoded, with: URLTemplate.placeholder)
        }
    }
    public static func script(_ script: ScriptItem) -> PluginItem {
        let args = script.argument == nil ? [] : ["{argument}"]
        let terminal = PluginAction(.terminal, script.url.path, argv: args, cwd: script.url.deletingLastPathComponent().path)
        let primary = script.mode == .fullOutput ? terminal : PluginAction(.execute, script.url.path, argv: args, cwd: script.url.deletingLastPathComponent().path, output: "notification")
        return PluginItem(id: script.url.path, title: script.title, subtitle: script.package.flatMap { $0.caseInsensitiveCompare(script.title) == .orderedSame ? nil : $0 }, kind: "Script",
                          symbol: "terminal", icon: script.icon.map { "text:" + $0 }, aliases: script.aliases,
                          argument: script.argument.map { PluginArgument(placeholder: $0.placeholder, optional: $0.optional) },
                          primary: primary, secondary: terminal, history: true)
    }
    public static func quick(_ quick: QuickAction) -> PluginItem {
        let action: PluginAction, symbol: String
        switch quick {
        case .calculation: action = PluginAction(.copy, quick.copyText ?? ""); symbol = "plus.forwardslash.minus"
        case .openURL(let url), .webSearch(_, let url): action = PluginAction(.openURL, url.absoluteString); symbol = "magnifyingglass"
        case .terminal(let command): action = PluginAction(.terminal, command); symbol = "terminal"
        }
        return PluginItem(id: quick.id, title: quick.title, subtitle: quick.subtitle, kind: quick.kindLabel, symbol: symbol, primary: action)
    }
}
