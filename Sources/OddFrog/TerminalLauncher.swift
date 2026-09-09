import AppKit
import Foundation
import OddFrogCore

enum LaunchOutcome: Sendable {
    case launched
    case failed(String)
}

@MainActor
final class TerminalLauncher {
    static let scratchDirectory = StoragePaths.support.appendingPathComponent("tmp", isDirectory: true)

    func launch(command: String, cwd: URL?, name: String, kind: TerminalKind, shell: String) async -> LaunchOutcome {
        let directory = cwd?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        switch kind {
        case .agterm:
            guard let agtermctl = Self.locate("agtermctl") else {
                return await openCommandFile(bundleID: "com.apple.Terminal", command: command, cwd: directory, shell: shell)
            }
            let result = await Self.run(agtermctl, ShellCommand.agtermArguments(cwd: directory, name: name, shell: shell, command: command))
            if result.status == 0 { return .launched }
            if ShellCommand.isAgtermUnavailable(stderr: result.stderr) {
                return await openCommandFile(bundleID: "com.apple.Terminal", command: command, cwd: directory, shell: shell)
            }
            let message = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed("agtermctl exited \(result.status): \(message)")
        case .terminal:
            return await openCommandFile(bundleID: "com.apple.Terminal", command: command, cwd: directory, shell: shell)
        case .iterm:
            return await openCommandFile(bundleID: "com.googlecode.iterm2", command: command, cwd: directory, shell: shell)
        }
    }

    private func openCommandFile(bundleID: String, command: String, cwd: String, shell: String) async -> LaunchOutcome {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failed("terminal app \(bundleID) is not installed")
        }
        let fm = FileManager.default
        let file = Self.scratchDirectory.appendingPathComponent("\(UUID().uuidString).command")
        do {
            try fm.createDirectory(at: Self.scratchDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let contents = ShellCommand.commandFileContents(shell: shell, cwd: cwd, command: command)
            try contents.write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        } catch {
            return .failed("could not write launcher script: \(error.localizedDescription)")
        }
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                continuation.resume(returning: error.map { .failed($0.localizedDescription) } ?? .launched)
            }
        }
    }

    static func cleanupStaleFiles(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: scratchDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }

    static func locate(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map(String.init)
        }
        for dir in candidates {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    struct RunResult: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ executable: URL, _ arguments: [String]) async -> RunResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do {
                try process.run()
            } catch {
                continuation.resume(returning: RunResult(status: -1, stdout: "", stderr: error.localizedDescription))
                return
            }
            let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            continuation.resume(returning: RunResult(status: process.terminationStatus, stdout: stdout, stderr: stderr))
        }
    }
}
