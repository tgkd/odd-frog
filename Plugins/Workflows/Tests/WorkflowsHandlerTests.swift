import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

actor Events {
    private(set) var names: [String] = []
    func add(_ name: String) { names.append(name) }
}

struct WorkflowsHandlerTests {
    private let operation = ProviderOperation(id: "test", service: { _, _ in .null }, emit: { _, _ in })

    private func params(_ context: PluginContext, _ input: some Encodable) throws -> JSONValue {
        .object(["apiVersion": .number(2), "context": try .encode(context), "input": try .encode(input)])
    }

    private func query(_ handler: WorkflowsHandler, _ context: PluginContext, _ text: String = "") async throws -> [PluginItem] {
        try await handler.handle("query", params: params(context, PluginQuery(query: text, fullQuery: "wf " + text)),
                                 operation: operation).decode([PluginItem].self)
    }

    private func activate(_ handler: WorkflowsHandler, _ context: PluginContext, _ action: String, payload: JSONValue,
                          argument: String? = nil, text: String? = nil) async throws -> PluginEffects {
        let activation = PluginActivation(actionID: action, payload: payload, item: PluginItem(id: "x", title: "x"),
                                          argument: argument, text: text)
        return try await handler.handle("activate", params: params(context, activation), operation: operation)
            .decode(PluginEffects.self)
    }

    @Test func withoutFoldersTheQueryShowsTheSetupRow() async throws {
        let handler = WorkflowsHandler()
        let rows = try await query(handler, PluginContext())
        #expect(rows.first?.id == "setup")
    }

    @Test func aWorkflowFileBecomesACatalogItemThatRuns() async throws {
        let created = try temporaryFolder()
        let folder = URL(fileURLWithPath: try #require(realpath(created.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }))
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("storage")
        let flows = folder.appendingPathComponent("flows")
        try FileManager.default.createDirectory(at: flows, withIntermediateDirectories: true)
        try """
        id = "hello"
        title = "Say hello"
        keyword = "hello"
        argument = { placeholder = "Name" }

        [[steps]]
        id = "say"
        kind = "exec"
        argv = ["/bin/echo", "hi {input}"]

        [[steps]]
        kind = "show"
        text = "Said {say.output}"
        """.write(to: flows.appendingPathComponent("hello.toml"), atomically: true, encoding: .utf8)
        try "not toml at all [".write(to: flows.appendingPathComponent("broken.toml"), atomically: true, encoding: .utf8)
        let context = PluginContext(settings: ["folders": .array([.string(flows.path)])], storagePath: storage.path)
        let events = Events()
        let handler = WorkflowsHandler(rescanInterval: .seconds(3600))
        await handler.start { name in await events.add(name) }
        _ = try await handler.handle("initialize", params: params(context, JSONValue.null), operation: operation)
        let items = try await handler.handle("catalog", params: params(context, JSONValue.null), operation: operation)
            .decode([PluginItem].self)
        #expect(items.map(\.id) == ["hello"])
        #expect(items.first?.aliases == ["hello"])
        #expect(items.first?.argument?.placeholder == "Name")
        #expect(items.first?.history == true)
        #expect(items.first?.primary == PluginAction(.callback, "run", payload: .object(["workflow": .string("hello")])))
        let before = try await query(handler, context)
        #expect(before.map(\.id) == ["error:" + flows.appendingPathComponent("broken.toml").path])
        let effects = try await activate(handler, context, "run", payload: .object(["workflow": .string("hello")]),
                                         argument: "Ann")
        #expect(effects.notification == "Said hi Ann")
        #expect(effects.refreshQuery)
        let after = try await query(handler, context, "say")
        #expect(after.first?.subtitle?.hasPrefix("Finished · say done · step 2 done · ") == true)
        #expect(await events.names.contains("queryInvalidated"))
        #expect(FileManager.default.fileExists(atPath: storage.appendingPathComponent("runs.json").path))
        await handler.shutdown()
    }

    @Test func aConfirmStepOpensTheEditorAndSubmitResumes() async throws {
        let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let flows = folder.appendingPathComponent("flows")
        try FileManager.default.createDirectory(at: flows, withIntermediateDirectories: true)
        try """
        id = "post"
        title = "Post it"
        keyword = "post"
        argument = { placeholder = "Text" }

        [[steps]]
        id = "review"
        kind = "confirm"
        text = "{input}"

        [[steps]]
        kind = "show"
        text = "Posted {review.title}"
        """.write(to: flows.appendingPathComponent("post.toml"), atomically: true, encoding: .utf8)
        let context = PluginContext(settings: ["folders": .array([.string(flows.path)])],
                                    storagePath: folder.appendingPathComponent("storage").path)
        let handler = WorkflowsHandler(rescanInterval: .seconds(3600))
        _ = try await handler.handle("initialize", params: params(context, JSONValue.null), operation: operation)
        let opened = try await activate(handler, context, "run", payload: .object(["workflow": .string("post")]),
                                        argument: "Hello\nworld")
        let view = try #require(opened.view)
        #expect(opened.notification == nil)
        #expect(opened.refreshQuery)
        #expect(view.kind == .editor)
        #expect(view.title == "Post it")
        #expect(view.text == "Hello\nworld")
        let runID = String(view.id.dropLast(2))
        #expect(view.id == runID + "-0")
        let payload: JSONValue = .object(["run": .string(runID)])
        #expect(view.save == PluginAction(.callback, "save", payload: payload))
        #expect(view.submit == PluginAction(.callback, "submit", payload: payload))
        let row = try #require(try await query(handler, context).first)
        #expect(row.id == runID)
        #expect(row.subtitle == "review review · step 2 waiting · Return continues the review")
        #expect(row.primary == PluginAction(.callback, "continue", payload: payload))
        let saved = try await activate(handler, context, "save", payload: payload, text: "Edited\nbody")
        #expect(saved.notification == nil && saved.view == nil)
        let continued = try await activate(handler, context, "continue", payload: payload)
        #expect(continued.view?.id == view.id)
        #expect(continued.view?.text == "Edited\nbody")
        let submitted = try await activate(handler, context, "submit", payload: payload, text: "Final\nbody")
        #expect(submitted.notification == "Posted Final")
        #expect(submitted.view == nil)
        await #expect(throws: RPCError("workflow", "This run is not waiting for review.")) {
            try await activate(handler, context, "continue", payload: payload)
        }
        await #expect(throws: RPCError("workflow", "This run is not waiting for review.")) {
            try await activate(handler, context, "submit", payload: payload, text: "again")
        }
        let late = try await activate(handler, context, "save", payload: payload, text: "late")
        #expect(late.notification == nil)
        let second = try await activate(handler, context, "run", payload: .object(["workflow": .string("post")]),
                                        argument: "Draft")
        let secondPayload: JSONValue = .object(["run": .string(String(try #require(second.view).id.dropLast(2)))])
        let cancelled = try await activate(handler, context, "cancel", payload: secondPayload)
        #expect(cancelled.notification == "Cancelled.")
        let afterCancel = try await activate(handler, context, "save", payload: secondPayload, text: "late")
        #expect(afterCancel.view == nil)
        await handler.shutdown()
    }

    @Test func cancellingAnUnknownRunThrows() async throws {
        let handler = WorkflowsHandler()
        _ = try await handler.handle("initialize", params: params(PluginContext(), JSONValue.null), operation: operation)
        await #expect(throws: RPCError("workflow", "This run is not running.")) {
            try await activate(handler, PluginContext(), "cancel", payload: .object(["run": .string("nope")]))
        }
        await handler.shutdown()
    }

    @Test func initializeAfterShutdownDoesNothing() async throws {
        let handler = WorkflowsHandler()
        await handler.shutdown()
        let ack = try await handler.handle("initialize", params: params(PluginContext(), JSONValue.null), operation: operation)
        #expect(ack["apiVersion"].number == 2)
        await #expect(throws: RPCError.self) {
            try await activate(handler, PluginContext(), "run", payload: .object(["workflow": .string("hello")]))
        }
    }
}

struct WorkflowRowsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func run(_ id: String, _ state: RunRecord.State, at offset: TimeInterval = 0, length: TimeInterval = 125,
                     steps: [RunRecord.Step], error: String? = nil) -> RunRecord {
        RunRecord(id: id, workflowID: "idea", workflowTitle: "New task", state: state,
                  started: start.addingTimeInterval(offset),
                  ended: state.isActive ? nil : start.addingTimeInterval(offset + length), steps: steps, error: error)
    }

    private func step(_ label: String, _ state: RunRecord.Step.State) -> RunRecord.Step {
        RunRecord.Step(label: label, kind: "exec", state: state)
    }

    @Test func eachStateHasItsRow() {
        let runs = [
            run("finished", .finished, at: 0, steps: [step("draft", .done), step("post", .done)]),
            run("running", .running, at: 10, steps: [step("draft", .done), step("post", .running), step("tell", .pending)]),
            run("failed", .failed, at: 20, steps: [step("draft", .failed)], error: "exited with code 2"),
            run("cancelled", .cancelled, at: 30, steps: [step("draft", .done), step("post", .cancelled)]),
            run("interrupted", .interrupted, at: 40, steps: [step("draft", .cancelled)]),
        ]
        let file = URL(fileURLWithPath: "/tmp/flows/bad.toml")
        let rows = WorkflowRows.rows(runs: runs, details: ["failed": "no token"],
                                     errors: [WorkflowFileError(file: file, message: "Line 2: bad key")],
                                     hasFolders: true, keywords: ["idea"], query: "", maxResults: 20)
        #expect(rows.map(\.id) == ["running", "interrupted", "cancelled", "failed", "finished", "error:/tmp/flows/bad.toml"])
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        #expect(byID["running"]?.subtitle == "draft done · post running · tell waiting · Return cancels")
        #expect(byID["running"]?.primary == PluginAction(.callback, "cancel", payload: .object(["run": .string("running")])))
        #expect(byID["running"]?.multiline == true)
        #expect(byID["finished"]?.subtitle == "Finished · draft done · post done · 2 min 5 s")
        #expect(byID["finished"]?.primary == nil)
        #expect(byID["failed"]?.title == "New task: draft failed")
        #expect(byID["failed"]?.subtitle == "exited with code 2: no token")
        #expect(byID["failed"]?.primary == PluginAction(.copy, "exited with code 2: no token"))
        #expect(byID["cancelled"]?.subtitle == "Cancelled at post")
        #expect(byID["interrupted"]?.subtitle == "Stopped at draft by a plugin reload or quit")
        #expect(byID["error:/tmp/flows/bad.toml"]?.title == "Cannot load bad.toml")
        #expect(byID["error:/tmp/flows/bad.toml"]?.primary == PluginAction(.reveal, "/tmp/flows/bad.toml"))
        #expect(rows.allSatisfy { $0.kind == "Workflow" })
    }

    @Test func aPausedRunOffersContinueAndCancel() throws {
        let paused = run("paused", .paused, steps: [step("draft", .done), step("review", .running), step("post", .pending)])
        let rows = WorkflowRows.rows(runs: [paused], errors: [], hasFolders: true, keywords: [], query: "", maxResults: 8)
        let row = try #require(rows.first)
        let payload: JSONValue = .object(["run": .string("paused")])
        #expect(row.subtitle == "draft done · review review · post waiting · Return continues the review")
        #expect(row.symbol == "pause.circle")
        #expect(row.primary == PluginAction(.callback, "continue", payload: payload))
        #expect(row.secondary == PluginAction(.callback, "cancel", payload: payload))
        #expect(row.multiline == true)
    }

    @Test func emptyAndSetupRows() {
        let setup = WorkflowRows.rows(runs: [], errors: [], hasFolders: false, keywords: [], query: "", maxResults: 8)
        #expect(setup.map(\.title) == ["Choose a workflow folder"])
        #expect(setup.first?.primary == nil)
        let empty = WorkflowRows.rows(runs: [], errors: [], hasFolders: true, keywords: ["idea", "ship"], query: "", maxResults: 8)
        #expect(empty.first?.id == "empty")
        #expect(empty.first?.subtitle == "Type a workflow keyword: idea, ship")
        let none = WorkflowRows.rows(runs: [], errors: [], hasFolders: true, keywords: [], query: "", maxResults: 8)
        #expect(none.first?.subtitle == "No workflows in the chosen folders.")
    }

    @Test func theQueryFiltersAndMaxResultsCaps() {
        let runs = (0..<5).map { run("\($0)", .finished, at: Double($0), steps: []) }
            + [RunRecord(id: "other", workflowID: "ship", workflowTitle: "Ship build", state: .finished, started: start,
                         ended: start, steps: [])]
        let filtered = WorkflowRows.rows(runs: runs, errors: [], hasFolders: true, keywords: [], query: "SHIP", maxResults: 8)
        #expect(filtered.map(\.id) == ["other"])
        let capped = WorkflowRows.rows(runs: runs, errors: [], hasFolders: true, keywords: [], query: "", maxResults: 3)
        #expect(capped.count == 3)
        #expect(WorkflowRows.rows(runs: runs, errors: [], hasFolders: false, keywords: [], query: "", maxResults: 8).last?.id == "setup")
    }
}
