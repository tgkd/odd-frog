import Foundation
import OddFrogPluginAPI

public enum RunOutcome: Sendable, Equatable {
    case finished(notification: String)
}

public struct RunSnapshot: Sendable, Equatable {
    public var runs: [RunRecord]
    public var details: [String: String]
}

public actor WorkflowRunner {
    public static let execTimeout: Duration = .seconds(600)
    public static let llmTimeout: Duration = .seconds(180)

    private let executor: StepExecutor
    private let history: URL?
    private let now: @Sendable () -> Date
    private let onChange: @Sendable () async -> Void
    private var runs: [RunRecord] = []
    private var details: [String: String] = [:]
    private var tasks: [String: Task<RunOutcome, any Error>] = [:]
    private var stopping = false

    public init(exec: any ExecRunning = ProcessGroupRunner(), model: any ModelCompleting = ModelRouter(),
                history: URL?, environment: [String: String] = ProcessInfo.processInfo.environment,
                now: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable () async -> Void = {}) {
        executor = StepExecutor(exec: exec, model: model, environment: environment)
        self.history = history
        self.now = now
        self.onChange = onChange
    }

    public func load() {
        guard let history else { return }
        runs = RunHistory.trimmed(RunHistory.interrupted(RunHistory.load(from: history), at: now()))
        save()
    }

    public func snapshot() -> RunSnapshot {
        RunSnapshot(runs: runs, details: details)
    }

    public func start(_ workflow: Workflow, input: String, settings: [String: JSONValue]) async throws -> RunOutcome {
        guard !stopping else { throw CancellationError() }
        let id = UUID().uuidString
        let steps = workflow.steps.map { RunRecord.Step(label: $0.label, kind: $0.kindName) }
        runs.insert(RunRecord(id: id, workflowID: workflow.id, workflowTitle: workflow.title, state: .running,
                              started: now(), steps: steps), at: 0)
        runs = RunHistory.trimmed(runs)
        save()
        let task = Task { [self] in
            try await execute(id, workflow: workflow, input: input, settings: settings)
        }
        tasks[id] = task
        await onChange()
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func cancel(_ runID: String) async throws {
        guard let task = tasks[runID], runs.first(where: { $0.id == runID })?.state == .running else {
            throw RPCError("workflow", "This run is not running.")
        }
        task.cancel()
        _ = await task.result
    }

    public func shutdown() async {
        stopping = true
        let pending = Array(tasks.values)
        pending.forEach { $0.cancel() }
        for task in pending {
            _ = await task.result
        }
        runs = RunHistory.interrupted(runs, at: now())
        save()
    }

    private func execute(_ id: String, workflow: Workflow, input: String,
                         settings: [String: JSONValue]) async throws -> RunOutcome {
        defer { tasks[id] = nil }
        var values = WorkflowValues(input: input)
        var notes: [String] = []
        for (index, step) in workflow.steps.enumerated() {
            if Task.isCancelled {
                await end(id, state: stopping ? .interrupted : .cancelled, cancelling: index)
                throw CancellationError()
            }
            update(id) { $0.steps[index].state = .running; $0.steps[index].started = now() }
            await changed()
            switch await attempt(step, values: values, workflowFile: workflow.file, settings: settings) {
            case .done(let completion):
                if let stepID = step.id {
                    values.steps[stepID] = completion.values
                }
                if let note = completion.note {
                    notes.append(note)
                }
                update(id) {
                    $0.steps[index].state = .done
                    $0.steps[index].ended = now()
                    $0.steps[index].exit = completion.values.exit
                }
                await changed()
            case .failed(let failure):
                update(id) {
                    $0.steps[index].state = .failed
                    $0.steps[index].ended = now()
                    $0.steps[index].exit = failure.exit
                    $0.steps[index].error = failure.summary
                }
                if step.onError == .continue {
                    if let stepID = step.id {
                        values.steps[stepID] = StepValues(output: "", exit: failure.exit, stderr: failure.stderr, failed: true)
                    }
                    await changed()
                    continue
                }
                details[id] = failure.detail
                update(id) { $0.state = .failed; $0.ended = now(); $0.error = failure.summary }
                await changed()
                let message = "\(step.label) failed: \(StepFailure.joined(failure.summary, detail: failure.detail))"
                throw RPCError("workflow", message)
            case .cancelled:
                await end(id, state: stopping ? .interrupted : .cancelled, cancelling: index)
                throw CancellationError()
            }
        }
        update(id) { $0.state = .finished; $0.ended = now() }
        await changed()
        let count = workflow.steps.count
        let notification = notes.isEmpty ? "Finished \(count) \(count == 1 ? "step" : "steps")." : notes.joined(separator: "\n")
        return .finished(notification: notification)
    }

    private enum Attempt {
        case done(StepCompletion)
        case failed(StepFailure)
        case cancelled
    }

    private func attempt(_ step: WorkflowStep, values: WorkflowValues, workflowFile: URL,
                         settings: [String: JSONValue]) async -> Attempt {
        let limit = step.timeout ?? (step.kindName == "llm" ? Self.llmTimeout : Self.execTimeout)
        let executor = executor
        do {
            let completion: StepCompletion? = try await withThrowingTaskGroup(of: StepCompletion?.self) { group -> StepCompletion? in
                group.addTask {
                    try await executor.run(step, values: values, workflowFile: workflowFile, settings: settings)
                }
                group.addTask {
                    try await Task.sleep(for: limit)
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
            if Task.isCancelled {
                return .cancelled
            }
            guard let completion else {
                return .failed(StepFailure("timed out after \(Self.seconds(limit)) s"))
            }
            return .done(completion)
        } catch {
            if Task.isCancelled || error is CancellationError {
                return Task.isCancelled ? .cancelled : .failed(StepFailure(String(describing: error)))
            }
            if let failure = error as? StepFailure {
                return .failed(failure)
            }
            return .failed(StepFailure(String(describing: error)))
        }
    }

    private func end(_ id: String, state: RunRecord.State, cancelling index: Int) async {
        update(id) {
            $0.state = state
            $0.ended = now()
            if $0.steps.indices.contains(index) {
                $0.steps[index].state = .cancelled
                $0.steps[index].ended = now()
            }
        }
        await changed()
    }

    private func update(_ id: String, _ change: (inout RunRecord) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[index])
        save()
    }

    private func changed() async {
        guard !stopping else { return }
        await onChange()
    }

    private func save() {
        guard let history else { return }
        try? RunHistory.save(runs, to: history)
    }

    static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
