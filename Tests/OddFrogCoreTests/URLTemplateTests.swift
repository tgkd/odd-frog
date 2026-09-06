import Foundation
import Testing
@testable import OddFrogCore

struct URLTemplateTests {
    @Test func acceptsAndDisplayRoundTrip() {
        let url = URL(string: "https://github.com/search?q={query}")!
        #expect(URLTemplate.accepts(url))
        #expect(URLTemplate.display(url) == "https://github.com/search?q={query}")
    }

    @Test func encodeEscapesReservedCharacters() {
        #expect(URLTemplate.encode("odd frog & co/+") == "odd%20frog%20%26%20co%2F%2B")
    }

    @Test func resolveReplacesEncodedPlaceholder() {
        let url = URL(string: "https://github.com/search?q={query}")!
        #expect(URLTemplate.resolve(url, query: "a b").absoluteString == "https://github.com/search?q=a%20b")
    }

    @Test func resolveTemplateBuildsURL() throws {
        let url = try #require(URLTemplate.resolve(template: "https://duckduckgo.com/?q={query}", query: "x"))
        #expect(url.host == "duckduckgo.com")
        #expect(url.query == "q=x")
    }

    @Test func resolveTemplateWithoutSchemeIsNil() {
        #expect(URLTemplate.resolve(template: "no scheme {query}", query: "x") == nil)
    }
}
