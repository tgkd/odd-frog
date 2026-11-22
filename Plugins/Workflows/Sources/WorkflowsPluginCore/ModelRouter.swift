import Foundation
import LLMClient
import OddFrogPluginAPI

public struct ModelRouter: ModelCompleting {
    public static let settingsName = "Workflows settings"
    public static let ollamaURL = URL(string: "http://localhost:11434/v1")!
    public static let lmStudioURL = URL(string: "http://localhost:1234/v1")!
    public static let missingURL = "Set the AI Gateway URL in Settings › Plugins › Workflows."
    public static let missingToken = "Set the AI Gateway token in Settings › Plugins › Workflows."
    public static let anthropicRefused = "anthropic/* models are not called through the gateway. Use a provider with a key in the gateway, such as openai/…."

    private let client: any ChatStreaming

    public init(client: any ChatStreaming = OpenAICompatibleBackend()) {
        self.client = client
    }

    public func complete(_ prompt: ModelPrompt, settings: [String: JSONValue]) async throws -> String {
        let request = try Self.request(for: prompt, settings: settings)
        var reply = ""
        for try await chunk in try await client.stream(request) {
            try Task.checkCancellation()
            reply += chunk
        }
        try Task.checkCancellation()
        return reply
    }

    public static func request(for prompt: ModelPrompt, settings: [String: JSONValue]) throws -> ChatRequest {
        let messages = [PluginMessage(id: "prompt", role: .user, text: prompt.prompt)]
        let format: ChatRequest.ResponseFormat = prompt.json ? .jsonObject : .text
        switch prompt.provider {
        case .gateway:
            if isAnthropic(prompt.model) {
                throw RPCError("workflow", anthropicRefused)
            }
            guard let baseURL = gatewayBaseURL(settings["gateway_url"]?.string ?? "") else {
                throw RPCError("workflow", missingURL)
            }
            let token = (settings["gateway_token"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                throw RPCError("workflow", missingToken)
            }
            return ChatRequest(baseURL: baseURL, apiKey: "", model: prompt.model, systemPrompt: prompt.system,
                               messages: messages, headers: ["cf-aig-authorization": "Bearer \(token)"],
                               responseFormat: format, settingsName: settingsName)
        case .ollama, .lmStudio:
            let baseURL = prompt.provider == .ollama ? ollamaURL : lmStudioURL
            return ChatRequest(baseURL: baseURL, apiKey: "", model: prompt.model, systemPrompt: prompt.system,
                               messages: messages, responseFormat: format, settingsName: settingsName)
        }
    }

    public static func isAnthropic(_ model: String) -> Bool {
        model.lowercased().hasPrefix("anthropic/")
    }

    static func gatewayBaseURL(_ setting: String) -> URL? {
        var text = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("/") {
            text.removeLast()
        }
        guard let given = URL(string: text), given.scheme?.lowercased() == "https",
              let host = given.host, !host.isEmpty else {
            return nil
        }
        if !text.hasSuffix("/compat") {
            text += "/compat"
        }
        return URL(string: text)
    }
}
