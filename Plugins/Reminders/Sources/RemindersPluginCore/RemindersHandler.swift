import Foundation
import OddFrogPluginAPI
import OddFrogHostServicesAPI

public actor RemindersHandler: ProviderHandler {
    private var refresh: Task<Void, Never>?
    public init() {}
    public func start(emit: @escaping @Sendable (String) async -> Void) async {
        refresh?.cancel()
        refresh = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                await emit("queryInvalidated")
            }
        }
    }
    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return .object(["apiVersion": .number(2)])
        case "settings":
            return .object([:])
        case "query":
            let query = try params["input"].decode(PluginQuery.self)
            let snapshot = try await operation.service("reminders.read@1", params: .encode(RemindersScope(limit: 2000))).decode(RemindersSnapshot.self)
            return try .encode(RemindersProvider.respond(to: query, snapshot: snapshot))
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }
    public func shutdown() async {
        refresh?.cancel()
        refresh = nil
    }
}
