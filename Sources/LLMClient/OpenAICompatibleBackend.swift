import Foundation
import OddFrogPluginAPI

public struct OpenAICompatibleBackend: ChatStreaming {
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
        guard let baseURL = request.baseURL else {
            throw RPCError("chat", "Set a valid API base URL in \(request.settingsName).")
        }
        var value = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        value.httpMethod = "POST"
        value.setValue("application/json", forHTTPHeaderField: "Content-Type")
        value.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !request.apiKey.isEmpty {
            value.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (name, header) in request.headers {
            value.setValue(header, forHTTPHeaderField: name)
        }
        var messages: [JSONValue] = []
        if !request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(request.systemPrompt)]))
        }
        for message in request.messages {
            messages.append(.object(["role": .string(message.role.rawValue), "content": .string(message.text)]))
        }
        var body: [String: JSONValue] = ["model": .string(request.model), "stream": .bool(true), "messages": .array(messages)]
        if request.responseFormat == .jsonObject {
            body["response_format"] = .object(["type": .string("json_object")])
        }
        value.httpBody = try PluginProtocol.encoder().encode(JSONValue.object(body))
        return value
    }
    public func stream(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, any Error> {
        let urlRequest = try Self.urlRequest(for: request)
        let baseURL = request.baseURL
        let settings = request.settingsName
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch let error as URLError {
            throw ChatBackendError.connection(error, baseURL: baseURL, settings: settings)
        }
        if let http = response as? HTTPURLResponse {
            if !(200..<300).contains(http.statusCode) {
                throw ChatBackendError.status(http.statusCode, baseURL: baseURL, body: try await Self.excerpt(of: bytes),
                                              settings: settings)
            }
            if http.value(forHTTPHeaderField: "Content-Type")?.localizedCaseInsensitiveContains("application/json") == true {
                let body = try await Self.excerpt(of: bytes)
                throw ChatBackendError.server(ChatBackendError.message(inBody: body) ?? "The server did not stream a reply.", baseURL: baseURL)
            }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        switch Self.parse(line: line) {
                        case .delta(let text):
                            continuation.yield(text)
                        case .error(let message):
                            throw ChatBackendError.server(message, baseURL: baseURL)
                        case .done:
                            continuation.finish()
                            return
                        case .skip:
                            continue
                        }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: ChatBackendError.connection(error, baseURL: baseURL, settings: settings))
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
