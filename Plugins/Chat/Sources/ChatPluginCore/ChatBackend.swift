import Foundation
import LLMClient
import OddFrogPluginAPI

public protocol ChatBackend: Sendable {
    func stream(_ request: ChatRequest, tools: ChatToolContext?) async throws -> AsyncThrowingStream<String, any Error>
}

extension OpenAICompatibleBackend: ChatBackend {
    public func stream(_ request: ChatRequest, tools: ChatToolContext?) async throws -> AsyncThrowingStream<String, any Error> {
        try await stream(request)
    }
}
