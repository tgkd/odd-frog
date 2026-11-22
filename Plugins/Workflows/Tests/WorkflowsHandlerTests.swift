import Foundation
import Testing
import OddFrogPluginAPI
import WorkflowsPluginCore

struct WorkflowsHandlerTests {
    @Test func withoutFoldersTheQueryShowsTheSetupRow() async throws {
        let handler = WorkflowsHandler()
        let operation = ProviderOperation(id: "test", service: { _, _ in .null }, emit: { _, _ in })
        let params: JSONValue = .object([
            "apiVersion": .number(2),
            "context": try .encode(PluginContext()),
            "input": try .encode(PluginQuery(query: "", fullQuery: "wf")),
        ])
        let rows = try await handler.handle("query", params: params, operation: operation).decode([PluginItem].self)
        #expect(rows.first?.id == "setup")
    }
}
