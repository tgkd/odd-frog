import Foundation
import Testing
import LLMClient
import OddFrogPluginAPI
import WorkflowsPluginCore

actor RequestLog {
    private(set) var requests: [ChatRequest] = []
    func add(_ request: ChatRequest) { requests.append(request) }
}

struct FakeStream: ChatStreaming {
    let chunks: [String]
    let log: RequestLog
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error> {
        await log.add(request)
        let chunks = chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

struct ModelRouterTests {
    let gatewaySettings: [String: JSONValue] = [
        "gateway_url": .string(" https://gateway.ai.cloudflare.com/v1/acct/gw "),
        "gateway_token": .string(" gw-token\n"),
    ]

    @Test func gatewayRequestsUseTheCompatURLAndTheGatewayHeader() throws {
        let prompt = ModelPrompt(provider: .gateway, model: "openai/gpt-6-luna", system: "sys", prompt: "hello", json: true)
        let request = try ModelRouter.request(for: prompt, settings: gatewaySettings)
        #expect(request.baseURL?.absoluteString == "https://gateway.ai.cloudflare.com/v1/acct/gw/compat")
        #expect(request.apiKey == "")
        #expect(request.headers == ["cf-aig-authorization": "Bearer gw-token"])
        #expect(request.settingsName == "Workflows settings")
        #expect(request.responseFormat == .jsonObject)
        #expect(request.model == "openai/gpt-6-luna")
        #expect(request.systemPrompt == "sys")
        #expect(request.messages.map(\.role) == [.user])
        #expect(request.messages.map(\.text) == ["hello"])
        let built = try OpenAICompatibleBackend.urlRequest(for: request)
        #expect(built.url?.absoluteString == "https://gateway.ai.cloudflare.com/v1/acct/gw/compat/chat/completions")
        #expect(built.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(built.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer gw-token")
    }

    @Test(arguments: [
        "https://gateway.ai.cloudflare.com/v1/acct/gw",
        "https://gateway.ai.cloudflare.com/v1/acct/gw/",
        "https://gateway.ai.cloudflare.com/v1/acct/gw/compat",
        "https://gateway.ai.cloudflare.com/v1/acct/gw/compat/",
    ])
    func compatIsAddedOnce(_ url: String) throws {
        let prompt = ModelPrompt(provider: .gateway, model: "openai/m", prompt: "p")
        let request = try ModelRouter.request(for: prompt, settings: ["gateway_url": .string(url), "gateway_token": .string("t")])
        #expect(request.baseURL?.absoluteString == "https://gateway.ai.cloudflare.com/v1/acct/gw/compat")
        #expect(request.responseFormat == .text)
    }

    @Test(arguments: ["", "  ", "http://gateway.ai.cloudflare.com/v1/acct/gw", "gateway.ai.cloudflare.com/v1/acct/gw", "https://"])
    func anInvalidGatewayURLFails(_ url: String) {
        let prompt = ModelPrompt(provider: .gateway, model: "openai/m", prompt: "p")
        #expect(throws: RPCError("workflow", "Set the AI Gateway URL in Settings › Plugins › Workflows.")) {
            try ModelRouter.request(for: prompt, settings: ["gateway_url": .string(url), "gateway_token": .string("t")])
        }
    }

    @Test func aMissingGatewayTokenFails() {
        let prompt = ModelPrompt(provider: .gateway, model: "openai/m", prompt: "p")
        let message = RPCError("workflow", "Set the AI Gateway token in Settings › Plugins › Workflows.")
        #expect(throws: message) {
            try ModelRouter.request(for: prompt, settings: ["gateway_url": gatewaySettings["gateway_url"]!])
        }
        #expect(throws: message) {
            try ModelRouter.request(for: prompt, settings: ["gateway_url": gatewaySettings["gateway_url"]!,
                                                            "gateway_token": .string("  ")])
        }
    }

    @Test func anthropicModelsAreRefusedForTheGateway() {
        let prompt = ModelPrompt(provider: .gateway, model: "ANTHROPIC/claude-x", prompt: "p")
        #expect(throws: RPCError("workflow", ModelRouter.anthropicRefused)) {
            try ModelRouter.request(for: prompt, settings: gatewaySettings)
        }
    }

    @Test(arguments: [(LLMProvider.ollama, "http://localhost:11434/v1"), (LLMProvider.lmStudio, "http://localhost:1234/v1")])
    func localProvidersUseTheirFixedURLs(_ provider: LLMProvider, _ url: String) throws {
        let prompt = ModelPrompt(provider: provider, model: "llama", system: "", prompt: "p", json: true)
        let request = try ModelRouter.request(for: prompt, settings: gatewaySettings)
        #expect(request.baseURL?.absoluteString == url)
        #expect(request.apiKey == "")
        #expect(request.headers.isEmpty)
        #expect(request.settingsName == "Workflows settings")
        #expect(request.responseFormat == .jsonObject)
        let built = try OpenAICompatibleBackend.urlRequest(for: request)
        #expect(built.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(built.value(forHTTPHeaderField: "cf-aig-authorization") == nil)
    }

    @Test func completeJoinsTheStreamedChunks() async throws {
        let log = RequestLog()
        let router = ModelRouter(client: FakeStream(chunks: ["Hel", "lo", " there"], log: log))
        let reply = try await router.complete(ModelPrompt(provider: .ollama, model: "llama", prompt: "hi"), settings: [:])
        #expect(reply == "Hello there")
        #expect(await log.requests.first?.baseURL?.absoluteString == "http://localhost:11434/v1")
    }
}
