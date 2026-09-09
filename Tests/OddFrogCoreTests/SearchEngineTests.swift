import Foundation
import Testing
@testable import OddFrogCore
import BundledFeatures

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
    @Test func windowKindFindsAndNarrowsActions() {
        let windows = WindowAction.all.map { LauncherItem.window(WindowItem(action: $0)) }
        let items = windows + [app("Safari"), cmd("Build")]
        let grouped = SearchEngine.search(query: "  WINDOW  ", items: items, weights: [:], maxResults: 20)
        #expect(Set(grouped.map { $0.item.id }) == Set(windows.map(\.id)))
        #expect(grouped.allSatisfy { !$0.exactAlias && $0.argument == nil })
        let narrowed = SearchEngine.search(query: "Window   left", items: items, weights: [:], maxResults: 20)
        #expect(Set(narrowed.map { $0.item.title }) == ["Left ½", "Left ⅔"])
        let plain = SearchEngine.search(query: "left", items: items, weights: [:], maxResults: 20)
        #expect(narrowed == plain)
        #expect(SearchEngine.search(query: "windowed", items: windows, weights: [:], maxResults: 20).isEmpty)
        #expect(SearchEngine.search(query: "window", items: windows, weights: [:], maxResults: 3).count == 3)
    }

    @Test func commandKindsAreSearchable() {
        let folder = LauncherItem.command(CommandItem(name: "Projects", aliases: ["pj"], action: .path(URL(fileURLWithPath: "/tmp/projects")), cwd: nil, terminal: false))
        let link = LauncherItem.command(CommandItem(name: "GitHub", aliases: ["gh"], action: .url(URL(string: "https://github.com")!), cwd: nil, terminal: false))
        let shell = cmd("Build")
        let terminal = LauncherItem.command(CommandItem(name: "Deploy", aliases: [], action: .shell("true"), cwd: nil, terminal: true))
        let items = [folder, link, shell, terminal, app("Safari")]
        for (query, expected) in [("folder", folder), ("folder pj", folder), ("URL gh", link), ("shell build", shell), ("terminal", terminal)] {
            let results = SearchEngine.search(query: query, items: items, weights: [:], maxResults: 20)
            #expect(results.map { $0.item.id } == [expected.id])
        }
    }

    @Test func kindPrefixesPreserveArguments() {
        let script = LauncherItem.script(ScriptItem(url: URL(fileURLWithPath: "/tmp/kill-port.sh"), title: "Kill Port", mode: .silent, icon: nil, package: nil, argument: ScriptArgument(placeholder: "port", optional: false), aliases: ["kp"]))
        let link = LauncherItem.command(CommandItem(name: "GitHub", aliases: ["gh"], action: .url(URL(string: "https://github.com/search?q={query}")!), cwd: nil, terminal: false))
        let items = [script, link]
        for (query, expected, argument) in [("script kp 3000", script, "3000"), ("url gh odd frog", link, "odd frog")] {
            let results = SearchEngine.search(query: query, items: items, weights: [:], maxResults: 20)
            #expect(results.count == 1)
            #expect(results.first?.item.id == expected.id)
            #expect(results.first?.argument == argument)
            #expect(results.first?.exactAlias == true)
        }
        let grouped = SearchEngine.search(query: "script", items: items, weights: [:], maxResults: 20)
        #expect(grouped.first?.item.id == script.id)
        #expect(grouped.first?.argument == nil)
        #expect(SearchEngine.search(query: "script nonexistent", items: items, weights: [:], maxResults: 20).isEmpty)
        let aliased = script.withAliases(["script stop"])
        let originalAlias = SearchEngine.search(query: "script stop 3000", items: [aliased], weights: [:], maxResults: 20)
        #expect(originalAlias.first?.item.id == script.id)
        #expect(originalAlias.first?.argument == "3000")
        #expect(originalAlias.first?.exactAlias == true)
    }

    @Test func explicitAliasesKeepPriorityOverKindMatches() {
        let window = LauncherItem.window(WindowItem(action: .tidy, aliases: ["window arrange", "cascade"]))
        let custom = cmd("Custom", aliases: ["window"])
        let items = [window, custom]
        let grouped = SearchEngine.search(query: "window", items: items, weights: [window.id: 1000], maxResults: 20)
        #expect(grouped.first?.item.id == custom.id)
        for query in ["window arrange", "window cascade", "cascade"] {
            let results = SearchEngine.search(query: query, items: items, weights: [:], maxResults: 20)
            #expect(results.first?.item.id == window.id)
            #expect(results.first?.exactAlias == true)
        }
    }

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
        let weights = ["plugin:applications:/Applications/Xcode.app": 3.0]
        let before = SearchEngine.search(query: "code", items: items, weights: weights, maxResults: 8).map { $0.item.title }
        let after = SearchEngine.search(query: "code", items: items + [app("Codesign Helper Thing")], weights: weights, maxResults: 8)
            .map { $0.item.title }
            .filter { $0 != "Codesign Helper Thing" }
        #expect(before == after)
    }

    @Test func maxResultsNeverChangesTop() {
        let items = (0..<20).map { app("Code \($0)") } + [app("Xcode")]
        let weights = ["plugin:applications:/Applications/Xcode.app": 50.0]
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
        let results = SearchEngine.search(query: "  ", items: items, weights: ["plugin:applications:/Applications/Mid.app": 2], maxResults: 2)
        #expect(results.map { $0.item.title } == ["Mid"])
    }

    @Test func hostSearchOnlyRanksSuppliedItems() {
        #expect(SearchEngine.search(query: "2+2", items: [app("Zed")], weights: [:], maxResults: 8).isEmpty)
    }

    @Test func bareNumberStillSearches() {
        let results = SearchEngine.search(query: "1", items: [app("1Password")], weights: [:], maxResults: 8)
        #expect(results.map { $0.item.title } == ["1Password"])
    }
}
