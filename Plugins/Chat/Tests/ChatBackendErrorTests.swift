import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (status: Int, contentType: String, body: String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.responses[url.host ?? ""] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": stub.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ChatBackendErrorTests {
    private let local = URL(string: "http://localhost:11434/v1")
    private let bare = URL(string: "http://localhost:1234")

    private func backend() -> OpenAICompatibleBackend {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return OpenAICompatibleBackend(session: URLSession(configuration: configuration))
    }

    private func request(_ base: String) -> ChatRequest {
        ChatRequest(baseURL: URL(string: base), apiKey: "", model: "m", systemPrompt: "",
                    messages: [PluginMessage(id: "m0", role: .user, text: "ping")])
    }

    @Test func connectionFailuresNameTheServerInPlainWords() {
        #expect(ChatBackendError.connection(URLError(.cannotConnectToHost), baseURL: local).message
                == "Could not connect to the server at localhost:11434. Start the server, or check the API base URL in Chat settings.")
        #expect(ChatBackendError.connection(URLError(.timedOut), baseURL: local).message == "The server at localhost:11434 did not answer in time.")
        #expect(ChatBackendError.connection(URLError(.notConnectedToInternet), baseURL: nil).message == "No internet connection.")
        #expect(ChatBackendError.connection(URLError(.cannotConnectToHost), baseURL: nil).message.hasPrefix("Could not connect to the server."))
    }

    @Test func statusCodesExplainTheLikelyCause() {
        #expect(ChatBackendError.status(401, baseURL: local, body: "").message
                == "The server at localhost:11434 rejected the API key (HTTP 401). Check the API key in Chat settings.")
        #expect(ChatBackendError.status(404, baseURL: bare, body: "").message
                == "The server at localhost:1234 has no chat endpoint at this address (HTTP 404). Check that the API base URL ends with /v1.")
        #expect(ChatBackendError.status(404, baseURL: local, body: "").message
                == "The server at localhost:11434 has no chat endpoint at this address (HTTP 404).")
        #expect(ChatBackendError.status(500, baseURL: local, body: #"{"error":{"message":"model not loaded"}}"#).message
                == "The server at localhost:11434 answered HTTP 500: model not loaded")
        #expect(ChatBackendError.status(502, baseURL: local, body: "").message == "The server at localhost:11434 answered HTTP 502.")
    }

    @Test func serverMessagesFromAnyErrorShapeAreFound() {
        #expect(ChatBackendError.message(inBody: #"{"error":"Unexpected endpoint"}"#) == "Unexpected endpoint")
        #expect(ChatBackendError.message(inBody: #"{"error":{"message":"bad model"}}"#) == "bad model")
        #expect(ChatBackendError.message(inBody: #"{"message":"busy"}"#) == "busy")
        #expect(ChatBackendError.message(inBody: "not json") == nil)
    }

    @Test func aRefusedConnectionReachesTheCallerAsAPlainMessage() async {
        StubProtocol.responses = [:]
        await #expect(throws: RPCError("chat", "Could not connect to the server at localhost:11434. Start the server, or check the API base URL in Chat settings.")) {
            _ = try await backend().stream(request("http://localhost:11434/v1"), tools: nil)
        }
    }

    @Test func aJSONErrorWithStatus200IsNotSwallowed() async {
        StubProtocol.responses = ["localhost": (200, "application/json",
                                                #"{"error":"Unexpected endpoint or method. (POST /chat/completions)"}"#)]
        await #expect(throws: RPCError("chat", "The server at localhost:1234 says: Unexpected endpoint or method. (POST /chat/completions) Check that the API base URL ends with /v1.")) {
            _ = try await backend().stream(request("http://localhost:1234"), tools: nil)
        }
    }
}
