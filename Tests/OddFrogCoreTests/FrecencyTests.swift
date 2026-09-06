import Foundation
import Testing
@testable import OddFrogCore

struct FrecencyTests {
    let day: TimeInterval = 86_400

    @Test func fortyTwoDayOldHundredLosesToThreeToday() {
        var table = FrecencyTable()
        let now = Date(timeIntervalSince1970: 10_000_000)
        table.entries["old"] = FrecencyEntry(weight: 100, lastUsed: now.addingTimeInterval(-42 * day))
        for _ in 0..<3 { table.record("new", at: now) }
        let old = table.weight(for: "old", at: now)
        #expect(abs(old - 1.5625) < 1e-9)
        #expect(table.weight(for: "new", at: now) == 3)
        #expect(old < table.weight(for: "new", at: now))
    }

    @Test func thirtyDayOldHundredStillWins() {
        var table = FrecencyTable()
        let now = Date(timeIntervalSince1970: 10_000_000)
        table.entries["old"] = FrecencyEntry(weight: 100, lastUsed: now.addingTimeInterval(-30 * day))
        for _ in 0..<3 { table.record("new", at: now) }
        let old = table.weight(for: "old", at: now)
        #expect(abs(old - 5.127095975) < 1e-6)
        #expect(old > table.weight(for: "new", at: now))
    }

    @Test func recordDecaysThenIncrements() {
        var table = FrecencyTable()
        let t0 = Date(timeIntervalSince1970: 0)
        table.record("x", at: t0)
        table.record("x", at: t0.addingTimeInterval(7 * day))
        #expect(abs(table.weight(for: "x", at: t0.addingTimeInterval(7 * day)) - 1.5) < 1e-9)
    }

    @Test func storeRoundTrips() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("frecency.json")
        let store = FrecencyStore(url: url)
        let now = Date(timeIntervalSince1970: 5_000_000)
        await store.record("a", at: now)
        await store.record("a", at: now)
        let reloaded = FrecencyStore(url: url)
        let weights = await reloaded.decayedWeights(at: now)
        #expect(weights["a"] == 2)
        try? FileManager.default.removeItem(at: dir)
    }
}
