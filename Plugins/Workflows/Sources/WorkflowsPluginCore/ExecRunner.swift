import Foundation
import Darwin
import OddFrogPluginAPI

public struct ExecRequest: Sendable, Equatable {
    public var executable: String
    public var argv: [String]
    public var cwd: String
    public var environment: [String: String]
    public init(executable: String, argv: [String], cwd: String, environment: [String: String]) {
        self.executable = executable; self.argv = argv; self.cwd = cwd; self.environment = environment
    }
}

public struct ExecResult: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exit: Int
    public init(stdout: String = "", stderr: String = "", exit: Int = 0) {
        self.stdout = stdout; self.stderr = stderr; self.exit = exit
    }
}

public protocol ExecRunning: Sendable {
    func run(_ request: ExecRequest) async throws -> ExecResult
}

public enum CommandSearch {
    public static let defaultPath = "/opt/homebrew/bin:/usr/local/bin"

    public static func effectivePath(setting: String?, appPath: String) -> String {
        let extra = (setting ?? defaultPath).trimmingCharacters(in: .whitespacesAndNewlines)
        return [extra, appPath].filter { !$0.isEmpty }.joined(separator: ":")
    }

    public static func resolve(_ command: String, cwd: String, path: String) -> String? {
        if command.hasPrefix("/") {
            return command
        }
        if command.contains("/") {
            return joined(cwd, command)
        }
        for folder in path.split(separator: ":").map(String.init) where folder.hasPrefix("/") {
            let candidate = (folder as NSString).appendingPathComponent(command)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue,
               access(candidate, X_OK) == 0 {
                return candidate
            }
        }
        return nil
    }

    static func joined(_ folder: String, _ relative: String) -> String {
        var parts: [Substring] = []
        for part in (folder + "/" + relative).split(separator: "/") {
            switch part {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }
}

public struct ProcessGroupRunner: ExecRunning {
    public static let outputLimit = 1 << 20
    public var terminateGrace: Duration

    public init(terminateGrace: Duration = .seconds(2)) {
        self.terminateGrace = terminateGrace
    }

    public func run(_ request: ExecRequest) async throws -> ExecResult {
        try Task.checkCancellation()
        let child = try SpawnedGroup(request)
        let grace = terminateGrace
        let status = await withTaskCancellationHandler {
            await child.waitForExit()
        } onCancel: {
            child.terminate(grace: grace)
        }
        async let stdout = child.stdout.drain()
        async let stderr = child.stderr.drain()
        let output = await (stdout, stderr)
        if child.wasTerminated {
            throw CancellationError()
        }
        return ExecResult(stdout: String(decoding: output.0, as: UTF8.self),
                          stderr: String(decoding: output.1, as: UTF8.self), exit: status)
    }
}

private final class SpawnedGroup: @unchecked Sendable {
    let pid: pid_t
    let stdout: PipeReader
    let stderr: PipeReader
    private let lock = NSLock()
    private var reaped = false
    private var terminated = false

    init(_ request: ExecRequest) throws {
        let out = Pipe(), err = Pipe()
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        posix_spawn_file_actions_addchdir(&actions, request.cwd)
        let argv = request.argv.map { strdup($0) } + [nil]
        let env = request.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; env.forEach { free($0) } }
        var spawned: pid_t = 0
        let code = argv.withUnsafeBufferPointer { args in env.withUnsafeBufferPointer { vars in
            posix_spawn(&spawned, request.executable, &actions, &attributes,
                        UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: vars.baseAddress!))
        } }
        try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
        guard code == 0 else {
            throw RPCError("workflow", "Could not start \(request.executable): \(String(cString: strerror(code))).")
        }
        pid = spawned
        stdout = PipeReader(out)
        stderr = PipeReader(err)
        stdout.start()
        stderr.start()
    }

    var wasTerminated: Bool {
        lock.lock(); defer { lock.unlock() }
        return terminated
    }

    func waitForExit() async -> Int {
        await withCheckedContinuation { continuation in
            let pid = pid
            DispatchQueue.global().async {
                var info = siginfo_t()
                while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
                self.lock.lock()
                kill(-pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                self.reaped = true
                self.lock.unlock()
                self.stdout.finishSoon()
                self.stderr.finishSoon()
                continuation.resume(returning: SpawnedGroup.exitCode(status))
            }
        }
    }

    func terminate(grace: Duration) {
        lock.lock()
        terminated = true
        if !reaped {
            kill(-pid, SIGTERM)
        }
        lock.unlock()
        let seconds = Double(grace.components.seconds) + Double(grace.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            self.lock.lock()
            if !self.reaped {
                kill(-self.pid, SIGKILL)
            }
            self.lock.unlock()
        }
    }

    private static func exitCode(_ status: Int32) -> Int {
        let signal = status & 0x7f
        if signal == 0 {
            return Int((status >> 8) & 0xff)
        }
        return 128 + Int(signal)
    }
}

private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false
    private var deadline: Date?
    private var waiters: [CheckedContinuation<Data, Never>] = []

    init(_ pipe: Pipe) {
        self.pipe = pipe
    }

    func start() {
        let fd = pipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global().async {
            let size = 65536
            var chunk = [UInt8](repeating: 0, count: size)
            while true {
                if self.pastDeadline() {
                    break
                }
                var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&poller, 1, 100)
                if ready < 0 {
                    if errno == EINTR { continue }
                    break
                }
                if ready == 0 {
                    continue
                }
                let count = read(fd, &chunk, size)
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    break
                }
                if count == 0 {
                    break
                }
                self.append(chunk[0..<count])
            }
            try? self.pipe.fileHandleForReading.close()
            self.finish()
        }
    }

    func finishSoon() {
        lock.lock()
        deadline = Date().addingTimeInterval(1)
        lock.unlock()
    }

    func drain() async -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                let data = buffer
                lock.unlock()
                continuation.resume(returning: data)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func pastDeadline() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let deadline else { return false }
        return Date() > deadline
    }

    private func append(_ bytes: ArraySlice<UInt8>) {
        lock.lock()
        buffer.append(contentsOf: bytes)
        if buffer.count > ProcessGroupRunner.outputLimit {
            buffer = Data(buffer.suffix(ProcessGroupRunner.outputLimit))
        }
        lock.unlock()
    }

    private func finish() {
        lock.lock()
        finished = true
        let data = buffer
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: data) }
    }
}
