import Foundation

/// Convenience SDK only: other languages implement the same envelopes and methods.
public actor ProviderServer {
    public typealias Handler = @Sendable (String, JSONValue, ProviderOperation) async throws -> JSONValue
    private let channel: NDJSONChannel
    private let handler: Handler
    private let provider: (any ProviderHandler)?
    private let oneShot: Bool
    private var operations: [String: Task<Void, Never>] = [:]
    private var services: [String: CheckedContinuation<JSONValue, any Error>] = [:]
    private var retiredServices = Set<String>()
    private var stopping = false
    public init(oneShot: Bool = false, handler: @escaping Handler) {
        signal(SIGPIPE, SIG_IGN)
        channel = NDJSONChannel(input: .standardInput, output: .standardOutput)
        self.oneShot = oneShot; self.handler = handler; provider = nil
    }
    public init(oneShot: Bool = false, provider: any ProviderHandler) {
        signal(SIGPIPE, SIG_IGN)
        channel = NDJSONChannel(input: .standardInput, output: .standardOutput)
        self.oneShot = oneShot
        self.provider = provider
        handler = { method, params, operation in
            try await provider.handle(method, params: params, operation: operation)
        }
    }
    public func run() async throws {
        if let provider {
            await provider.start(emit: { [weak self] method in
                try? await self?.emit(method)
            })
        }
        do {
            try await consume()
        } catch {
            await provider?.shutdown()
            throw error
        }
        await provider?.shutdown()
    }
    private func consume() async throws {
        for try await message in channel.messages {
            if let method = message.method {
                if method == "shutdown" { break }
                if method == "cancel", let id = message.params?["requestID"].string { operations[id]?.cancel(); continue }
                guard let id = message.id, operations[id] == nil else { throw RPCError("protocol", "Invalid provider request.") }
                let operation = ProviderOperation(
                    id: id,
                    service: { [weak self] capability, params in
                        guard let self else { throw RPCError("protocol", "Provider stopped.") }
                        return try await self.service(capability, params: params, owner: id)
                    },
                    emit: { [weak self] method in
                        try await self?.emit(method)
                    }
                )
                operations[id] = Task {
                    do {
                        let result = try await handler(method, message.params ?? .object([:]), operation)
                        try Task.checkCancellation()
                        finish(id, result: result, error: nil)
                    } catch {
                        finish(id, result: nil, error: error as? RPCError ?? RPCError("operation", String(describing: error)))
                    }
                }
            } else if let id = message.id, let continuation = services.removeValue(forKey: id) {
                if let error = message.error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: message.result ?? .null) }
            } else if let id = message.id, retiredServices.contains(id) { continue }
            else { throw RPCError("protocol", "Uncorrelated host response.") }
            if stopping { break }
        }
        for task in operations.values { task.cancel() }
        for continuation in services.values { continuation.resume(throwing: CancellationError()) }
        services.removeAll(); channel.close()
    }
    private func finish(_ id: String, result: JSONValue?, error: RPCError?) {
        operations.removeValue(forKey: id)
        try? channel.send(PluginEnvelope(id: id, result: result, error: error))
        if oneShot { stopping = true; channel.close() }
    }
    public func emit(_ method: String) throws { try channel.send(PluginEnvelope(method: method, params: .object([:]))) }
    private func service(_ capability: String, params: JSONValue, owner: String) async throws -> JSONValue {
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                services[id] = continuation
                do { try channel.send(PluginEnvelope(id: id, method: "host.service", params: .object([
                    "requestID": .string(owner), "capability": .string(capability), "params": params
                ]))) } catch { services.removeValue(forKey: id)?.resume(throwing: error) }
            }
        } onCancel: { Task { await self.cancelService(id) } }
    }
    private func cancelService(_ id: String) {
        if retiredServices.count > 1024 { retiredServices.removeAll() }; retiredServices.insert(id)
        services.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
public struct ProviderOperation: Sendable {
    public typealias Service = @Sendable (String, JSONValue) async throws -> JSONValue
    public typealias Emit = @Sendable (String) async throws -> Void
    public let id: String
    private let services: Service
    private let events: Emit
    public init(id: String, service: @escaping Service, emit: @escaping Emit) {
        self.id = id
        services = service
        events = emit
    }
    public func service(_ capability: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        try await services(capability, params)
    }
    public func emit(_ method: String) async throws {
        try await events(method)
    }
}
