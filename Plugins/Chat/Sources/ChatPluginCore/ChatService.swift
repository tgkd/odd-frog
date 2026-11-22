import Foundation
import LLMClient
import OddFrogPluginAPI

public enum ChatService: String, CaseIterable, Sendable {
    case appleFM = "Apple FM"
    case lmStudio = "LM Studio"
    case ollama = "Ollama"
    case custom = "Custom"

    public static let onDeviceModel = "system"

    public static func selected(in settings: [String: JSONValue]) -> ChatService {
        settings["service"]?.string.flatMap(ChatService.init(rawValue:)) ?? .custom
    }

    public var isOnDevice: Bool {
        self == .appleFM
    }

    public var presetBaseURL: URL? {
        switch self {
        case .lmStudio: URL(string: "http://localhost:1234/v1")
        case .ollama: URL(string: "http://localhost:11434/v1")
        case .appleFM, .custom: nil
        }
    }

    public func request(settings: [String: JSONValue], messages: [PluginMessage]) throws -> ChatRequest {
        let systemPrompt = settings["system_prompt"]?.string ?? ""
        guard !isOnDevice else {
            return ChatRequest(baseURL: nil, apiKey: "", model: Self.onDeviceModel,
                               systemPrompt: systemPrompt, messages: messages)
        }
        guard let baseURL = presetBaseURL ?? Self.customBaseURL(settings) else {
            throw RPCError("chat", "Set a valid API base URL in Chat settings.")
        }
        let model = Self.trimmed(settings["model"])
        guard !model.isEmpty else {
            throw RPCError("chat", "Set a model name in Chat settings.")
        }
        let apiKey = self == .custom ? Self.trimmed(settings["api_key"]) : ""
        return ChatRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                           systemPrompt: systemPrompt, messages: messages)
    }

    private static func customBaseURL(_ settings: [String: JSONValue]) -> URL? {
        guard let url = URL(string: trimmed(settings["base_url"])),
              url.scheme?.isEmpty == false, url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static func trimmed(_ value: JSONValue?) -> String {
        (value?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
