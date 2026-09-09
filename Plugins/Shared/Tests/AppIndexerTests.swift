import Foundation
import Testing
@testable import OddFrogCore
@testable import BundledFeatures

struct AppIndexerTests {
    private func makeBundle(named name: String, in dir: URL) throws -> URL {
        let bundle = dir.appendingPathComponent("\(name).app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        return bundle
    }

    @Test func cacheReusesUnchangedBundles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try makeBundle(named: "Real", in: dir)

        let first = AppScanner.scan(roots: [dir], cache: AppScanner.AppScanCache())
        #expect(first.apps.map(\.name) == ["Real"])
        let path = dir.appendingPathComponent("Real.app").standardizedFileURL.resolvingSymlinksInPath().path
        guard let entry = first.cache.entries[path] else {
            Issue.record("missing cache entry for \(path)")
            return
        }

        let poisonedItem = AppItem(url: entry.item.url, name: "Cached", bundleID: entry.item.bundleID)
        var poisoned = first.cache
        poisoned.entries[path] = AppScanner.AppScanCache.Entry(modified: entry.modified, item: poisonedItem)

        let second = AppScanner.scan(roots: [dir], cache: poisoned)
        #expect(second.apps.map(\.name) == ["Cached"])

        try Data().write(to: dir.appendingPathComponent("Real.app/Contents/Info.plist"))

        let third = AppScanner.scan(roots: [dir], cache: second.cache)
        #expect(third.apps.map(\.name) == ["Real"])
        #expect(third.cache.entries[path]?.modified != second.cache.entries[path]?.modified)
    }

    @Test func cacheDropsRemovedBundles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try makeBundle(named: "Gone", in: dir)

        let first = AppScanner.scan(roots: [dir], cache: AppScanner.AppScanCache())
        #expect(!first.cache.entries.isEmpty)

        try FileManager.default.removeItem(at: bundle)

        let second = AppScanner.scan(roots: [dir], cache: first.cache)
        #expect(second.apps.isEmpty)
        #expect(second.cache.entries.isEmpty)
    }

    @Test func watchedDirectoriesIncludesSubfoldersButNotBundles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Utilities"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Some.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)

        let result = AppScanner.watchedDirectories(roots: [root])
        #expect(result.map(\.standardizedFileURL.path) == [root, root.appendingPathComponent("Utilities")].map(\.standardizedFileURL.path))
    }
}
