import Foundation
import OddFrogPluginAPI

public struct ChatRequest: Sendable, Equatable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var systemPrompt: String
    public var messages: [PluginMessage]
    public init(baseURL: URL, apiKey: String, model: String, systemPrompt: String, messages: [PluginMessage]) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.messages = messages
    }
}

public protocol ChatBackend: Sendable {
    func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error>
}

public struct OpenAICompatibleBackend: ChatBackend {
    public enum StreamLine: Sendable, Equatable {
        case delta(String)
        case error(String)
        case done
        case skip
    }
    private let session: URLSession
    public init(session: URLSession = .shared) {
        self.session = session
    }
    public static func urlRequest(for request: ChatRequest) throws -> URLRequest {
        var value = URLRequest(url: request.baseURL.appendingPathComponent("chat/completions"))
        value.httpMethod = "POST"
        value.setValue("application/json", forHTTPHeaderField: "Content-Type")
        value.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !request.apiKey.isEmpty {
            value.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }
        var messages: [JSONValue] = []
        if !request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(request.systemPrompt)]))
        }
        for message in request.messages {
            messages.append(.object(["role": .string(message.role.rawValue), "content": .string(message.text)]))
        }
        value.httpBody = try PluginProtocol.encoder().encode(
            JSONValue.object(["model": .string(request.model), "stream": .bool(true), "messages": .array(messages)]))
        return value
    }
    public func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error> {
        let urlRequest = try Self.urlRequest(for: request)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RPCError("chat", "HTTP \(http.statusCode) from \(urlRequest.url?.host ?? "the server"): \(try await Self.excerpt(of: bytes))")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        switch Self.parse(line: line) {
                        case .delta(let text):
                            continuation.yield(text)
                        case .error(let message):
                            throw RPCError("chat", message)
                        case .done:
                            continuation.finish()
                            return
                        case .skip:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    public static func parse(line: String) -> StreamLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":"), trimmed.hasPrefix("data:") else {
            return .skip
        }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else {
            return .done
        }
        guard let data = payload.data(using: .utf8),
              let value = try? PluginProtocol.decoder().decode(JSONValue.self, from: data) else {
            return .skip
        }
        if let message = value["error"]["message"].string, !message.isEmpty {
            return .error(message)
        }
        guard let content = value["choices"].array?.first?["delta"]["content"].string, !content.isEmpty else {
            return .skip
        }
        return .delta(content)
    }
    public static func delta(fromLine line: String) -> String? {
        guard case .delta(let text) = parse(line: line) else {
            return nil
        }
        return text
    }
    private static func excerpt(of bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 2048 {
                break
            }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
