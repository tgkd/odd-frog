import Foundation
import OddFrogPluginAPI

public actor DiceHandler: ProviderHandler {
    public init() {}

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return .object(["apiVersion": .number(2)])
        case "settings":
            return .object([:])
        case "query":
            let input = try params["input"].decode(PluginQuery.self)
            return try .encode(DiceProvider.respond(to: input.query) { Int.random(in: 1...$0) })
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }
}
