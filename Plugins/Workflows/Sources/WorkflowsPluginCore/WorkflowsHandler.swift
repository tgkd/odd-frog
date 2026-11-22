import Foundation
import OddFrogPluginAPI

public actor WorkflowsHandler: ProviderHandler {
    public init() {}

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize", "settings":
            return .object(["apiVersion": .number(2)])
        case "catalog":
            return .array([])
        case "query":
            return try .encode([PluginItem(id: "setup", title: "Choose a workflow folder",
                                           subtitle: "Settings › Plugins › Workflows", kind: "Workflow")])
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }
}
