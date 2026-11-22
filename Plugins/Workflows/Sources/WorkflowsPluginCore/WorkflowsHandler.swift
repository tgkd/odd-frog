import Foundation
import OddFrogPluginAPI

public actor WorkflowsHandler: ProviderHandler {
    private let exec: any ExecRunning
    private let rescanInterval: Duration
    private let watcher = FolderWatcher()

    private var emit: (@Sendable (String) async -> Void)?
    private var closed = false
    private var runner: WorkflowRunner?
    private var folders: [URL] = []
    private var library = WorkflowLibrary()
    private var periodic: Task<Void, Never>?

    public init(exec: any ExecRunning = ProcessGroupRunner(), rescanInterval: Duration = .seconds(60)) {
        self.exec = exec
        self.rescanInterval = rescanInterval
    }

    public func start(emit: @escaping @Sendable (String) async -> Void) async {
        self.emit = emit
    }

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return try await initialize(params: params)
        case "settings":
            configure(try params["context"].decode(PluginContext.self), force: true)
            return .object([:])
        case "catalog":
            configure(try params["context"].decode(PluginContext.self), force: true)
            return try .encode(library.workflows.map(Self.item))
        case "query":
            return try await query(params: params)
        case "activate":
            return try await activate(params: params)
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }

    public func shutdown() async {
        closed = true
        watcher.stop()
        periodic?.cancel()
        periodic = nil
        await runner?.shutdown()
    }

    private func initialize(params: JSONValue) async throws -> JSONValue {
        let ack: JSONValue = .object(["apiVersion": .number(2)])
        if closed || Task.isCancelled {
            return ack
        }
        let context = try params["context"].decode(PluginContext.self)
        if runner == nil {
            var history: URL?
            if !context.storagePath.isEmpty {
                let storage = URL(fileURLWithPath: context.storagePath, isDirectory: true)
                try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
                history = storage.appendingPathComponent(RunHistory.fileName)
            }
            let created = WorkflowRunner(exec: exec, history: history, onChange: { [weak self] in
                await self?.send("queryInvalidated")
            })
            runner = created
            await created.load()
        }
        if closed {
            return ack
        }
        configure(context, force: true)
        startPeriodic()
        return ack
    }

    private func query(params: JSONValue) async throws -> JSONValue {
        let context = try params["context"].decode(PluginContext.self)
        let input = try params["input"].decode(PluginQuery.self)
        configure(context, force: false)
        let snapshot = await runner?.snapshot() ?? RunSnapshot(runs: [], details: [:])
        return try .encode(WorkflowRows.rows(runs: snapshot.runs, details: snapshot.details, errors: library.errors,
                                             hasFolders: !folders.isEmpty, keywords: library.workflows.map(\.keyword),
                                             query: input.query, maxResults: input.maxResults))
    }

    private func activate(params: JSONValue) async throws -> JSONValue {
        let context = try params["context"].decode(PluginContext.self)
        let activation = try params["input"].decode(PluginActivation.self)
        switch activation.actionID {
        case "run":
            guard let runner, !closed else { throw RPCError("workflow", "Workflows are not ready yet.") }
            let workflow = try current(activation.payload["workflow"].string ?? "")
            return try .encode(Self.effects(try await runner.start(workflow, input: activation.argument ?? "",
                                                                   settings: context.settings)))
        case "save":
            await runner?.saveDraft(activation.payload["run"].string ?? "", text: activation.text ?? "")
            return try .encode(PluginEffects())
        case "submit":
            guard let runner, !closed else { throw Self.notWaiting }
            let outcome = try await runner.submit(activation.payload["run"].string ?? "", text: activation.text ?? "",
                                                  settings: context.settings)
            return try .encode(Self.effects(outcome))
        case "continue":
            guard let runner else { throw Self.notWaiting }
            let review = try await runner.review(activation.payload["run"].string ?? "")
            return try .encode(PluginEffects(refreshQuery: true, view: Self.view(review)))
        case "cancel":
            guard let runner else { throw RPCError("workflow", "This run is not running.") }
            try await runner.cancel(activation.payload["run"].string ?? "")
            return try .encode(PluginEffects(notification: "Cancelled.", refreshQuery: true))
        default:
            throw RPCError("action", "Unknown action: \(activation.actionID)")
        }
    }

    private func current(_ id: String) throws -> Workflow {
        guard let known = library.workflows.first(where: { $0.id == id }) else {
            throw RPCError("workflow", "This workflow is no longer in the chosen folders.")
        }
        let text: String
        do {
            text = try String(contentsOf: known.file, encoding: .utf8)
        } catch {
            throw RPCError("workflow", "Cannot read \(known.file.lastPathComponent): \(error.localizedDescription)")
        }
        let workflow = try WorkflowParser.parse(text, file: known.file)
        guard workflow.id == id else {
            throw RPCError("workflow", "\(known.file.lastPathComponent) no longer defines the workflow \(id).")
        }
        return workflow
    }

    private func configure(_ context: PluginContext, force: Bool) {
        let wanted = (context.settings["folders"]?.array ?? []).compactMap(\.string)
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        guard force || wanted != folders else { return }
        folders = wanted
        library = WorkflowLibrary.scan(folders: wanted)
        guard !closed else { return }
        watcher.watch(wanted) { [weak self] in
            Task { await self?.send("catalogChanged") }
        }
    }

    private func startPeriodic() {
        guard periodic == nil else { return }
        let interval = rescanInterval
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                await self?.send("catalogChanged")
            }
        }
    }

    private func send(_ event: String) async {
        guard !closed else { return }
        await emit?(event)
    }

    private static let notWaiting = RPCError("workflow", "This run is not waiting for review.")

    static func effects(_ outcome: RunOutcome) -> PluginEffects {
        switch outcome {
        case .finished(let notification):
            PluginEffects(notification: notification, refreshQuery: true)
        case .paused(let review):
            PluginEffects(refreshQuery: true, view: view(review))
        }
    }

    static func view(_ review: Review) -> PluginView {
        let run: JSONValue = .object(["run": .string(review.runID)])
        return PluginView(id: review.viewID, title: review.title, text: review.text,
                          save: PluginAction(.callback, "save", payload: run),
                          submit: PluginAction(.callback, "submit", payload: run))
    }

    static func item(_ workflow: Workflow) -> PluginItem {
        PluginItem(id: workflow.id, title: workflow.title, subtitle: workflow.keyword, kind: "Workflow",
                   symbol: "flowchart", aliases: [workflow.keyword], argument: workflow.argument,
                   primary: PluginAction(.callback, "run", payload: .object(["workflow": .string(workflow.id)])),
                   history: true)
    }
}
