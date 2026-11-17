import Foundation
import Testing
import ChatPluginCore
import OddFrogPluginAPI

struct ChatServiceTests {
    private let messages = [PluginMessage(id: "m0", role: .user, text: "hi")]
    private let custom: [String: JSONValue] = ["base_url": .string(" http://example.com/v1 "), "api_key": .string(" sk "),
                                               "model": .string(" qwen "), "system_prompt": .string("Be brief.")]

    private func settings(_ service: String) -> [String: JSONValue] {
        custom.merging(["service": .string(service)]) { $1 }
    }

    @Test func missingOrUnknownServiceFallsBackToCustom() {
        #expect(ChatService.selected(in: [:]) == .custom)
        #expect(ChatService.selected(in: ["service": .string("Nope")]) == .custom)
        #expect(ChatService.selected(in: ["service": .string("Apple FM")]) == .appleFM)
    }

    @Test func appleFMIgnoresServerFields() throws {
        let request = try ChatService.appleFM.request(settings: settings("Apple FM"), messages: messages)
        #expect(request.baseURL == nil)
        #expect(request.apiKey == "")
        #expect(request.model == ChatService.onDeviceModel)
        #expect(request.systemPrompt == "Be brief.")
        #expect(ChatService.appleFM.isOnDevice)
    }

    @Test func localPresetsUseTheirOwnURLAndTheModelField() throws {
        let studio = try ChatService.lmStudio.request(settings: settings("LM Studio"), messages: messages)
        #expect(studio.baseURL?.absoluteString == "http://localhost:1234/v1")
        #expect(studio.model == "qwen")
        #expect(studio.apiKey == "")
        let ollama = try ChatService.ollama.request(settings: settings("Ollama"), messages: messages)
        #expect(ollama.baseURL?.absoluteString == "http://localhost:11434/v1")
        #expect(throws: RPCError("chat", "Set a model name in Chat settings.")) {
            try ChatService.ollama.request(settings: ["model": .string(" ")], messages: messages)
        }
    }

    @Test func customUsesEveryField() throws {
        let request = try ChatService.custom.request(settings: settings("Custom"), messages: messages)
        #expect(request.baseURL?.absoluteString == "http://example.com/v1")
        #expect(request.apiKey == "sk")
        #expect(request.model == "qwen")
        #expect(throws: RPCError("chat", "Set a valid API base URL in Chat settings.")) {
            try ChatService.custom.request(settings: ["base_url": .string("nope"), "model": .string("m")], messages: messages)
        }
    }

    @Test func transcriptCarriesInstructionsAndHistoryButNotThePrompt() {
        let request = ChatRequest(baseURL: nil, apiKey: "", model: "system", systemPrompt: "Be brief.",
                                  messages: [PluginMessage(id: "a", role: .user, text: "hi"),
                                             PluginMessage(id: "b", role: .assistant, text: "Hello"),
                                             PluginMessage(id: "c", role: .user, text: "again")])
        let entries = Array(FoundationModelsBackend.transcript(for: request))
        #expect(entries.count == 3)
        guard case .instructions = entries[0], case .prompt = entries[1], case .response = entries[2] else {
            Issue.record("Unexpected transcript entries")
            return
        }
    }
}
