import Foundation
import Testing
import TranslatePluginCore
import OddFrogPluginAPI

struct TranslateProviderTests {
    private let direction = TranslateDirection(source: .english, target: .russian)

    private func query(_ text: String) -> PluginQuery {
        PluginQuery(query: text, fullQuery: "tr \(text)")
    }

    @Test func emptyQueryShowsTheHint() {
        let local = TranslateProvider.respond(to: query(""), direction: direction, offline: nil, online: .off)
        #expect(local.map(\.id) == ["hint"])
        #expect(local[0].title == "Type text to translate")
        #expect(local[0].subtitle == "Russian ⇄ English · Apple Translation")
        #expect(local[0].primary == nil)
        let both = TranslateProvider.respond(to: query("  "), direction: direction, offline: nil, online: .pending)
        #expect(both[0].subtitle == "Russian ⇄ English · Apple Translation and DeepL")
    }

    @Test func translationPastesAndCopies() {
        let rows = TranslateProvider.respond(to: query("hello"), direction: direction, offline: .text("привет"), online: .off)
        #expect(rows.map(\.id) == ["apple"])
        #expect(rows[0].title == "привет")
        #expect(rows[0].subtitle == "Apple · English → Russian")
        #expect(rows[0].primary == PluginAction(.paste, "привет"))
        #expect(rows[0].secondary == PluginAction(.copy, "привет"))
    }

    @Test func appleOutcomesWithoutTextExplainThemselves() {
        let pending = TranslateProvider.respond(to: query("hi"), direction: direction, offline: nil, online: .off)[0]
        #expect(pending.title == "Translating…" && pending.primary == nil)
        let missing = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .notInstalled, online: .off)[0]
        #expect(missing.title == "Download English and Russian for offline translation")
        #expect(missing.primary?.kind == .openURL)
        let unsupported = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .unsupported, online: .off)[0]
        #expect(unsupported.title == "Apple can't translate English → Russian")
        let failed = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .failed("boom"), online: .off)[0]
        #expect(failed.title == "Apple Translation failed" && failed.subtitle == "boom")
    }

    @Test func deepLRowFollowsApple() {
        let pending = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .text("привет"), online: .pending)
        #expect(pending.map(\.id) == ["apple", "deepl"])
        #expect(pending[1].title == "Translating with DeepL…" && pending[1].primary == nil)
        let done = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .notInstalled, online: .done(.text("здравствуй")))
        #expect(done[1].title == "здравствуй" && done[1].subtitle == "DeepL · English → Russian")
        let failed = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .text("привет"), online: .done(.failed("bad key")))
        #expect(failed[1].title == "DeepL translation failed" && failed[1].subtitle == "bad key")
    }

    @Test func equalTranslationsMergeIntoOneRow() {
        let rows = TranslateProvider.respond(to: query("hi"), direction: direction, offline: .text("привет"), online: .done(.text("привет")))
        #expect(rows.map(\.id) == ["apple"])
        #expect(rows[0].subtitle == "Apple and DeepL · English → Russian")
    }

    @Test func sameLanguagesAskForDifferentOnes() {
        let rows = TranslateProvider.respond(to: query("hi"), direction: TranslateDirection(source: .english, target: .english),
                                             offline: nil, online: .off)
        #expect(rows.map(\.id) == ["same"])
    }
}
