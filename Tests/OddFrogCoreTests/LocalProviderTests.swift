import Foundation
import Testing
import OddFrogPluginAPI
@testable import OddFrogCore

private actor EventLog {
    private(set) var events: [(method: String, params: JSONValue)] = []
    var methods: [String] { events.map(\.method) }
    func record(_ method: String, params: JSONValue) {
        events.append((method, params))
    }
}

private actor ProbeHandler: ProviderHandler {
    private(set) var starts = 0
    private(set) var shutdowns = 0
    private(set) var methods: [String] = []
    private var failure: RPCError?
    func fail(with error: RPCError) {
        failure = error
    }
    func start(emit: @escaping @Sendable (String) async -> Void) async {
        starts += 1
        await emit("catalogChanged")
    }
    func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        methods.append(method)
        if let failure {
            throw failure
        }
        switch method {
        case "service":
            return try await operation.service("cap@1", params: params)
        case "emit":
            try await operation.emit("queryInvalidated", params: .object(["n": .number(1)]))
            return .null
        default:
            return .object(["echo": params])
        }
    }
    func shutdown() async {
        shutdowns += 1
    }
}

struct LocalProviderTests {
    private func settle(_ condition: @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while await !condition() {
            guard ContinuousClock.now < deadline else { throw RPCError("test", "Timed out waiting for the local provider.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    @Test func requestForwardsMethodAndParamsAndReturnsTheHandlerResult() async throws {
        let handler = ProbeHandler()
        let provider = LocalProvider(handler: handler)
        let result = try await provider.request("query", params: .object(["q": .string("hi")]))
        #expect(result["echo"]["q"].string == "hi")
        #expect(await handler.methods == ["query"])
    }
    @Test func operationServiceReachesTheServiceClosureOfThatRequest() async throws {
        let handler = ProbeHandler()
        let provider = LocalProvider(handler: handler)
        let result = try await provider.request("service", params: .object(["n": .number(2)])) { capability, params in
            .object(["capability": .string(capability), "params": params])
        }
        #expect(result["capability"].string == "cap@1")
        #expect(result["params"]["n"].number == 2)
    }
    @Test func startAndOperationEmitReachTheEventCallback() async throws {
        let handler = ProbeHandler()
        let log = EventLog()
        let provider = LocalProvider(handler: handler) { method, params in
            await log.record(method, params: params)
        }
        _ = try await provider.request("emit")
        #expect(await log.methods == ["catalogChanged", "queryInvalidated"])
        #expect(await log.events.last?.params["n"].number == 1)
    }
    @Test func startRunsOnceAcrossSeveralRequests() async throws {
        let handler = ProbeHandler()
        let provider = LocalProvider(handler: handler)
        for _ in 0..<3 {
            _ = try await provider.request("initialize")
        }
        #expect(await handler.starts == 1)
        #expect(await handler.methods.count == 3)
    }
    @Test func stopShutsTheHandlerDownAndRefusesLaterRequests() async throws {
        let handler = ProbeHandler()
        let provider = LocalProvider(handler: handler)
        _ = try await provider.request("initialize")
        await provider.stop()
        await #expect(throws: RPCError.self) {
            _ = try await provider.request("initialize")
        }
        try await settle { await handler.shutdowns == 1 }
        #expect(await handler.methods == ["initialize"])
    }
    @Test func handlerErrorsSurfaceToTheCaller() async throws {
        let handler = ProbeHandler()
        await handler.fail(with: RPCError("query", "Nope."))
        let provider = LocalProvider(handler: handler)
        await #expect(throws: RPCError("query", "Nope.")) {
            _ = try await provider.request("query")
        }
    }
}
