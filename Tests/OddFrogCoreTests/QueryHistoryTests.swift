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

    @Test func windowStaysInsideTheList() {
        #expect(QueryHistory.window(around: 0, count: 5, total: 2) == 0..<2)
        #expect(QueryHistory.window(around: 0, count: 5, total: 20) == 0..<5)
        #expect(QueryHistory.window(around: 7, count: 5, total: 20) == 5..<10)
        #expect(QueryHistory.window(around: 19, count: 5, total: 20) == 15..<20)
        #expect(QueryHistory.window(around: 0, count: 5, total: 0).isEmpty)
    }

    @Test func storeRoundTrips() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("query-history.json")
        let store = QueryHistoryStore(url: url)
        await store.record("calendar")
        await store.record("mail")
        let reloaded = QueryHistoryStore(url: url)
        #expect(await reloaded.snapshot().queries == ["mail", "calendar"])
    }
}
