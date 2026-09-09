import Foundation
import OddFrogPluginAPI

/// One-shot transport. File-backed stdio avoids pipe deadlocks and keeps event data out of logs.
/// A private temporary directory is removed on success, failure, and cancellation.
public enum PluginProcess {
    public static func exchange(executable: URL, request: PluginRequest,
                                timeout: Duration = .seconds(2)) async throws -> PluginResponse {
        let control = ProviderProcessControl()
        return try await withTaskCancellationHandler {
            try await run(executable: executable, request: request, timeout: timeout, control: control)
        } onCancel: {
            // Cancellation must stop the process synchronously, including when the app is quitting
            // and its main run loop will no longer resume the query task.
            control.cancel()
        }
    }

    private static func run(executable: URL, request: PluginRequest, timeout: Duration,
                            control: ProviderProcessControl) async throws -> PluginResponse {
        try Task.checkCancellation()
        let input = try PluginProtocol.encoder().encode(request)
        guard input.count <= PluginProtocol.maxBytes else { throw PluginError.message("Plugin input exceeds four MiB.") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("odd-frog-provider-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        let inputURL = root.appendingPathComponent("input")
        let outputURL = root.appendingPathComponent("output")
        let errorURL = root.appendingPathComponent("error")
        try input.write(to: inputURL)
        fm.createFile(atPath: outputURL.path, contents: nil)
        fm.createFile(atPath: errorURL.path, contents: nil)
        let stdin = try FileHandle(forReadingFrom: inputURL)
        let stdout = try FileHandle(forWritingTo: outputURL)
        let stderr = try FileHandle(forWritingTo: errorURL)
        defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }
        let process = control.process
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try control.start()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        func checkSize() throws {
            for url in [outputURL, errorURL] {
                let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size <= PluginProtocol.maxBytes else { throw PluginError.message("Plugin output exceeds four MiB.") }
            }
        }
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard clock.now < deadline else { throw PluginError.message("Plugin timed out. Use Reload Plugins to retry.") }
                try checkSize()
                try await Task.sleep(for: .milliseconds(20))
            }
            try Task.checkCancellation()
            try checkSize()
        } catch {
            control.cancel()
            process.waitUntilExit()
            throw error
        }
        guard process.terminationStatus == 0 else {
            throw PluginError.message("Plugin exited with status \(process.terminationStatus). Use Reload Plugins to retry.")
        }
        let response: PluginResponse
        do {
            response = try PluginProtocol.decoder().decode(PluginResponse.self, from: Data(contentsOf: outputURL))
        } catch { throw PluginError.message("Plugin returned invalid JSON: \(error.localizedDescription)") }
        guard response.apiVersion == PluginProtocol.version, response.id == request.id else {
            throw PluginError.message("Plugin response version or request ID does not match.")
        }
        guard response.items.count <= 50, Set(response.items.map(\.id)).count == response.items.count,
              response.items.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }) else {
            throw PluginError.message("Plugin returned invalid or duplicate items.")
        }
        return response
    }
}

private final class ProviderProcessControl: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var started = false

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
        started = true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if started, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
