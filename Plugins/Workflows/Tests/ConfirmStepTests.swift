import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

actor Seen {
    private(set) var argv: [[String]] = []
    private(set) var bodies: [String] = []
    private(set) var modes: [Int] = []
    private(set) var cancelled = false
    func add(_ request: ExecRequest) {
        argv.append(request.argv)
        if let path = request.argv.last, FileManager.default.fileExists(atPath: path) {
            bodies.append((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            let mode = try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
            modes.append(mode ?? -1)
        }
    }
    func markCancelled() { cancelled = true }
}

func confirm(_ id: String, _ position: Int, _ template: Template, title: Template? = nil,
             editable: Bool = true) -> WorkflowStep {
    WorkflowStep(id: id, position: position, kind: .confirm(ConfirmStep(text: template, title: title, editable: editable)))
}

struct ConfirmStepTests {
    private func paused(_ outcome: RunOutcome) throws -> Review {
        guard case .paused(let review) = outcome else {
            Issue.record("Expected a paused outcome, got \(outcome)")
            throw CancellationError()
        }
        return review
    }

    @Test func theRunPausesAtConfirmWithTitleAndText() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult(stdout: "Fix the bug\n\nIt crashes.\n") }, history: nil)
        let flow = workflow([exec("draft", 0, [text("/bin/echo")]), confirm("review", 1, ref("draft", "output"))])
        let review = try paused(try await runner.start(flow, input: "", settings: [:]))
        #expect(review.step == 1)
        #expect(review.title == "Sample")
        #expect(review.text == "Fix the bug\n\nIt crashes.")
        #expect(review.editable)
        #expect(review.viewID == "\(review.runID)-1")
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .paused)
        #expect(run.steps.map(\.state) == [.done, .running])
        let titled = workflow([confirm("review", 0, text("t"), title: Template(parts: [.text("Post "), .value(ValueReference(name: "input"))]))])
        let custom = try paused(try await runner.start(titled, input: "it", settings: [:]))
        #expect(custom.title == "Post it")
        let blank = workflow([confirm("review", 0, text("t"), title: text("  "))])
        let fallback = try paused(try await runner.start(blank, input: "", settings: [:]))
        #expect(fallback.title == "Sample")
    }

    @Test func submitSplitsTitleAndBodyIntoValuesAndAPrivateFile() async throws {
        let seen = Seen()
        let runner = WorkflowRunner(exec: FakeExec { request in
            await seen.add(request)
            return ExecResult()
        }, history: nil)
        let flow = workflow([confirm("review", 0, text("draft")),
                             exec("post", 1, [text("/bin/echo"), ref("review", "title"), ref("review", "file")]),
                             show(2, ref("review", "body"))])
        let review = try paused(try await runner.start(flow, input: "", settings: [:]))
        let outcome = try await runner.submit(review.runID, text: "\n  New title  \n\n\nline one\n\n  line two\n\n",
                                              settings: [:])
        #expect(outcome == .finished(notification: "line one\n\n  line two"))
        let argv = try #require(await seen.argv.first)
        #expect(argv.count == 3)
        #expect(argv[1] == "New title")
        let path = argv[2]
        #expect(path == runner.reviewFolder.appendingPathComponent("\(review.runID)-0.txt").path)
        #expect(await seen.bodies == ["line one\n\n  line two"])
        #expect(await seen.modes == [0o600])
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(await runner.snapshot().runs.first?.steps.map(\.state) == [.done, .done, .done])
    }

    @Test func aNonEditableConfirmIgnoresTheSubmittedText() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let flow = workflow([confirm("review", 0, text("Rendered\nbody"), editable: false), show(1, ref("review", "title"))])
        let review = try paused(try await runner.start(flow, input: "", settings: [:]))
        #expect(!review.editable)
        await runner.saveDraft(review.runID, text: "Changed")
        #expect(try await runner.review(review.runID).text == "Rendered\nbody")
        let outcome = try await runner.submit(review.runID, text: "Other\ntext", settings: [:])
        #expect(outcome == .finished(notification: "Rendered"))
    }

    @Test func aSavedDraftComesBackFromContinue() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let review = try paused(try await runner.start(workflow([confirm("review", 0, text("first"))]), input: "", settings: [:]))
        await runner.saveDraft(review.runID, text: "second draft")
        let again = try await runner.review(review.runID)
        #expect(again.text == "second draft")
        #expect(again.viewID == review.viewID)
    }

    @Test func aSecondConfirmPausesAgainWithANewViewID() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let flow = workflow([confirm("one", 0, text("first")), confirm("two", 1, ref("one", "file"))])
        let first = try paused(try await runner.start(flow, input: "", settings: [:]))
        let second = try paused(try await runner.submit(first.runID, text: "Title\nbody", settings: [:]))
        #expect(second.runID == first.runID)
        #expect(second.step == 1)
        #expect(second.viewID != first.viewID)
        #expect(FileManager.default.fileExists(atPath: second.text))
        #expect(await runner.snapshot().runs.first?.state == .paused)
        _ = try await runner.submit(second.runID, text: "Done", settings: [:])
        #expect(!FileManager.default.fileExists(atPath: second.text))
    }

    @Test func cancellingAPausedRunCancelsItAndDeletesItsFiles() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let flow = workflow([confirm("one", 0, text("first")), confirm("two", 1, ref("one", "file"))])
        let first = try paused(try await runner.start(flow, input: "", settings: [:]))
        let second = try paused(try await runner.submit(first.runID, text: "Title\nbody", settings: [:]))
        #expect(FileManager.default.fileExists(atPath: second.text))
        try await runner.cancel(second.runID)
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .cancelled)
        #expect(run.steps.map(\.state) == [.done, .cancelled])
        #expect(!FileManager.default.fileExists(atPath: second.text))
        await #expect(throws: RPCError("workflow", "This run is not waiting for review.")) {
            try await runner.submit(second.runID, text: "x", settings: [:])
        }
        await runner.saveDraft(second.runID, text: "late")
    }

    @Test func submitWhenNotPausedThrows() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        await #expect(throws: RPCError("workflow", "This run is not waiting for review.")) {
            try await runner.submit("nope", text: "x", settings: [:])
        }
        await #expect(throws: RPCError("workflow", "This run is not waiting for review.")) {
            try await runner.review("nope")
        }
        await runner.saveDraft("nope", text: "x")
    }

    @Test func cancellingTheSubmitTaskKillsTheResumedExec() async throws {
        let seen = Seen()
        let runner = WorkflowRunner(exec: FakeExec { _ in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await seen.markCancelled()
                throw error
            }
            return ExecResult()
        }, history: nil)
        let flow = workflow([confirm("review", 0, text("draft")), exec("wait", 1, [text("/bin/sleep"), ref("review", "file")])])
        let review = try paused(try await runner.start(flow, input: "", settings: [:]))
        let submitted = Task { try await runner.submit(review.runID, text: "Title\nbody", settings: [:]) }
        #expect(await eventually { await runner.snapshot().runs.first?.steps.last?.state == .running })
        let path = runner.reviewFolder.appendingPathComponent("\(review.runID)-0.txt").path
        #expect(FileManager.default.fileExists(atPath: path))
        submitted.cancel()
        await #expect(throws: CancellationError.self) { try await submitted.value }
        #expect(await seen.cancelled)
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .cancelled)
        #expect(run.steps.map(\.state) == [.done, .cancelled])
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func anEmptyReviewedTextFailsTheStep() async throws {
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: nil)
        let review = try paused(try await runner.start(workflow([confirm("review", 0, text("draft"))]), input: "", settings: [:]))
        await #expect(throws: RPCError("workflow", "review failed: The reviewed text is empty.")) {
            try await runner.submit(review.runID, text: "  \n\t\n", settings: [:])
        }
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .failed)
        #expect(run.steps.first?.state == .failed)
        #expect(run.error == "The reviewed text is empty.")
    }

    @Test func runHistoryHoldsNoReviewText() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("runs.json")
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: file)
        let flow = workflow([confirm("review", 0, text("secret-rendered-text"), title: text("secret-window-title")),
                             confirm("again", 1, ref("review", "body"))])
        let review = try paused(try await runner.start(flow, input: "", settings: [:]))
        await runner.saveDraft(review.runID, text: "secret-draft-text")
        let second = try paused(try await runner.submit(review.runID, text: "secret-title-text\nsecret-body-text",
                                                        settings: [:]))
        #expect(second.text == "secret-body-text")
        #expect(runner.reviewFolder == folder.appendingPathComponent("review", isDirectory: true))
        let stored = try String(contentsOf: file, encoding: .utf8)
        for secret in ["secret-rendered-text", "secret-window-title", "secret-draft-text", "secret-title-text",
                       "secret-body-text"] {
            #expect(!stored.contains(secret))
        }
        #expect(RunHistory.load(from: file).first?.state == .paused)
        await runner.shutdown()
    }

    @Test func shutdownDeletesTheReviewFiles() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: folder.appendingPathComponent("runs.json"))
        let flow = workflow([confirm("one", 0, text("first")), confirm("two", 1, ref("one", "file"))])
        let first = try paused(try await runner.start(flow, input: "", settings: [:]))
        let second = try paused(try await runner.submit(first.runID, text: "Title\nbody", settings: [:]))
        #expect(FileManager.default.fileExists(atPath: second.text))
        await runner.shutdown()
        #expect(!FileManager.default.fileExists(atPath: runner.reviewFolder.path))
        let run = try #require(await runner.snapshot().runs.first)
        #expect(run.state == .interrupted)
        #expect(run.steps.map(\.state) == [.done, .cancelled])
    }

    @Test func loadDeletesALeftoverReviewFolder() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let review = folder.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        try "left".write(to: review.appendingPathComponent("old-0.txt"), atomically: true, encoding: .utf8)
        let runner = WorkflowRunner(exec: FakeExec { _ in ExecResult() }, history: folder.appendingPathComponent("runs.json"))
        await runner.load()
        #expect(!FileManager.default.fileExists(atPath: review.path))
    }
}
