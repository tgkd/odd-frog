import Foundation
import Testing
import OddFrogPluginAPI
@testable import FilesPluginCore

struct FilesProviderTests {
    private func request(_ text: String, max: Int = 8) -> PluginQuery {
        PluginQuery(query: text, fullQuery: "f " + text, maxResults: max)
    }

    @Test func rowsOpenAndRevealThePath() {
        let hits = [FileHit(root: "/Users/me/Developer", relativePath: "app/main.swift", isDirectory: false, score: 10)]
        let rows = FilesProvider.respond(to: request("main"), state: .ready(scanning: false), hits: hits, home: "/Users/me")
        #expect(rows.count == 1)
        #expect(rows[0].title == "main.swift")
        #expect(rows[0].subtitle == "~/Developer/app")
        #expect(rows[0].icon == "file:/Users/me/Developer/app/main.swift")
                #expect(rows[0].secondary?.kind == .reveal)
        let remember = PluginAfter("track", payload: .object([
            "root": .string("/Users/me/Developer"), "path": .string("app/main.swift"), "query": .string("main"),
        ]))
        #expect(rows[0].primary == PluginAction(.openPath, "/Users/me/Developer/app/main.swift", after: remember))
        #expect(rows[0].secondary?.after == remember)
    }

    @Test func rootSearchReturnsHitsWithoutNotices() {
        var root = request("main", max: 3); root.root = true
        let hits = [FileHit(root: "/r", relativePath: "main.swift", isDirectory: false, score: 10)]
        #expect(FilesProvider.respond(to: root, state: .ready(scanning: false), hits: hits, home: "/h").map(\.title) == ["main.swift"])
        #expect(FilesProvider.respond(to: root, state: .ready(scanning: true), hits: [], home: "/h").isEmpty)
        #expect(FilesProvider.respond(to: root, state: .noFolders, hits: [], home: "/h").isEmpty)
        #expect(FilesProvider.respond(to: root, state: .unavailable("x"), hits: [], home: "/h").isEmpty)
    }

    @Test func mergeKeepsBestScorePerPathAndSortsDescending() {
        let merged = FilesProvider.merge([
            [FileHit(root: "", relativePath: "a", isDirectory: false, score: 5), FileHit(root: "", relativePath: "b", isDirectory: true, score: 9)],
            [FileHit(root: "", relativePath: "a", isDirectory: false, score: 7)],
        ])
        #expect(merged.map(\.path) == ["/b", "/a"])
        #expect(merged[1].score == 7)
    }

    @Test func respectsMaxResults() {
        let hits = (0..<20).map { FileHit(root: "", relativePath: "f\($0)", isDirectory: false, score: 100 - $0) }
        let rows = FilesProvider.respond(to: request("f", max: 5), state: .ready(scanning: false), hits: hits, home: "/h")
        #expect(rows.count == 5)
    }

    @Test func stateRowsExplainWhatIsWrong() {
        let unavailable = FilesProvider.respond(to: request("x"), state: .unavailable("missing"), hits: [], home: "/h")
        #expect(unavailable[0].subtitle == "missing")
        let none = FilesProvider.respond(to: request("x"), state: .noFolders, hits: [], home: "/h")
        #expect(none[0].id == "no-folders")
        let indexing = FilesProvider.respond(to: request("x"), state: .ready(scanning: true), hits: [], home: "/h")
        #expect(indexing[0].title == "Indexing your folders…")
        let hint = FilesProvider.respond(to: request(" "), state: .ready(scanning: false), hits: [], home: "/h")
        #expect(hint[0].id == "hint")
    }
}
