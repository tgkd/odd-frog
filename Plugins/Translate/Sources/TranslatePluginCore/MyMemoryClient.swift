import Foundation

public struct MyMemoryClient: OnlineTranslator {
    private struct Answer: Decodable {
        struct Result: Decodable {
            var translatedText: String
        }
        struct Match: Decodable {
            var translation: String
            var match: Double
            var createdBy: String?
            enum CodingKeys: String, CodingKey {
                case translation, match
                case createdBy = "created-by"
            }
        }
        var responseData: Result
        var responseStatus: Int
        var responseDetails: String
        var quotaFinished: Bool
        var matches: [Match]
        enum CodingKeys: String, CodingKey {
            case responseData, responseStatus, responseDetails, quotaFinished, matches
        }
        // Errors arrive as HTTP 200 with a string status, a null quota flag and `matches: ""`.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            responseData = try c.decode(Result.self, forKey: .responseData)
            if let status = try? c.decode(Int.self, forKey: .responseStatus) {
                responseStatus = status
            } else {
                responseStatus = Int(try c.decode(String.self, forKey: .responseStatus)) ?? 0
            }
            responseDetails = (try? c.decodeIfPresent(String.self, forKey: .responseDetails)) ?? ""
            quotaFinished = (try? c.decodeIfPresent(Bool.self, forKey: .quotaFinished)) ?? false
            matches = (try? c.decodeIfPresent([Match].self, forKey: .matches)) ?? []
        }
    }
    public static let endpoint = URL(string: "https://api.mymemory.translated.net/get")!
    public static let limit = 500
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private let session: URLSession
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func urlRequest(_ text: String, from source: TranslateLanguage, to target: TranslateLanguage,
                                  email: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var fields = [("q", text), ("langpair", "\(source.code)|\(target.code)")]
        if !email.isEmpty {
            fields.append(("de", email))
        }
        let body = fields.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $1)" }
        request.httpBody = Data(body.joined(separator: "&").utf8)
        return request
    }

    public static func outcome(status: Int, data: Data, text: String) -> TranslationOutcome {
        guard (200..<300).contains(status) else {
            return .failed("MyMemory answered with HTTP \(status).")
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
            return .failed("MyMemory sent an answer Odd Frog can't read.")
        }
        if answer.quotaFinished || answer.responseStatus == 429 {
            return .failed("MyMemory's free limit for today is used up. An email in Translate settings raises it.")
        }
        guard answer.responseStatus == 200 else {
            let details = answer.responseDetails.isEmpty ? answer.responseData.translatedText : answer.responseDetails
            return .failed("MyMemory: " + details.prefix(1).uppercased() + details.dropFirst().lowercased())
        }
        return .text(best(answer, text: text))
    }

    // The top answer can be a fuzzy memory hit for another sentence, or the source copied verbatim.
    private static func best(_ answer: Answer, text: String) -> String {
        if let machine = answer.matches.first(where: { $0.createdBy == "MT!" }) {
            return machine.translation
        }
        let exact = answer.matches.first {
            $0.match >= 0.95 && $0.translation.caseInsensitiveCompare(text) != .orderedSame
        }
        return exact?.translation ?? answer.responseData.translatedText
    }

    public func translate(_ text: String, from source: TranslateLanguage, to target: TranslateLanguage,
                          email: String) async -> TranslationOutcome {
        guard text.count <= Self.limit else {
            return .failed("MyMemory translates up to \(Self.limit) characters.")
        }
        do {
            let (data, response) = try await session.data(for: Self.urlRequest(text, from: source, to: target, email: email))
            return Self.outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data, text: text)
        } catch {
            return .failed("Can't reach MyMemory: \(error.localizedDescription)")
        }
    }
}
