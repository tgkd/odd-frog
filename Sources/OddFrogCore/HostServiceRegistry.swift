import Foundation
import OddFrogPluginAPI

@MainActor public final class HostServiceRegistry {
    public struct Context: Sendable {
        public var pluginID: String
        public var generation: UUID
        public var activated: Bool
    }
    public typealias Handler = @MainActor @Sendable (JSONValue, Context) async throws -> JSONValue
    private struct Service { var activationRequired: Bool; var handler: Handler }
    public var onInvalidation: ((Context) -> Void)?
    private var subscriptions: [String: [UUID: [String: Context]]] = [:]
    private var revoked = Set<UUID>()
    public var subscriptionCount: Int { subscriptions.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }
    public func subscribe(_ context: Context, to topic: String) {
        guard !revoked.contains(context.generation) else { return }
        subscriptions[topic, default: [:]][context.generation, default: [:]][context.pluginID] = context
    }
    public func invalidate(_ topic: String) {
        for contexts in subscriptions[topic]?.values ?? [:].values { for context in contexts.values { onInvalidation?(context) } }
    }
    public func cancelSubscriptions(generation: UUID) {
        revoked.insert(generation)
        for topic in Array(subscriptions.keys) { subscriptions[topic]?[generation] = nil }
    }
    private var services: [String: Service] = [:]
    public init() {}
    public var capabilities: Set<String> { Set(services.keys) }
    public func register(_ capability: String, activationRequired: Bool = false, handler: @escaping Handler) {
        services[capability] = Service(activationRequired: activationRequired, handler: handler)
    }
    public func invoke(_ capability: String, params: JSONValue, context: Context, declared: [String]) async throws -> JSONValue {
        guard declared.contains(capability), let service = services[capability] else {
            throw RPCError("capability", "Undeclared or unsupported capability '\(capability)'.")
        }
        guard context.activated || !service.activationRequired else {
            throw RPCError("activation", "'\(capability)' requires user activation.")
        }
        guard !revoked.contains(context.generation) else { throw CancellationError() }
        try Task.checkCancellation()
        let result = try await service.handler(params, context)
        try Task.checkCancellation()
        return result
    }
}
