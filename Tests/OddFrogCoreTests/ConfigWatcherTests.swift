import Foundation
import Testing
@testable import OddFrogCore

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [Data] = []

    func push(_ data: Data) {
        lock.withLock { received.append(data) }
    }

    var all: [String] {
        lock.withLock { received.map { String(decoding: $0, as: UTF8.self) } }
    }

    private var count: Int { lock.withLock { received.count } }

    func wait(count target: Int, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if count >= target { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

struct ConfigWatcherTests {
    private func makeSandbox() throws -> (root: URL, dir: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-watch-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("odd-frog")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.toml")
        try Data("v1".utf8).write(to: file)
        return (root, dir, file)
    }

    private func atomicSave(_ text: String, to file: URL) throws {
        let tmp = file.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        try Data(text.utf8).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }

    @Test func inPlaceOverwrite() async throws {
        let (root, _, file) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox()
        let watcher = ConfigWatcher(path: file, debounce: 0.05, retry: 0.1)
        watcher.start(lastContents: Data("v1".utf8)) { inbox.push($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("v2".utf8))
        try handle.close()
        #expect(await inbox.wait(count: 1))
        #expect(inbox.all == ["v2"])
    }

    @Test func atomicRename() async throws {
        let (root, _, file) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox()
        let watcher = ConfigWatcher(path: file, debounce: 0.05, retry: 0.1)
        watcher.start(lastContents: Data("v1".utf8)) { inbox.push($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        try atomicSave("v2", to: file)
        #expect(await inbox.wait(count: 1))
        try atomicSave("v3", to: file)
        #expect(await inbox.wait(count: 2))
        #expect(inbox.all == ["v2", "v3"])
    }

    @Test func deleteAndRecreate() async throws {
        let (root, _, file) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox()
        let watcher = ConfigWatcher(path: file, debounce: 0.05, retry: 0.1)
        watcher.start(lastContents: Data("v1".utf8)) { inbox.push($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(300))
        try Data("v2".utf8).write(to: file)
        #expect(await inbox.wait(count: 1))
        try atomicSave("v3", to: file)
        #expect(await inbox.wait(count: 2))
        #expect(inbox.all == ["v2", "v3"])
    }

    @Test func replaceWholeDirectoryThenKeepWatching() async throws {
        let (root, dir, file) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox()
        let watcher = ConfigWatcher(path: file, debounce: 0.05, retry: 0.1)
        watcher.start(lastContents: Data("v1".utf8)) { inbox.push($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("v2".utf8).write(to: staging.appendingPathComponent("config.toml"))
        let old = root.appendingPathComponent("old")
        try FileManager.default.moveItem(at: dir, to: old)
        try FileManager.default.moveItem(at: staging, to: dir)
        #expect(await inbox.wait(count: 1))
        try atomicSave("v3", to: file)
        #expect(await inbox.wait(count: 2))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("v4".utf8))
        try handle.close()
        #expect(await inbox.wait(count: 3))
        #expect(inbox.all == ["v2", "v3", "v4"])
    }

    @Test func identicalBytesDoNotFire() async throws {
        let (root, _, file) = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox()
        let watcher = ConfigWatcher(path: file, debounce: 0.05, retry: 0.1)
        watcher.start(lastContents: Data("v1".utf8)) { inbox.push($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))
        try atomicSave("v1", to: file)
        #expect(await inbox.wait(count: 1, timeout: 0.5) == false)
    }
}
