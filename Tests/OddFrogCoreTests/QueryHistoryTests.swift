import Foundation
import Testing
@testable import OddFrogCore

struct QueryHistoryTests {
    @Test func newestFirstWithoutDuplicates() {
        var history = QueryHistory()
        history.record("safari")
        history.record("notes")
        history.record("safari")
        #expect(history.queries == ["safari", "notes"])
    }

    @Test func ignoresBlankButKeepsTriggerSpacing() {
        var history = QueryHistory()
        history.record("   ")
        history.record("")
        history.record("clip ")
        #expect(history.queries == ["clip "])
    }

    @Test func dropsOldestPastLimit() {
        var history = QueryHistory()
        for n in 0...QueryHistory.limit { history.record("q\(n)") }
        #expect(history.queries.count == QueryHistory.limit)
        #expect(history.queries.first == "q\(QueryHistory.limit)")
        #expect(!history.queries.contains("q0"))
    }

    @Test func trailingWhitespaceDoesNotMakeADuplicate() {
        var history = QueryHistory()
        history.record("mail")
        history.record("notes")
        history.record("mail ")
        #expect(history.queries == ["mail ", "notes"])
        history.record("mail")
        #expect(history.queries == ["mail", "notes"])
    }

    @Test func leadingWhitespaceStillDiffers() {
        var history = QueryHistory()
        history.record("mail")
        history.record(" mail")
        #expect(history.queries == [" mail", "mail"])
    }

    @Test func olderStopsAtTheOldestEntry() {
        #expect(QueryHistory.older(than: nil, total: 3) == 0)
        #expect(QueryHistory.older(than: 0, total: 3) == 1)
        #expect(QueryHistory.older(than: 2, total: 3) == nil)
        #expect(QueryHistory.older(than: nil, total: 0) == nil)
    }

    @Test func newerLeavesHistoryPastTheNewestEntry() {
        #expect(QueryHistory.newer(than: 2) == 1)
        #expect(QueryHistory.newer(than: 1) == 0)
        #expect(QueryHistory.newer(than: 0) == nil)
    }

    @Test func windowStaysInsideTheList() {
        #expect(QueryHistory.window(around: 0, count: 5, total: 2) == 0..<2)
        #expect(QueryHistory.window(around: 0, count: 5, total: 20) == 0..<5)
        #expect(QueryHistory.window(around: 7, count: 5, total: 20) == 5..<10)
        #expect(QueryHistory.window(around: 19, count: 5, total: 20) == 15..<20)
        #expect(QueryHistory.window(around: 0, count: 5, total: 0).isEmpty)
    }

    @Test func storeKeepsQueriesInMemoryOnly() async throws {
        let store = QueryHistoryStore()
        await store.record("calendar")
        await store.record("mail")
        #expect(await store.snapshot().queries == ["mail", "calendar"])
        #expect(await QueryHistoryStore().snapshot().queries.isEmpty)
    }

    @Test func removeLegacyFileDeletesAnExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("odd-frog-legacy-\(UUID().uuidString).json")
        try Data("{\"queries\":[\"secret\"]}".utf8).write(to: url)
        QueryHistoryStore.removeLegacyFile(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func removeLegacyFileAcceptsAMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("odd-frog-legacy-\(UUID().uuidString).json")
        QueryHistoryStore.removeLegacyFile(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
