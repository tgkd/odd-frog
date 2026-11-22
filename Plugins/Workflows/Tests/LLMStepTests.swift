import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

actor PromptLog {
    private(set) var prompts: [ModelPrompt] = []
    func add(_ prompt: ModelPrompt) { prompts.append(prompt) }
}

struct FakeModel: ModelCompleting {
    let log = PromptLog()
    let body: @Sendable (ModelPrompt) async throws -> String
    func complete(_ prompt: ModelPrompt, settings: [String: JSONValue]) async throws -> String {
        await log.add(prompt)
        return try await body(prompt)
    }
}

func replying(_ reply: String) -> FakeModel { FakeModel { _ in reply } }

func llm(_ id: String, _ position: Int, _ prompt: Template, context: [String] = [], output: StepOutput = .text,
         provider: LLMProvider = .gateway, timeout: Duration? = nil) -> WorkflowStep {
    WorkflowStep(id: id, position: position,
                 kind: .llm(LLMStep(provider: provider, model: "openai/gpt-6-luna", prompt: prompt, context: context, output: output)),
                 timeout: timeout)
}

struct LLMStepTests {
    private func runner(_ model: FakeModel, history: URL? = nil) -> WorkflowRunner {
        WorkflowRunner(exec: FakeExec { _ in ExecResult() }, model: model, history: history)
    }

    @Test func textOutputAndLastLineReachLaterSteps() async throws {
        let model = replying("first line\nsecond line  \n\n")
        let summary = Template(parts: [.value(ValueReference(name: "draft", field: "output")), .text("|"),
                                       .value(ValueReference(name: "draft", field: "last_line"))])
        let prompt = Template(parts: [.text("Idea: "), .value(ValueReference(name: "input"))])
        let flow = workflow([llm("draft", 0, prompt, provider: .ollama), show(1, summary)])
        let outcome = try await runner(model).start(flow, input: "cats", settings: [:])
        #expect(outcome == .finished(notification: "first line\nsecond line|second line"))
        let sent = try #require(await model.log.prompts.first)
        #expect(sent == ModelPrompt(provider: .ollama, model: "openai/gpt-6-luna", system: "", prompt: "Idea: cats", json: false))
    }

    @Test func jsonOutputGivesTopLevelFieldsAndAsksForJSON() async throws {
        let model = replying(#"{"title": "Fix it", "count": 3}"#)
        let flow = workflow([llm("draft", 0, text("p"), output: .json), show(1, ref("draft", "title"))])
        let outcome = try await runner(model).start(flow, input: "", settings: [:])
        #expect(outcome == .finished(notification: "Fix it"))
        let sent = try #require(await model.log.prompts.first)
        #expect(sent.json)
        #expect(sent.system == "Answer with one JSON object and nothing else.")
    }

    @Test func fencedJSONIsCleaned() async throws {
        let model = replying("\n```json\n{\"title\": \"Fenced\"}\n```\n")
        let flow = workflow([llm("draft", 0, text("p"), output: .json),
                             show(1, ref("draft", "title")), show(2, ref("draft", "output"))])
        let outcome = try await runner(model).start(flow, input: "", settings: [:])
        #expect(outcome == .finished(notification: "Fenced\n{\"title\": \"Fenced\"}"))
    }

    @Test func invalidJSONFailsWithTheRawTextOnlyInTheThrownMessage() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("runs.json")
        let runner = runner(replying("secret-model-text, not json"), history: file)
        await #expect(throws: RPCError("workflow", "draft failed: The model did not return a JSON object: secret-model-text, not json")) {
            try await runner.start(workflow([llm("draft", 0, text("p"), output: .json)]), input: "", settings: [:])
        }
        let stored = try String(contentsOf: file, encoding: .utf8)
        #expect(!stored.contains("secret-model-text"))
        #expect(stored.contains("The model did not return a JSON object."))
        let run = try #require(await runner.snapshot().runs.first)
        #expect(await runner.snapshot().details[run.id] == "secret-model-text, not json")
    }

    @Test func anEmptyReplyFailsTheStep() async throws {
        await #expect(throws: RPCError("workflow", "draft failed: The model returned no text.")) {
            try await runner(replying(" \n\t")).start(workflow([llm("draft", 0, text("p"))]), input: "", settings: [:])
        }
    }

    @Test func contextFilesGoInTheSystemPrompt() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("products.md")
        let second = folder.appendingPathComponent("rules.md")
        try "alpha\nbeta".write(to: first, atomically: true, encoding: .utf8)
        try "rule one".write(to: second, atomically: true, encoding: .utf8)
        let model = replying(#"{"a": "b"}"#)
        let flow = workflow([llm("draft", 0, text("p"), context: [first.path, second.path], output: .json)])
        _ = try await runner(model).start(flow, input: "", settings: [:])
        let sent = try #require(await model.log.prompts.first)
        #expect(sent.system == "Context file \(first.path):\nalpha\nbeta\n\nContext file \(second.path):\nrule one\n\n"
                + "Answer with one JSON object and nothing else.")
    }

    @Test func aMissingOrLargeContextFileFailsBeforeTheModelIsCalled() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent("missing.md").path
        let model = replying("never")
        await #expect(throws: RPCError("workflow", "draft failed: Cannot read context file \(missing).")) {
            try await runner(model).start(workflow([llm("draft", 0, text("p"), context: [missing])]), input: "", settings: [:])
        }
        let large = folder.appendingPathComponent("large.md")
        try Data(repeating: 0x61, count: 256 * 1024 + 1).write(to: large)
        await #expect(throws: RPCError("workflow", "draft failed: Context file \(large.path) is larger than 256 KiB.")) {
            try await runner(model).start(workflow([llm("draft", 0, text("p"), context: [large.path])]), input: "", settings: [:])
        }
        #expect(await model.log.prompts.isEmpty)
    }

    @Test func aModelErrorBecomesTheStepFailure() async throws {
        let model = FakeModel { _ in throw RPCError("chat", "Set the AI Gateway token in Settings › Plugins › Workflows.") }
        await #expect(throws: RPCError("workflow", "draft failed: Set the AI Gateway token in Settings › Plugins › Workflows.")) {
            try await runner(model).start(workflow([llm("draft", 0, text("p"))]), input: "", settings: [:])
        }
    }

    @Test func cancellingAWaitingModelCancelsTheRun() async throws {
        let model = FakeModel { _ in
            try await Task.sleep(for: .seconds(60))
            return "late"
        }
        let runner = runner(model)
        let started = Task { try await runner.start(workflow([llm("draft", 0, text("p"))]), input: "", settings: [:]) }
        #expect(await eventually { await runner.snapshot().runs.first?.steps.first?.state == .running })
        let id = try #require(await runner.snapshot().runs.first?.id)
        try await runner.cancel(id)
        await #expect(throws: CancellationError.self) { try await started.value }
        #expect(await runner.snapshot().runs.first?.state == .cancelled)
    }

    @Test func aWaitingModelTimesOut() async throws {
        let model = FakeModel { _ in
            try await Task.sleep(for: .seconds(60))
            return "late"
        }
        await #expect(throws: RPCError("workflow", "draft failed: timed out after 0.1 s")) {
            try await runner(model).start(workflow([llm("draft", 0, text("p"), timeout: .milliseconds(100))]),
                                          input: "", settings: [:])
        }
    }
}
