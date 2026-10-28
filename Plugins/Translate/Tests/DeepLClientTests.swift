import Foundation
import Testing
import TranslatePluginCore
import OddFrogPluginAPI

struct DeepLClientTests {
    @Test func freeKeysUseTheFreeEndpoint() {
        #expect(DeepLClient.endpoint(for: "abc:fx").absoluteString == "https://api-free.deepl.com/v2/translate")
        #expect(DeepLClient.endpoint(for: "abc").absoluteString == "https://api.deepl.com/v2/translate")
    }

    @Test func requestCarriesKeyTextAndTargetVariant() throws {
        let request = try DeepLClient.urlRequest("привет", target: .english, key: "abc:fx")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key abc:fx")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try PluginProtocol.decoder().decode(JSONValue.self, from: try #require(request.httpBody))
        #expect(body["text"] == .array([.string("привет")]))
        #expect(body["target_lang"] == .string("EN-US"))
        #expect(body["source_lang"] == .null)
    }

    @Test func successfulAnswerYieldsTheFirstTranslation() {
        let data = Data(#"{"translations":[{"detected_source_language":"RU","text":"hello"}]}"#.utf8)
        #expect(DeepLClient.outcome(status: 200, data: data) == .text("hello"))
        #expect(DeepLClient.outcome(status: 200, data: Data("nope".utf8)) == .failed("DeepL sent an answer Odd Frog can't read."))
        #expect(DeepLClient.outcome(status: 200, data: Data(#"{"translations":[]}"#.utf8)) == .failed("DeepL sent an answer Odd Frog can't read."))
    }

    @Test func errorStatusesExplainWhatHappened() {
        #expect(DeepLClient.outcome(status: 403, data: Data()) == .failed("DeepL rejected the API key. Check it in Translate settings."))
        #expect(DeepLClient.outcome(status: 456, data: Data()) == .failed("The DeepL quota for this month is used up."))
        #expect(DeepLClient.outcome(status: 429, data: Data()) == .failed("DeepL is busy. Try again in a moment."))
        #expect(DeepLClient.outcome(status: 500, data: Data()) == .failed("DeepL answered with HTTP 500."))
    }
}
