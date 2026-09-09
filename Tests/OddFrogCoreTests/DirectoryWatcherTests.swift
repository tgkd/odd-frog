import Foundation
import Testing
@testable import OddFrogCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int { lock.withLock { count } }

    func wait(for target: Int, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if value >= target { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

struct DirectoryWatcherTests {
    private func makeExecutable(in root: URL, body: String) throws -> URL {
        let file = root.appendingPathComponent("provider")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func run(_ executable: URL) throws {
        let process = Process()
        process.executableURL = executable
        try process.run()
        process.waitUntilExit()
    }

    @Test func runningAWatchedProviderDoesNotRestartIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("odd-frog-watch-exec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try makeExecutable(in: root, body: "exit 0")
        let counter = Counter()
        let watcher = DirectoryWatcher(debounce: 0.05)
        watcher.watch([root, executable]) { counter.increment() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(150))
        for _ in 0..<3 { try run(executable) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == 0)
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: executable)
        #expect(await counter.wait(for: 1))
    }
}
