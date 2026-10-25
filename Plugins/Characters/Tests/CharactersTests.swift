import Foundation
import Testing
import CharactersPluginCore
import OddFrogPluginAPI

struct CharactersTests {
    private let emoji = CharacterCatalog.emoji(locale: Locale(identifier: "ru"))
    private let symbols = CharacterCatalog.symbols()

    private func request(_ query: String, maxResults: Int = 50) -> PluginQuery {
        PluginQuery(query: query, fullQuery: "emoji " + query, maxResults: maxResults)
    }

    @Test func emojiNamesFindTheGlyph() {
        #expect(emoji.search("grinning face").first?.glyph == "😀")
        #expect(emoji.search("rocket").first?.glyph == "🚀")
    }

    @Test func aliasesCoverWordsMissingFromUnicodeNames() {
        #expect(emoji.search("thumbs up").first?.glyph == "👍")
        #expect(emoji.search("огонь").first?.glyph == "🔥")
        #expect(emoji.search("heart").contains { $0.glyph == "❤️" })
    }

    @Test func textPresentationEmojiGetAVariationSelector() {
        let heart = emoji.search("love").first { $0.name.contains("heart") && $0.code == "U+2764" }
        #expect(heart?.glyph == "❤\u{FE0F}")
    }

    @Test func flagsMatchEnglishNameCodeAndLocalName() {
        #expect(emoji.search("flag germany").first?.glyph == "🇩🇪")
        #expect(emoji.search("jp").first?.glyph == "🇯🇵")
        #expect(emoji.search("германия").first?.glyph == "🇩🇪")
        #expect(emoji.search("germany").first?.code == "U+1F1E9 U+1F1EA")
    }

    @Test func everyQueryWordMustMatch() {
        #expect(emoji.search("grinning zzzzz").isEmpty)
        #expect(emoji.search("   ").isEmpty)
    }

    @Test func pastedGlyphFindsItself() {
        #expect(emoji.search("😀").first?.glyph == "😀")
        #expect(symbols.search("→").first?.glyph == "→")
    }

    @Test func symbolsFindArrowsMathCurrencyAndMacKeys() {
        #expect(symbols.search("right arrow").first?.glyph == "→")
        #expect(symbols.search("not equal").first?.glyph == "≠")
        #expect(symbols.search("euro").first?.glyph == "€")
        #expect(symbols.search("ruble").first?.glyph == "₽")
        #expect(symbols.search("command").first?.glyph == "⌘")
        #expect(symbols.search("alpha").contains { $0.glyph == "α" })
    }

    @Test func symbolsLeaveEmojiToTheEmojiCatalog() {
        #expect(!symbols.entries.contains { $0.glyph == "😀" || $0.glyph == "✅" })
    }

    @Test func emptyQueryListsFeaturedEntries() {
        let items = CharactersProvider.respond(to: request(""), kind: .emoji, catalog: emoji)
        #expect(items.first?.title == "Grinning face")
        #expect(items.first?.icon == "glyph:😀")
        #expect(items.count == emoji.featured.count)
        #expect(!symbols.featured.isEmpty)
    }

    @Test func rowsPasteOnReturnAndCopyOnTheSecondaryAction() throws {
        let item = try #require(CharactersProvider.respond(to: request("rocket"), kind: .emoji, catalog: emoji).first)
        #expect(item.title == "Rocket")
        #expect(item.icon == "glyph:🚀")
        #expect(item.subtitle == "U+1F680")
        #expect(item.kind == "Emoji")
        #expect(item.primary == PluginAction(.paste, "🚀"))
        #expect(item.secondary == PluginAction(.copy, "🚀"))
    }

    @Test func resultCountFollowsTheCapAndNoMatchGivesAnInfoRow() {
        #expect(CharactersProvider.respond(to: request("heart", maxResults: 3), kind: .emoji, catalog: emoji).count == 3)
        #expect(CharactersProvider.respond(to: request("heart", maxResults: 500), kind: .emoji, catalog: emoji).count <= 50)
        let none = CharactersProvider.respond(to: request("zzzzzz"), kind: .symbols, catalog: symbols)
        #expect(none.map(\.id) == ["empty"])
        #expect(none[0].primary == nil)
    }

    @Test func handlerAnswersQueriesAndRejectsUnknownMethods() async throws {
        let handler = CharactersHandler(.symbols)
        let operation = ProviderOperation(id: "test", service: { _, _ in throw RPCError("test", "unexpected service call") }, emit: { _, _ in })
        let params = JSONValue.object(["input": try .encode(request("copyright"))])
        let result = try await handler.handle("query", params: params, operation: operation)
        let items = try result.decode([PluginItem].self)
        #expect(items.first?.primary == PluginAction(.paste, "©"))
        await #expect(throws: RPCError.self) {
            try await handler.handle("bogus", params: .null, operation: operation)
        }
    }
}
