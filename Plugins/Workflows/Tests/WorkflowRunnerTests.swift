import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

struct FakeExec: ExecRunning {
    let body: @Sendable (ExecRequest) async throws -> ExecResult
    func run(_ request: ExecRequest) async throws -> ExecResult { try await body(request) }
}

actor Recorder {
    private(set) var requests: [ExecRequest] = []
    func add(_ request: ExecRequest) { requests.append(request) }
}

func text(_ value: String) -> Template { Template(parts: [.text(value)]) }

func ref(_ name: String, _ field: String? = nil) -> Template {
    Template(parts: [.value(ValueReference(name: name, field: field))])
}

func exec(_ id: String?, _ position: Int, _ argv: [Template], onError: WorkflowStep.OnError = .stop,
          timeout: Duration? = nil) -> WorkflowStep {
    WorkflowStep(id: id, position: position, kind: .exec(ExecStep(argv: argv)), onError: onError, timeout: timeout)
}

func show(_ position: Int, _ template: Template) -> WorkflowStep {
    WorkflowStep(position: position, kind: .show(ShowStep(text: template)))
}

func workflow(_ steps: [WorkflowStep], id: String = "sample") -> Workflow {
    Workflow(id: id, title: "Sample", keyword: "sample", steps: steps,
             file: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sample.toml"))
}

func temporaryFolder() throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-wf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

func eventually(_ timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

let waitsForCancel = FakeExec { _ in
    try await Task.sleep(for: .seconds(60))
    return ExecResult()
}

struct WorkflowRunnerTests {
    @Test func aFailedStepStopsTheRunAndThrowsItsStderr() async throws {
        let recorder = Recorder()
        let fake = FakeExec { request in
            await recorder.add(request)
            return ExecResult(stdout: "", stderr: "bad thing\n", exit: 3)
        }
        let runner = WorkflowRunner(exec: fake, history: nil)
        let flow = workflow([exec("first", 0, [text("/bin/false")]), exec("second", 1, [text("/bin/echo")])])
        await #expect(throws: RPCError("workflow", "first failed: exited with code 3: bad thing")) {
            try await runner.start(flow, input: "", settings: [:])
        }
        #expect(await recorder.requests.count == 1)
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .failed)
        #expect(run.error == "exited with code 3")
        #expect(run.steps.map(\.state) == [.failed, .pending])
        #expect(run.steps[0].exit == 3)
        #expect(await runner.snapshot().details[run.id] == "bad thing")
    }

    @Test func continueGivesTheNextStepAnEmptyOutputAndTheRealExit() async throws {
        let fake = FakeExec { request in
            request.argv[0] == "/bin/false" ? ExecResult(stdout: "ignored", stderr: "oops", exit: 2) : ExecResult(stdout: "fine")
        }
        let runner = WorkflowRunner(exec: fake, history: nil)
        let summary = Template(parts: [.text("["), .value(ValueReference(name: "first", field: "output")), .text("] "),
                                       .value(ValueReference(name: "first", field: "exit")), .text(" "),
                                       .value(ValueReference(name: "first", field: "stderr"))])
        let flow = workflow([exec("first", 0, [text("/bin/false")], onError: .continue), show(1, summary)])
        let outcome = try await runner.start(flow, input: "", settings: [:])
        #expect(outcome == .finished(notification: "[] 2 oops"))
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .finished)
        #expect(run.steps.map(\.state) == [.failed, .done])
    }

    @Test func showStepsBecomeTheNotificationAndOutputIsTrimmed() async throws {
        let recorder = Recorder()
        let fake = FakeExec { request in
            await recorder.add(request)
            return ExecResult(stdout: "hello world \n\n")
        }
        let runner = WorkflowRunner(exec: fake, history: nil, environment: ["PATH": "/usr/bin:/bin"])
        let flow = workflow([exec("say", 0, [text("/bin/echo"), ref("input")]),
                             show(1, Template(parts: [.text("Said: "), .value(ValueReference(name: "say", field: "output"))])),
                             show(2, text("Done"))])
        let outcome = try await runner.start(flow, input: "a b", settings: ["path": .string(" /opt/tools ")])
        #expect(outcome == .finished(notification: "Said: hello world\nDone"))
        let request = try #require(await recorder.requests.first)
        #expect(request.argv == ["/bin/echo", "a b"])
        #expect(request.cwd == NSTemporaryDirectory().trimmingSuffix("/"))
        #expect(request.environment["PATH"] == "/opt/tools:/usr/bin:/bin")
    }

    @Test func aRunWithoutShowStepsCountsItsSteps() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let outcome = try await runner.start(workflow([exec(nil, 0, [text("/bin/true")]), exec(nil, 1, [text("/bin/true")])]),
                                             input: "", settings: [:])
        #expect(outcome == .finished(notification: "Finished 2 steps."))
    }

    @Test func aMissingCommandAndARenderErrorFailTheStep() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil, environment: ["PATH": ""])
        await #expect(throws: RPCError("workflow", "step 1 failed: Command not found: no-such-tool-xyz")) {
            try await runner.start(workflow([exec(nil, 0, [text("no-such-tool-xyz")])]), input: "", settings: ["path": .string("")])
        }
        await #expect(throws: RPCError.self) {
            try await runner.start(workflow([show(0, ref("missing", "title"))]), input: "", settings: [:])
        }
        #expect(await runner.snapshot().runs.allSatisfy { $0.state == .failed })
    }

    @Test func aSubstitutedTildeIsNeverExpanded() async throws {
        let recorder = Recorder()
        let runner = WorkflowRunner(exec: FakeExec { request in
            await recorder.add(request)
            return ExecResult()
        }, history: nil)
        let value = WorkflowStep(id: "a", position: 0, kind: .show(ShowStep(text: text("~/x"))))
        _ = try await runner.start(workflow([value, exec(nil, 1, [ref("a", "output")])]), input: "", settings: [:])
        let request = try #require(await recorder.requests.first)
        #expect(request.argv == ["~/x"])
        #expect(request.executable.hasSuffix("/~/x"))
        let cwd = WorkflowStep(position: 1, kind: .exec(ExecStep(argv: [text("/bin/echo")], cwd: ref("a", "output"))))
        await #expect(throws: RPCError("workflow", "step 2 failed: cwd must be an absolute path.")) {
            try await runner.start(workflow([value, cwd]), input: "", settings: [:])
        }
    }

    @Test func llmAndConfirmStepsAreNotAvailableYet() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let llm = WorkflowStep(id: "draft", position: 0, kind: .llm(LLMStep(provider: .gateway, model: "m", prompt: text("p"))))
        await #expect(throws: RPCError("workflow", "draft failed: llm steps are not available in this build yet.")) {
            try await runner.start(workflow([llm]), input: "", settings: [:])
        }
        let confirm = WorkflowStep(id: "review", position: 0, kind: .confirm(ConfirmStep(text: text("t"))))
        await #expect(throws: RPCError("workflow", "review failed: confirm steps are not available in this build yet.")) {
            try await runner.start(workflow([confirm]), input: "", settings: [:])
        }
    }

    @Test func cancelByRunIDKillsTheStepAndRecordsCancelled() async throws {
        let runner = WorkflowRunner(exec: waitsForCancel, history: nil)
        let started = Task { try await runner.start(workflow([exec("wait", 0, [text("/bin/sleep")])]), input: "", settings: [:]) }
        #expect(await eventually { await runner.snapshot().runs.first?.steps.first?.state == .running })
        let id = try #require(await runner.snapshot().runs.first?.id)
        try await runner.cancel(id)
        await #expect(throws: CancellationError.self) { try await started.value }
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .cancelled)
        #expect(run.steps.first?.state == .cancelled)
        await #expect(throws: RPCError("workflow", "This run is not running.")) { try await runner.cancel(id) }
    }

    @Test func cancellingTheAwaitingTaskCancelsTheRun() async throws {
        let runner = WorkflowRunner(exec: waitsForCancel, history: nil)
        let started = Task { try await runner.start(workflow([exec("wait", 0, [text("/bin/sleep")])]), input: "", settings: [:]) }
        #expect(await eventually { await runner.snapshot().runs.first?.steps.first?.state == .running })
        started.cancel()
        await #expect(throws: CancellationError.self) { try await started.value }
        #expect(await runner.snapshot().runs.first?.state == .cancelled)
    }

    @Test func aStepTimeoutFailsTheStep() async throws {
        let runner = WorkflowRunner(exec: waitsForCancel, history: nil)
        let flow = workflow([exec("wait", 0, [text("/bin/sleep")], timeout: .milliseconds(100))])
        let clock = ContinuousClock()
        let began = clock.now
        await #expect(throws: RPCError("workflow", "wait failed: timed out after 0.1 s")) {
            try await runner.start(flow, input: "", settings: [:])
        }
        #expect(clock.now - began < .seconds(5))
        #expect(await runner.snapshot().runs.first?.steps.first?.state == .failed)
    }

    @Test func twoRunsOfTheSameWorkflowCanRunTogether() async throws {
        let runner = WorkflowRunner(exec: waitsForCancel, history: nil)
        let flow = workflow([exec("wait", 0, [text("/bin/sleep")])])
        let first = Task { try await runner.start(flow, input: "", settings: [:]) }
        let second = Task { try await runner.start(flow, input: "", settings: [:]) }
        #expect(await eventually { await runner.snapshot().runs.filter { $0.steps.first?.state == .running }.count == 2 })
        first.cancel(); second.cancel()
        _ = await first.result; _ = await second.result
        #expect(await runner.snapshot().runs.map(\.state) == [.cancelled, .cancelled])
    }

    @Test func historyHoldsMetadataOnlyWithPrivateMode() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("runs.json")
        let fake = FakeExec { _ in ExecResult(stdout: "secret-stdout-text", stderr: "secret-stderr-text", exit: 1) }
        let runner = WorkflowRunner(exec: fake, history: file)
        let flow = workflow([exec("say", 0, [text("/bin/echo"), ref("input")], onError: .continue),
                             show(1, text("secret-show-text"))])
        _ = try await runner.start(flow, input: "secret-input-text", settings: [:])
        let stored = try String(contentsOf: file, encoding: .utf8)
        for secret in ["secret-stdout-text", "secret-stderr-text", "secret-input-text", "secret-show-text"] {
            #expect(!stored.contains(secret))
        }
        #expect(stored.contains("exited with code 1"))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func aRunningRunBecomesInterruptedAfterAReload() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("runs.json")
        let first = WorkflowRunner(exec: waitsForCancel, history: file)
        let started = Task { try await first.start(workflow([exec("wait", 0, [text("/bin/sleep")])]), input: "", settings: [:]) }
        #expect(await eventually { await first.snapshot().runs.first?.steps.first?.state == .running })
        let second = WorkflowRunner(exec: waitsForCancel, history: file)
        await second.load()
        let run = try #require(await second.snapshot().runs.first)
        #expect(run.state == .interrupted)
        #expect(run.steps.first?.state == .cancelled)
        #expect(RunHistory.load(from: file).first?.state == .interrupted)
        started.cancel()
        _ = await started.result
    }

    @Test func shutdownStopsRunsAsInterrupted() async throws {
        let runner = WorkflowRunner(exec: waitsForCancel, history: nil)
        let started = Task { try await runner.start(workflow([exec("wait", 0, [text("/bin/sleep")])]), input: "", settings: [:]) }
        #expect(await eventually { await runner.snapshot().runs.first?.steps.first?.state == .running })
        await runner.shutdown()
        await #expect(throws: CancellationError.self) { try await started.value }
        #expect(await runner.snapshot().runs.first?.state == .interrupted)
    }

    @Test func historyKeepsTheNewestThirtyRuns() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let runs = (0..<40).map { index in
            RunRecord(id: "\(index)", workflowID: "w", workflowTitle: "W", state: .finished,
                      started: base.addingTimeInterval(Double(index)), steps: [])
        }
        let kept = RunHistory.trimmed(runs)
        #expect(kept.count == 30)
        #expect(kept.first?.id == "39")
        #expect(kept.last?.id == "10")
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
