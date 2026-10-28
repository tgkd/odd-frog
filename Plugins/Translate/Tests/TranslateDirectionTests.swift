import Foundation
import Testing
import TranslatePluginCore
import OddFrogPluginAPI

struct TranslateDirectionTests {
    @Test func yourLanguageGoesIntoTheOtherOne() {
        let direction = TranslateDirection.resolve("привет", primary: .russian, secondary: .english)
        #expect(direction == TranslateDirection(source: .russian, target: .english))
    }

    @Test func anyOtherLanguageGoesIntoYours() throws {
        #expect(TranslateDirection.resolve("hello", primary: .russian, secondary: .english)
            == TranslateDirection(source: .english, target: .russian))
        let german = try #require(TranslateLanguage.named("German"))
        #expect(TranslateDirection.resolve("Guten Morgen, wie geht es dir heute?", primary: .russian, secondary: .english)
            == TranslateDirection(source: german, target: .russian))
    }

    @Test func chineseVariantsMapToChinese() {
        #expect(TranslateLanguage.matching(code: "zh-Hans")?.name == "Chinese")
        #expect(TranslateLanguage.matching(code: "nb")?.name == "Norwegian")
        #expect(TranslateLanguage.matching(code: "xx") == nil)
    }

    @Test func settingsFallBackToRussianAndEnglish() throws {
        let fallback = TranslateDirection.languages([:])
        #expect(fallback.primary == .russian && fallback.secondary == .english)
        let chosen = TranslateDirection.languages(["primary_language": .string("German"), "secondary_language": .string("Bogus")])
        #expect(chosen.primary == (try #require(TranslateLanguage.named("German"))) && chosen.secondary == .english)
    }
}
