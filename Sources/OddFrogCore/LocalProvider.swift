import Foundation
import OddFrogPluginAPI

public actor LocalProvider: ProviderTransport {
    private let handler: any ProviderHandler
    private let event: PluginProcess.Event
    private var started = false
    private var stopped = false
    public init(handler: any ProviderHandler, event: @escaping PluginProcess.Event = { _, _ in }) {
        self.handler = handler
        self.event = event
    }
    public func request(_ method: String, params: JSONValue = .object([:]), timeout: Duration? = nil,
                        service: @escaping PluginProcess.Service = { _, _ in throw RPCError("capability", "No services declared.") }) async throws -> JSONValue {
        try Task.checkCancellation()
        guard !stopped else {
            throw RPCError("protocol", "Provider stopped.")
        }
        let emit = forwarder()
        if !started {
            started = true
            await handler.start(emit: emit)
        }
        let operation = ProviderOperation(id: UUID().uuidString, service: service) { method in
            await emit(method)
        }
        return try await handler.handle(method, params: params, operation: operation)
    }
    public func stop() {
        guard !stopped else {
            return
        }
        stopped = true
        let handler = self.handler
        Task.detached {
            await handler.shutdown()
        }
    }
    private func forwarder() -> @Sendable (String) async -> Void {
        let event = self.event
        return { method in
            await event(method, .object([:]))
        }
    }
}
