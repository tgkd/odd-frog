import Foundation
import OddFrogPluginAPI

public struct ChatRequest: Sendable, Equatable {
    public enum ResponseFormat: Sendable, Equatable { case text, jsonObject }
    public var baseURL: URL?
    public var apiKey: String
    public var model: String
    public var systemPrompt: String
    public var messages: [PluginMessage]
    public var headers: [String: String]
    public var responseFormat: ResponseFormat
    public var settingsName: String
    public init(baseURL: URL?, apiKey: String, model: String, systemPrompt: String, messages: [PluginMessage],
                headers: [String: String] = [:], responseFormat: ResponseFormat = .text,
                settingsName: String = "Chat settings") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.headers = headers
        self.responseFormat = responseFormat
        self.settingsName = settingsName
    }
}

public protocol ChatStreaming: Sendable {
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error>
}
