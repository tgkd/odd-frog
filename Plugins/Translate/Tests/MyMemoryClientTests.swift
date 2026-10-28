import Foundation
import Testing
import TranslatePluginCore

struct MyMemoryClientTests {
    private func body(_ request: URLRequest) throws -> String {
        String(decoding: try #require(request.httpBody), as: UTF8.self)
    }

    @Test func requestPostsAnEscapedForm() throws {
        let request = MyMemoryClient.urlRequest("a+b & привет", from: .english, to: .russian, email: "")
        #expect(request.url == MyMemoryClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(try body(request) == "q=a%2Bb%20%26%20%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82&langpair=en%7Cru")
    }

    @Test func emailIsSentOnlyWhenSet() throws {
        let request = MyMemoryClient.urlRequest("hi", from: .english, to: .russian, email: "me@example.com")
        #expect(try body(request) == "q=hi&langpair=en%7Cru&de=me%40example.com")
    }

    @Test func machineTranslationBeatsAFuzzyMemoryHit() {
        let data = Data("""
        {"responseData":{"translatedText":"Что-то дождь усилился","match":0.91},"quotaFinished":false,
         "responseDetails":"","responseStatus":200,"matches":[
          {"translation":"Что-то дождь усилился","match":0.91,"created-by":"Kuzz"},
          {"translation":"идет дождь, не так ли?","match":0.85,"created-by":"MT!"}]}
        """.utf8)
        #expect(MyMemoryClient.outcome(status: 200, data: data, text: "it's raining, isn't it?") == .text("идет дождь, не так ли?"))
    }

    @Test func memoryCopyOfTheSourceIsSkipped() {
        let data = Data("""
        {"responseData":{"translatedText":"Guten Morgen","match":1},"quotaFinished":false,
         "responseDetails":"","responseStatus":200,"matches":[
          {"translation":"Guten Morgen","match":1,"created-by":"Public Web"},
          {"translation":"Доброе утро","match":1,"created-by":"MateCat"}]}
        """.utf8)
        #expect(MyMemoryClient.outcome(status: 200, data: data, text: "Guten Morgen") == .text("Доброе утро"))
    }

    @Test func topAnswerIsTheFallback() {
        let data = Data(#"{"responseData":{"translatedText":"hei","match":0.99},"responseStatus":200,"matches":[]}"#.utf8)
        #expect(MyMemoryClient.outcome(status: 200, data: data, text: "hello") == .text("hei"))
    }

    @Test func errorsInsideHTTP200ExplainWhatHappened() {
        let invalid = Data("""
        {"responseData":{"translatedText":"'XX' IS AN INVALID TARGET LANGUAGE"},"quotaFinished":null,
         "responseDetails":"'XX' IS AN INVALID TARGET LANGUAGE","responseStatus":"403","matches":""}
        """.utf8)
        #expect(MyMemoryClient.outcome(status: 200, data: invalid, text: "hello") == .failed("MyMemory: 'xx' is an invalid target language"))
        let quota = Data("""
        {"responseData":{"translatedText":"MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY"},
         "quotaFinished":true,"responseStatus":429,"matches":""}
        """.utf8)
        #expect(MyMemoryClient.outcome(status: 200, data: quota, text: "hello")
            == .failed("MyMemory's free limit for today is used up. An email in Translate settings raises it."))
    }

    @Test func badAnswersAreReported() {
        #expect(MyMemoryClient.outcome(status: 500, data: Data(), text: "hello") == .failed("MyMemory answered with HTTP 500."))
        #expect(MyMemoryClient.outcome(status: 200, data: Data("<html>".utf8), text: "hello")
            == .failed("MyMemory sent an answer Odd Frog can't read."))
    }

    @Test func longTextIsRejectedWithoutARequest() async {
        let text = String(repeating: "a", count: MyMemoryClient.limit + 1)
        let outcome = await MyMemoryClient().translate(text, from: .english, to: .russian, email: "")
        #expect(outcome == .failed("MyMemory translates up to 500 characters."))
    }
}
