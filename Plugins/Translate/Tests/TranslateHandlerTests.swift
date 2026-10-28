import Foundation
import Testing
import TranslatePluginCore
import OddFrogPluginAPI

private actor FakeOffline: OfflineTranslator {
    private let outcome: TranslationOutcome
    private let delay: Duration
    private(set) var calls = 0
    init(_ outcome: TranslationOutcome, delay: Duration = .zero) {
        self.outcome = outcome
        self.delay = delay
    }
    func translate(_ text: String, from source: TranslateLanguage, to target: TranslateLanguage) async -> TranslationOutcome {
        calls += 1
        try? await Task.sleep(for: delay)
        return outcome
    }
}

private actor FakeOnline: OnlineTranslator {
    private var outcomes: [TranslationOutcome]
    private(set) var texts: [String] = []
    init(_ outcomes: [TranslationOutcome]) {
        self.outcomes = outcomes
    }
    func translate(_ text: String, to target: TranslateLanguage, key: String) async -> TranslationOutcome {
        texts.append(text)
        return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
    }
}

private actor Recorder {
    private(set) var events: [String] = []
    func record(_ method: String) {
        events.append(method)
    }
}

struct TranslateHandlerTests {
    private let operation = ProviderOperation(id: "test", service: { _, _ in throw RPCError("test", "No host services.") },
                                              emit: { _, _ in })

    private func handler(offline: FakeOffline, online: FakeOnline = FakeOnline([.text("unused")]),
                         offlineWait: Duration = .seconds(1), retryAfter: TimeInterval = 10) async -> (TranslateHandler, Recorder) {
        let handler = TranslateHandler(offline: offline, online: online, offlineWait: offlineWait,
                                       onlineDelay: .milliseconds(30), retryAfter: retryAfter)
        let recorder = Recorder()
        await handler.start(emit: { method in await recorder.record(method) })
        return (handler, recorder)
    }

    private func rows(_ handler: TranslateHandler, _ text: String, key: String = "") async throws -> [PluginItem] {
        let params = JSONValue.object([
            "input": try .encode(PluginQuery(query: text, fullQuery: "tr \(text)")),
            "context": try .encode(PluginContext(settings: ["deepl_key": .string(key)])),
        ])
        return try await handler.handle("query", params: params, operation: operation).decode([PluginItem].self)
    }

    private func wait(_ condition: @Sendable () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func offlineAnswerArrivesWithinTheQuery() async throws {
        let offline = FakeOffline(.text("привет"))
        let (handler, recorder) = await handler(offline: offline)
        let first = try await rows(handler, "hello")
        #expect(first.map(\.title) == ["привет"])
        #expect(try await rows(handler, "hello").map(\.title) == ["привет"])
        #expect(await offline.calls == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorder.events.isEmpty)
    }

    @Test func slowOfflineAnswerInvalidatesTheQuery() async throws {
        let (handler, recorder) = await handler(offline: FakeOffline(.text("привет"), delay: .milliseconds(150)),
                                                offlineWait: .milliseconds(10))
        #expect(try await rows(handler, "hello").map(\.title) == ["Translating…"])
        try await wait { await recorder.events == ["queryInvalidated"] }
        #expect(try await rows(handler, "hello").map(\.title) == ["привет"])
    }

    @Test func deepLRowAppearsOnlyWithAKey() async throws {
        let online = FakeOnline([.text("здравствуй")])
        let (handler, recorder) = await handler(offline: FakeOffline(.text("привет")), online: online)
        #expect(try await rows(handler, "hello").map(\.id) == ["apple"])
        #expect(try await rows(handler, "hello", key: "k:fx").map(\.title) == ["привет", "Translating with DeepL…"])
        try await wait { await recorder.events.contains("queryInvalidated") }
        #expect(try await rows(handler, "hello", key: "k:fx").map(\.title) == ["привет", "здравствуй"])
        #expect(await online.texts == ["hello"])
    }

    @Test func onlyTheLastOfFastQueriesReachesDeepL() async throws {
        let online = FakeOnline([.text("x")])
        let (handler, recorder) = await handler(offline: FakeOffline(.text("y")), online: online)
        _ = try await rows(handler, "h", key: "k")
        _ = try await rows(handler, "he", key: "k")
        _ = try await rows(handler, "hello", key: "k")
        try await wait { await recorder.events.contains("queryInvalidated") }
        try await Task.sleep(for: .milliseconds(80))
        #expect(await online.texts == ["hello"])
    }

    @Test func failuresAreRetriedAfterTheyExpire() async throws {
        let online = FakeOnline([.failed("DeepL is busy. Try again in a moment."), .text("здравствуй")])
        let (handler, recorder) = await handler(offline: FakeOffline(.text("привет")), online: online, retryAfter: 0.1)
        _ = try await rows(handler, "hello", key: "k")
        try await wait { await recorder.events.count == 1 }
        #expect(try await rows(handler, "hello", key: "k").last?.title == "DeepL translation failed")
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await rows(handler, "hello", key: "k").last?.title == "Translating with DeepL…")
        try await wait { await recorder.events.count == 2 }
        #expect(try await rows(handler, "hello", key: "k").last?.title == "здравствуй")
    }

    @Test func emptyTranslationBecomesAFailure() async throws {
        let (handler, recorder) = await handler(offline: FakeOffline(.text(" ")), online: FakeOnline([.text("")]))
        let first = try await rows(handler, "?", key: "k")
        #expect(first.first?.title == "Apple Translation failed")
        #expect(first.first?.subtitle == "The translation came back empty.")
        try await wait { await recorder.events.contains("queryInvalidated") }
        #expect(try await rows(handler, "?", key: "k").allSatisfy { !$0.title.isEmpty })
        #expect(try await rows(handler, "?", key: "k").last?.title == "DeepL translation failed")
    }

    @Test func staleOfflineAnswersDoNotInvalidate() async throws {
        let (handler, recorder) = await handler(offline: FakeOffline(.text("привет"), delay: .milliseconds(100)),
                                                offlineWait: .milliseconds(10))
        _ = try await rows(handler, "hel")
        _ = try await rows(handler, "hello")
        try await wait { await recorder.events.count == 1 }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await recorder.events == ["queryInvalidated"])
    }

    @Test func emptyQueryShowsTheHintWithoutTranslating() async throws {
        let offline = FakeOffline(.text("unused"))
        let (handler, _) = await handler(offline: offline)
        #expect(try await rows(handler, "").map(\.id) == ["hint"])
        #expect(await offline.calls == 0)
    }
}
