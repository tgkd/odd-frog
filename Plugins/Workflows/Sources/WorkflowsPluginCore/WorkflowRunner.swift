import Foundation
import OddFrogPluginAPI

public enum RunOutcome: Sendable, Equatable {
    case finished(notification: String)
    case paused(Review)
}

public struct RunSnapshot: Sendable, Equatable {
    public var runs: [RunRecord]
    public var details: [String: String]
}

public actor WorkflowRunner {
    public static let execTimeout: Duration = .seconds(600)

    private struct Segment: Sendable {
        var workflow: Workflow
        var start: Int
        var values: WorkflowValues
        var notes: [String]
        var settings: [String: JSONValue]
        var reviewed: String?
    }

    private struct Pause {
        var segment: Segment
        var title: String
        var text: String
        var editable: Bool
        var draft: String

        func review(_ runID: String) -> Review {
            Review(runID: runID, step: segment.start, title: title, text: draft, editable: editable)
        }
    }

    private let executor: StepExecutor
    private let history: URL?
    private let reviewFiles: ReviewFiles
    private let now: @Sendable () -> Date
    private let onChange: @Sendable () async -> Void
    private var runs: [RunRecord] = []
    private var details: [String: String] = [:]
    private var tasks: [String: Task<RunOutcome, any Error>] = [:]
    private var pauses: [String: Pause] = [:]
    private var files: [String: [URL]] = [:]
    private var stopping = false

    public init(exec: any ExecRunning = ProcessGroupRunner(), history: URL?, environment: [String: String] = ProcessInfo.processInfo.environment,
                now: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable () async -> Void = {}) {
        executor = StepExecutor(exec: exec, environment: environment)
        self.history = history
        reviewFiles = ReviewFiles(history: history)
        self.now = now
        self.onChange = onChange
    }

    public nonisolated var reviewFolder: URL { reviewFiles.folder }

    public func load() {
        reviewFiles.removeAll()
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
        let segment = Segment(workflow: workflow, start: 0, values: WorkflowValues(input: input), notes: [],
                              settings: settings)
        return try await launch(id, segment)
    }

    public func review(_ runID: String) throws -> Review {
        guard let pause = pauses[runID] else { throw Self.notWaiting }
        return pause.review(runID)
    }

    public func saveDraft(_ runID: String, text: String) {
        guard var pause = pauses[runID], pause.editable else { return }
        pause.draft = text
        pauses[runID] = pause
    }

    public func submit(_ runID: String, text: String, settings: [String: JSONValue]) async throws -> RunOutcome {
        guard !stopping else { throw CancellationError() }
        guard let pause = pauses.removeValue(forKey: runID) else { throw Self.notWaiting }
        var segment = pause.segment
        segment.reviewed = pause.editable ? text : pause.text
        segment.settings = settings
        update(runID) { $0.state = .running }
        return try await launch(runID, segment)
    }

    public func cancel(_ runID: String) async throws {
        if let pause = pauses.removeValue(forKey: runID) {
            await end(runID, state: .cancelled, cancelling: pause.segment.start)
            discardFiles(runID)
            return
        }
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
        pauses.removeAll()
        files.removeAll()
        reviewFiles.removeAll()
        runs = RunHistory.interrupted(runs, at: now())
        save()
    }

    private static let notWaiting = RPCError("workflow", "This run is not waiting for review.")

    private func launch(_ id: String, _ segment: Segment) async throws -> RunOutcome {
        let task = Task { [self] in
            try await execute(id, segment)
        }
        tasks[id] = task
        await onChange()
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func execute(_ id: String, _ segment: Segment) async throws -> RunOutcome {
        defer { settle(id) }
        let workflow = segment.workflow
        var values = segment.values
        var notes = segment.notes
        for index in segment.start..<workflow.steps.count {
            let step = workflow.steps[index]
            if Task.isCancelled {
                await end(id, state: stopping ? .interrupted : .cancelled, cancelling: index)
                throw CancellationError()
            }
            let result: Attempt
            if index == segment.start, let reviewed = segment.reviewed {
                result = complete(id, step: index, reviewed: reviewed)
            } else {
                update(id) { $0.steps[index].state = .running; $0.steps[index].started = now() }
                await changed()
                if case .confirm(let confirm) = step.kind {
                    do {
                        let rendered = try executor.review(confirm, values: values, workflowTitle: workflow.title)
                        let resume = Segment(workflow: workflow, start: index, values: values, notes: notes,
                                             settings: segment.settings)
                        let pause = Pause(segment: resume, title: rendered.title, text: rendered.text,
                                          editable: confirm.editable, draft: rendered.text)
                        pauses[id] = pause
                        update(id) { $0.state = .paused }
                        return .paused(pause.review(id))
                    } catch {
                        result = .failed(error as? StepFailure ?? StepFailure(String(describing: error)))
                    }
                } else {
                    result = await attempt(step, values: values, workflowFile: workflow.file, settings: segment.settings)
                }
            }
            switch result {
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

    private func complete(_ id: String, step index: Int, reviewed text: String) -> Attempt {
        guard let parts = ReviewedText(text) else {
            return .failed(StepFailure("The reviewed text is empty."))
        }
        let file: URL
        do {
            file = try reviewFiles.write(parts.body, run: id, step: index)
        } catch {
            return .failed(StepFailure("Cannot write the review file.", detail: error.localizedDescription))
        }
        files[id, default: []].append(file)
        return .done(StepExecutor.reviewed(text, parts, file: file))
    }

    private func settle(_ id: String) {
        tasks[id] = nil
        guard runs.first(where: { $0.id == id })?.state != .paused else { return }
        pauses[id] = nil
        discardFiles(id)
    }

    private func discardFiles(_ id: String) {
        reviewFiles.remove(files.removeValue(forKey: id) ?? [])
    }

    private enum Attempt {
        case done(StepCompletion)
        case failed(StepFailure)
        case cancelled
    }

    private func attempt(_ step: WorkflowStep, values: WorkflowValues, workflowFile: URL,
                         settings: [String: JSONValue]) async -> Attempt {
        let limit = step.timeout ?? Self.execTimeout
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
