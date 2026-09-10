import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

struct ChatBackendTests {
    private func request(apiKey: String = "", systemPrompt: String = "",
                         messages: [PluginMessage] = [PluginMessage(id: "m0", role: .user, text: "hi")]) -> ChatRequest {
        ChatRequest(baseURL: URL(string: "http://localhost:11434/v1")!, apiKey: apiKey, model: "llama3.2",
                    systemPrompt: systemPrompt, messages: messages)
    }

    private func body(_ value: URLRequest) throws -> JSONValue {
        try PluginProtocol.decoder().decode(JSONValue.self, from: try #require(value.httpBody))
    }

    @Test func blankCommentAndTerminatorLinesCarryNoDelta() {
        #expect(OpenAICompatibleBackend.parse(line: "") == .skip)
        #expect(OpenAICompatibleBackend.parse(line: "   ") == .skip)
        #expect(OpenAICompatibleBackend.parse(line: ": ping") == .skip)
        #expect(OpenAICompatibleBackend.parse(line: "event: message") == .skip)
        #expect(OpenAICompatibleBackend.parse(line: "data: [DONE]") == .done)
        #expect(OpenAICompatibleBackend.parse(line: "data:[DONE]") == .done)
        #expect(OpenAICompatibleBackend.delta(fromLine: "data: [DONE]") == nil)
        #expect(OpenAICompatibleBackend.delta(fromLine: ": ping") == nil)
    }

    @Test func contentDeltasAreExtractedAndEmptyOnesSkipped() {
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#) == .delta("Hel"))
        #expect(OpenAICompatibleBackend.delta(fromLine: #"data:{"choices":[{"delta":{"content":" lo"}}]}"#) == " lo")
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .skip)
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"choices":[{"delta":{"content":""}}]}"#) == .skip)
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"choices":[]}"#) == .skip)
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"id":"1"}"#) == .skip)
    }

    @Test func malformedJSONIsSkippedAndErrorObjectsAreSurfaced() {
        #expect(OpenAICompatibleBackend.parse(line: "data: {not json") == .skip)
        #expect(OpenAICompatibleBackend.parse(line: "data: ") == .skip)
        #expect(OpenAICompatibleBackend.delta(fromLine: "data: {not json") == nil)
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"error":{"message":"model not found"}}"#)
                == .error("model not found"))
        #expect(OpenAICompatibleBackend.parse(line: #"data: {"error":{"message":""}}"#) == .skip)
    }

    @Test func requestsTargetChatCompletionsWithJSONAndStreaming() throws {
        let value = try OpenAICompatibleBackend.urlRequest(for: request())
        #expect(value.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(value.httpMethod == "POST")
        #expect(value.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(value.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(value.value(forHTTPHeaderField: "Authorization") == nil)
        let json = try body(value)
        #expect(json["model"].string == "llama3.2")
        #expect(json["stream"].bool == true)
        #expect(json["messages"].array?.count == 1)
        #expect(json["messages"].array?.first?["role"].string == "user")
        #expect(json["messages"].array?.first?["content"].string == "hi")
    }

    @Test func authorizationAndSystemPromptAppearOnlyWhenConfigured() throws {
        let keyed = try OpenAICompatibleBackend.urlRequest(for: request(apiKey: "sk-test", systemPrompt: "  \n "))
        #expect(keyed.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(try body(keyed)["messages"].array?.map { $0["role"].string } == ["user"])
        let prompted = try OpenAICompatibleBackend.urlRequest(
            for: request(systemPrompt: "Be brief.",
                         messages: [PluginMessage(id: "m0", role: .user, text: "hi"),
                                    PluginMessage(id: "m1", role: .assistant, text: "Hello"),
                                    PluginMessage(id: "m2", role: .user, text: "again")]))
        let messages = try #require(try body(prompted)["messages"].array)
        #expect(messages.map { $0["role"].string } == ["system", "user", "assistant", "user"])
        #expect(messages.first?["content"].string == "Be brief.")
        #expect(messages.last?["content"].string == "again")
    }
}
