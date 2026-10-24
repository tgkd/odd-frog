import Foundation
import OddFrogPluginAPI

public actor FilesHandler: ProviderHandler {
    private struct Index {
        var root: String
        var handle: FffLibrary.Handle
    }

    private let loader: @Sendable () throws -> FffLibrary
    private let pollInterval: Duration
    private let home: String
    private var library: FffLibrary?
    private var loadFailure: String?
    private var indexes: [Index] = []
    private var folders: [String] = []
    private var emit: (@Sendable (String) async -> Void)?
    private var watcher: Task<Void, Never>?

    public init(loader: @escaping @Sendable () throws -> FffLibrary = { try FffLibrary.load() },
                pollInterval: Duration = .milliseconds(300),
                home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.loader = loader
        self.pollInterval = pollInterval
        self.home = home
    }

    public func start(emit: @escaping @Sendable (String) async -> Void) async {
        self.emit = emit
    }

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize", "settings":
            let context = try params["context"].decode(PluginContext.self)
            configure(context)
            return method == "initialize" ? .object(["apiVersion": .number(2)]) : .object([:])
        case "query":
            let input = try params["input"].decode(PluginQuery.self)
            return try .encode(query(input))
        case "activate":
            let activation = try params["input"].decode(PluginActivation.self)
            try track(activation)
            return try .encode(PluginEffects())
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }

    public func shutdown() async {
        closeIndexes()
    }

    // No suspension points between closing and reopening: actor reentrancy would otherwise let a second
    // configure run in between and leave duplicate or twice-closed handles.
    private func configure(_ context: PluginContext) {
        let requested = (context.settings["folders"]?.array ?? []).compactMap(\.string)
            .map { ($0 as NSString).expandingTildeInPath }
        guard requested != folders || (indexes.isEmpty && library == nil) else { return }
        closeIndexes()
        folders = requested
        loadFailure = nil
        var openFailure: String?
        if library == nil {
            do { library = try loader() } catch { loadFailure = "\(error)" }
        }
        guard let library else { return }
        let storage = URL(fileURLWithPath: context.storagePath)
        for root in requested {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let database = storage.appendingPathComponent("index-" + Self.fingerprint(root)).path
            do {
                indexes.append(Index(root: root, handle: try library.open(root: root, database: database)))
            } catch {
                openFailure = openFailure ?? "\(root): \(error)"
            }
        }
        if indexes.isEmpty, let openFailure { loadFailure = openFailure }
        watchScans()
    }

    private func closeIndexes() {
        watcher?.cancel()
        watcher = nil
        if let library {
            for index in indexes { library.close(index.handle) }
        }
        indexes = []
    }

    private func watchScans() {
        guard !indexes.isEmpty else { return }
        let poll = pollInterval
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                guard let scanning = await self?.isScanning(), scanning else { break }
                try? await Task.sleep(for: poll)
            }
            if !Task.isCancelled { await self?.emit?("queryInvalidated") }
        }
    }

    private func track(_ activation: PluginActivation) throws {
        guard activation.actionID == "track", let library,
              let root = activation.payload["root"].string, let path = activation.payload["path"].string,
              let index = indexes.first(where: { $0.root == root }) else { return }
        try library.track(index.handle, query: activation.payload["query"].string ?? "", path: root + "/" + path)
    }

    private func isScanning() -> Bool {
        guard let library else { return false }
        return indexes.contains { library.isScanning($0.handle) }
    }

    private func query(_ request: PluginQuery) throws -> [PluginItem] {
        if let loadFailure {
            return FilesProvider.respond(to: request, state: .unavailable(loadFailure), hits: [], home: home)
        }
        guard let library, !indexes.isEmpty else {
            return FilesProvider.respond(to: request, state: .noFolders, hits: [], home: home)
        }
        let text = request.query.trimmingCharacters(in: .whitespaces)
        var groups: [[FileHit]] = []
        if !text.isEmpty {
            let limit = max(1, min(request.maxResults, 50))
            for index in indexes {
                guard let hits = try? library.search(index.handle, query: text, limit: limit) else { continue }
                groups.append(hits.map {
                    FileHit(root: index.root, relativePath: $0.relativePath, isDirectory: $0.isDirectory, score: $0.score)
                })
            }
        }
        return FilesProvider.respond(to: request, state: .ready(scanning: isScanning()),
                                     hits: FilesProvider.merge(groups), home: home)
    }

    private static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
