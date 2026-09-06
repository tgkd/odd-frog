import Foundation
import Testing
@testable import OddFrogCore

private func app(_ name: String) -> LauncherItem {
    .app(AppItem(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: nil))
}

private func cmd(_ name: String, aliases: [String] = []) -> LauncherItem {
    .command(CommandItem(name: name, aliases: aliases, action: .shell("true"), cwd: nil, terminal: false))
}

private func rank(lexical: Double, weight: Double, name: String = "x") -> RankedItem {
    RankedItem(item: app(name), lexical: lexical, weight: weight, exactAlias: false)
}

struct SearchEngineTests {
    @Test func bonusIsBoundedAndSaturating() {
        #expect(SearchEngine.frecencyBonus(0) == 0)
        #expect(SearchEngine.frecencyBonus(3) == 7.5)
        #expect(SearchEngine.frecencyBonus(1_000_000) < 15)
        #expect(SearchEngine.frecencyBonus(10) > SearchEngine.frecencyBonus(3))
    }

    @Test func gapAboveCapNeverFlips() {
        let strong = rank(lexical: 100, weight: 0, name: "a")
        let weak = rank(lexical: 84, weight: 1e9, name: "b")
        #expect(SearchEngine.order(strong, weak))
    }

    @Test func nearMatchFlipsAfterThreeUses() {
        var table = FrecencyTable()
        let now = Date(timeIntervalSince1970: 1_000_000)
        for _ in 0..<3 { table.record("b", at: now) }
        let w = table.weight(for: "b", at: now)
        let a = rank(lexical: 85, weight: 0, name: "a")
        let b = rank(lexical: 80, weight: w, name: "b")
        #expect(b.score == 87.5)
        #expect(SearchEngine.order(b, a))
    }

    @Test func unrelatedCandidateDoesNotReorder() {
        let items = [app("Xcode"), app("Visual Studio Code")]
        let weights = ["/Applications/Xcode.app": 3.0]
        let before = SearchEngine.search(query: "code", items: items, weights: weights, maxResults: 8).map { $0.item.title }
        let after = SearchEngine.search(query: "code", items: items + [app("Codesign Helper Thing")], weights: weights, maxResults: 8)
            .map { $0.item.title }
            .filter { $0 != "Codesign Helper Thing" }
        #expect(before == after)
    }

    @Test func maxResultsNeverChangesTop() {
        let items = (0..<20).map { app("Code \($0)") } + [app("Xcode")]
        let weights = ["/Applications/Xcode.app": 50.0]
        let wide = SearchEngine.search(query: "code", items: items, weights: weights, maxResults: 50)
        let narrow = SearchEngine.search(query: "code", items: items, weights: weights, maxResults: 1)
        #expect(wide.first?.item.title == narrow.first?.item.title)
    }

    @Test func exactAliasBeatsEverything() {
        let items = [app("Build Master 3000"), cmd("Build Project", aliases: ["build", "b"])]
        let weights = ["/Applications/Build Master 3000.app": 1000.0]
        let results = SearchEngine.search(query: "build", items: items, weights: weights, maxResults: 8)
        #expect(results.first?.item.title == "Build Project")
        #expect(results.first?.exactAlias == true)
    }

    @Test func tiesAreDeterministic() {
        let items = [app("Beta"), app("Alpha"), app("Gamma")]
        let results = SearchEngine.search(query: "a", items: items, weights: [:], maxResults: 8)
        let again = SearchEngine.search(query: "a", items: items.reversed(), weights: [:], maxResults: 8)
        #expect(results.map { $0.item.id } == again.map { $0.item.id })
    }

    @Test func urlPlaceholderCommandAcceptsArgument() {
        let search = LauncherItem.command(CommandItem(
            name: "GitHub", aliases: ["gh"],
            action: .url(URL(string: "https://github.com/search?q={query}")!),
            cwd: nil, terminal: false
        ))
        let plain = LauncherItem.command(CommandItem(
            name: "GitHub Home", aliases: ["ghh"],
            action: .url(URL(string: "https://github.com")!),
            cwd: nil, terminal: false
        ))
        let items = [search, plain]

        let withArgument = SearchEngine.search(query: "gh odd-frog", items: items, weights: [:], maxResults: 8)
        #expect(withArgument.first?.item.id == search.id)
        #expect(withArgument.first?.argument == "odd-frog")

        let withoutArgument = SearchEngine.search(query: "gh", items: items, weights: [:], maxResults: 8)
        #expect(withoutArgument.first?.item.id == search.id)
        #expect(withoutArgument.first?.argument == nil)

        let plainSearch = SearchEngine.search(query: "ghh something", items: items, weights: [:], maxResults: 8)
        #expect(plainSearch.allSatisfy { $0.item.id != plain.id })
    }

    @Test func emptyQueryShowsOnlyUsedItems() {
        let items = [app("Zed"), app("Alpha"), app("Mid")]
        let results = SearchEngine.search(query: "  ", items: items, weights: ["/Applications/Mid.app": 2], maxResults: 2)
        #expect(results.map { $0.item.title } == ["Mid"])
    }

    @Test func noMatchYieldsFallbacks() {
        let items = [app("Zed")]
        let template = "https://duckduckgo.com/?q={query}"
        let results = SearchEngine.search(query: "zzzz", items: items, weights: [:], maxResults: 8, searchTemplate: template)
        #expect(results.count == 1)
        guard case .quick(let quick) = results[0].item, case .webSearch = quick else {
            Issue.record("expected a webSearch fallback")
            return
        }
    }

    @Test func terminalPrefixBypassesItems() {
        let items = [app("uptime")]
        let results = SearchEngine.search(query: ">uptime", items: items, weights: [:], maxResults: 8)
        #expect(results.count == 1)
        guard case .quick(let quick) = results[0].item else {
            Issue.record("expected a quick action")
            return
        }
        #expect(quick == .terminal("uptime"))
    }
}
