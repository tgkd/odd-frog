import Foundation

public struct DeepLClient: OnlineTranslator {
    private struct Answer: Decodable {
        struct Translation: Decodable {
            var text: String
        }
        var translations: [Translation]
    }
    private let session: URLSession
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func endpoint(for key: String) -> URL {
        URL(string: key.hasSuffix(":fx") ? "https://api-free.deepl.com/v2/translate" : "https://api.deepl.com/v2/translate")!
    }

    public static func urlRequest(_ text: String, target: TranslateLanguage, key: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint(for: key), timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": [text], "target_lang": target.deepLTarget])
        return request
    }

    public static func outcome(status: Int, data: Data) -> TranslationOutcome {
        switch status {
        case 200..<300:
            guard let answer = try? JSONDecoder().decode(Answer.self, from: data), let first = answer.translations.first else {
                return .failed("DeepL sent an answer Odd Frog can't read.")
            }
            return .text(first.text)
        case 403:
            return .failed("DeepL rejected the API key. Check it in Translate settings.")
        case 456:
            return .failed("The DeepL quota for this month is used up.")
        case 429:
            return .failed("DeepL is busy. Try again in a moment.")
        default:
            return .failed("DeepL answered with HTTP \(status).")
        }
    }

    public func translate(_ text: String, to target: TranslateLanguage, key: String) async -> TranslationOutcome {
        do {
            let (data, response) = try await session.data(for: try Self.urlRequest(text, target: target, key: key))
            return Self.outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch {
            return .failed("Can't reach DeepL: \(error.localizedDescription)")
        }
    }
}
