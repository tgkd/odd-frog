import Foundation

public protocol ProviderHandler: Sendable {
    func start(emit: @escaping @Sendable (String) async -> Void) async
    func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue
    func shutdown() async
}

public extension ProviderHandler {
    func start(emit: @escaping @Sendable (String) async -> Void) async {}
    func shutdown() async {}
}
