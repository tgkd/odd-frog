import Foundation
import Testing
import TranslatePluginCore
import OddFrogPluginAPI

struct TranslateProviderTests {
    private let direction = TranslateDirection(source: .english, target: .russian)

    @Test func hintNamesThePairAndEngines() {
        let local = TranslateProvider.hint(primary: .russian, secondary: .english, deepL: false)
        #expect(local.map(\.id) == ["hint"])
        #expect(local[0].title == "Type text to translate")
        #expect(local[0].subtitle == "Russian ⇄ English · Apple Translation")
        #expect(local[0].primary == nil)
        let both = TranslateProvider.hint(primary: .russian, secondary: .english, deepL: true)
        #expect(both[0].subtitle == "Russian ⇄ English · Apple Translation and DeepL")
    }

    @Test func translationPastesAndCopies() {
        let rows = TranslateProvider.respond(direction: direction, offline: .text("привет"), online: .off)
        #expect(rows.map(\.id) == ["apple"])
        #expect(rows[0].title == "привет")
        #expect(rows[0].subtitle == "Apple · English → Russian")
        #expect(rows[0].primary == PluginAction(.paste, "привет"))
        #expect(rows[0].secondary == PluginAction(.copy, "привет"))
    }

    @Test func truncatedTextIsNamedInTheSubtitle() {
        let rows = TranslateProvider.respond(direction: direction, offline: .text("привет"), online: .off, truncated: true)
        #expect(rows[0].subtitle == "Apple · English → Russian · first 2000 characters")
    }

    @Test func appleOutcomesWithoutTextExplainThemselves() {
        let pending = TranslateProvider.respond(direction: direction, offline: nil, online: .off)[0]
        #expect(pending.title == "Translating…" && pending.primary == nil)
        let missing = TranslateProvider.respond(direction: direction, offline: .notInstalled, online: .off)[0]
        #expect(missing.title == "Download English and Russian for offline translation")
        #expect(missing.primary?.kind == .openURL)
        let unsupported = TranslateProvider.respond(direction: direction, offline: .unsupported, online: .off)[0]
        #expect(unsupported.title == "Apple can't translate English → Russian")
        let failed = TranslateProvider.respond(direction: direction, offline: .failed("boom"), online: .off)[0]
        #expect(failed.title == "Apple Translation failed" && failed.subtitle == "boom")
    }

    @Test func deepLRowFollowsAppleTranslation() {
        let pending = TranslateProvider.respond(direction: direction, offline: .text("привет"), online: .pending)
        #expect(pending.map(\.id) == ["apple", "deepl"])
        #expect(pending[1].title == "Translating with DeepL…" && pending[1].primary == nil)
        let failed = TranslateProvider.respond(direction: direction, offline: .text("привет"), online: .done(.failed("bad key")))
        #expect(failed[1].title == "DeepL translation failed" && failed[1].subtitle == "bad key")
        let both = TranslateProvider.respond(direction: direction, offline: nil, online: .pending)
        #expect(both.map(\.id) == ["apple", "deepl"])
    }

    @Test func deepLTranslationLeadsWhenAppleHasNone() {
        let rows = TranslateProvider.respond(direction: direction, offline: .notInstalled, online: .done(.text("здравствуй")))
        #expect(rows.map(\.id) == ["deepl", "apple"])
        #expect(rows[0].title == "здравствуй" && rows[0].subtitle == "DeepL · English → Russian")
        #expect(rows[0].primary == PluginAction(.paste, "здравствуй"))
    }

    @Test func equalTranslationsMergeIntoOneRow() {
        let rows = TranslateProvider.respond(direction: direction, offline: .text("привет"), online: .done(.text("привет")))
        #expect(rows.map(\.id) == ["apple"])
        #expect(rows[0].subtitle == "Apple and DeepL · English → Russian")
    }

    @Test func sameLanguagesAskForDifferentOnes() {
        #expect(TranslateProvider.sameLanguages().map(\.id) == ["same"])
    }
}
