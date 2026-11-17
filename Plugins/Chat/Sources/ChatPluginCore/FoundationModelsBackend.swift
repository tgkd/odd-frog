import Foundation
import FoundationModels
import OddFrogPluginAPI

public struct FoundationModelsBackend: ChatBackend {
    public init() {}

    public func stream(_ request: ChatRequest, tools context: ChatToolContext?) async throws -> AsyncThrowingStream<String, any Error> {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            throw RPCError("chat", Self.message(for: reason))
        }
        guard let prompt = request.messages.last, prompt.role == .user else {
            throw RPCError("params", "Nothing to send.")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let report: ActivityReport = { line in continuation.yield("→ \(line)\n\n") }
                    let actions = context.map(ChatActions.init(context:))
                    let tools = actions.map { FoundationModelsTools.all($0, report: report) } ?? []
                    let transcript = Self.transcript(for: request, extraInstructions: actions?.instructions, tools: tools)
                    let session = LanguageModelSession(model: .default, tools: tools, transcript: transcript)
                    var sent = ""
                    for try await snapshot in session.streamResponse(to: prompt.text) {
                        let text = snapshot.content
                        if text.hasPrefix(sent), text.count > sent.count {
                            continuation.yield(String(text.dropFirst(sent.count)))
                        }
                        sent = text
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.chatError(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func transcript(for request: ChatRequest, extraInstructions: String? = nil,
                                  tools: [any Tool] = []) -> Transcript {
        var entries: [Transcript.Entry] = []
        let instructions = [request.systemPrompt, extraInstructions ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !instructions.isEmpty || !tools.isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: tools.map { Transcript.ToolDefinition(tool: $0) })))
        }
        for message in request.messages.dropLast() {
            let segments: [Transcript.Segment] = [.text(Transcript.TextSegment(content: message.text))]
            switch message.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(segments: segments)))
            case .assistant:
                entries.append(.response(Transcript.Response(assetIDs: [], segments: segments)))
            }
        }
        return Transcript(entries: entries)
    }

    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This Mac cannot run the on-device Apple model."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings to use the Apple FM chat."
        case .modelNotReady:
            "The on-device Apple model is still downloading. Try again later."
        @unknown default:
            "The on-device Apple model is not available."
        }
    }

    private static func chatError(_ error: any Error) -> any Error {
        if error is CancellationError || error is RPCError {
            return error
        }
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
            return RPCError("chat", "This conversation is too long for the on-device Apple model. Start a new chat.")
        }
        return RPCError("chat", error.localizedDescription)
    }
}
