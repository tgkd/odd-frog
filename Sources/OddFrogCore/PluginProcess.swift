import Foundation
import Darwin
import OddFrogPluginAPI

/// Each provider owns a process group, including descendants that keep stdout open after its exit.
private final class ProviderChild: @unchecked Sendable {
    let channel: NDJSONChannel
    // NSPipe owns its descriptors even when individual FileHandles are retained.
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var reaped = false
    init(executable: URL) throws {
        let input = Pipe(), output = Pipe()
        stdinPipe = input; stdoutPipe = output
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir(&actions, executable.deletingLastPathComponent().path)
        let argv = [strdup(executable.path), nil]
        let env = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; env.forEach { free($0) } }
        var spawned: pid_t = 0
        let code = argv.withUnsafeBufferPointer { args in env.withUnsafeBufferPointer { vars in
            posix_spawn(&spawned, executable.path, &actions, &attributes,
                        UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: vars.baseAddress!))
        } }
        guard code == 0 else { throw RPCError("protocol", "Could not start provider: \(String(cString: strerror(code))).") }
        pid = spawned
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        signal(SIGPIPE, SIG_IGN)
        channel = NDJSONChannel(input: output.fileHandleForReading, output: input.fileHandleForWriting)
    }
    func exited() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if reaped { return true }
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid {
            // Kill descendants even when the group leader exited normally.
            kill(-pid, SIGKILL); reaped = true; return true
        }
        return false
    }
    func stop() {
        lock.lock()
        if !reaped {
            kill(-pid, SIGKILL)
            let child = pid
            reaped = true
            DispatchQueue.global().async {
                var status: Int32 = 0
                while waitpid(child, &status, 0) < 0 && errno == EINTR {}
            }
        }
        lock.unlock()
        channel.close()
    }
    deinit { stop() }
}

public actor PluginProcess {
    public typealias Service = @Sendable (String, JSONValue) async throws -> JSONValue
    public typealias Event = @Sendable (String, JSONValue) async -> Void
    private struct Pending {
        var continuation: CheckedContinuation<JSONValue, any Error>
        var service: Service
        var deadline: Task<Void, Never>?
    }
    private let executable: URL
    private let persistent: Bool
    private let event: Event
    private var runToken = UUID()
    private var child: ProviderChild?
    private var reader: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var retired = Set<String>()
    private var serviceTasks: [String: (owner: String, task: Task<Void, Never>)] = [:]
    private var failure: RPCError?
    public init(executable: URL, persistent: Bool, event: @escaping Event = { _, _ in }) {
        self.executable = executable; self.persistent = persistent; self.event = event
    }
    private func start() throws {
        if let failure { throw failure }
        guard child == nil else { return }
        let child = try ProviderChild(executable: executable)
        self.child = child
        let token = UUID(); runToken = token
        reader = Task { [weak self] in
            do {
                for try await message in child.channel.messages { await self?.receive(message, token: token) }
                await self?.ended(token: token)
            } catch { await self?.readFailed(error, token: token) }
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                if child.exited() {
                    // Allow already-buffered final responses to be consumed before EOF is diagnosed.
                    try? await Task.sleep(for: .milliseconds(50))
                    if !Task.isCancelled { await self?.ended(token: token) }
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
    public func request(_ method: String, params: JSONValue = .object([:]), timeout: Duration? = .seconds(2),
                        service: @escaping Service = { _, _ in throw RPCError("capability", "No services declared.") }) async throws -> JSONValue {
        try Task.checkCancellation()
        try start()
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var entry = Pending(continuation: continuation, service: service)
                if let timeout {
                    entry.deadline = Task { [weak self] in
                        do { try await Task.sleep(for: timeout) } catch { return }
                        await self?.fail(RPCError("protocol", "Provider \(method) timed out. Use Reload Plugins to retry."))
                    }
                }
                pending[id] = entry
                send(PluginEnvelope(id: id, method: method, params: params))
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func receive(_ message: PluginEnvelope, token: UUID) async {
        guard token == runToken else { return }
        if let method = message.method {
            guard let id = message.id else {
                guard ["catalogChanged", "queryInvalidated", "messageDelta"].contains(method) else { fail(RPCError("protocol", "Unknown provider event.")); return }
                await event(method, message.params ?? .null); return
            }
            if method == "host.service", let owner = message.params?["requestID"].string, retired.contains(owner) {
                send(PluginEnvelope(id: id, error: RPCError("cancelled", "The owning operation is no longer active.")))
                return
            }
            guard method == "host.service", let owner = message.params?["requestID"].string,
                  let entry = pending[owner], let capability = message.params?["capability"].string,
                  serviceTasks[id] == nil else { fail(RPCError("protocol", "Uncorrelated host service request.")); return }
            let params = message.params?["params"] ?? .object([:])
            serviceTasks[id] = (owner, Task { [weak self] in
                do {
                    let result = try await entry.service(capability, params)
                    try Task.checkCancellation()
                    await self?.serviceReply(id, owner: owner, result: result, error: nil)
                } catch {
                    await self?.serviceReply(id, owner: owner, result: nil,
                                             error: error as? RPCError ?? RPCError("service", String(describing: error)))
                }
            })
            return
        }
        guard let id = message.id else { fail(RPCError("protocol", "Response has no request ID.")); return }
        guard let entry = pending.removeValue(forKey: id) else {
            if retired.contains(id) { return }
            fail(RPCError("protocol", "Response has an unknown request ID.")); return
        }
        entry.deadline?.cancel(); retire(id)
        for (key, value) in serviceTasks where value.owner == id { value.task.cancel(); serviceTasks.removeValue(forKey: key) }
        if let error = message.error { entry.continuation.resume(throwing: error) }
        else { entry.continuation.resume(returning: message.result ?? .null) }
        if !persistent { stopChild() }
    }
    private func serviceReply(_ id: String, owner: String, result: JSONValue?, error: RPCError?) {
        serviceTasks.removeValue(forKey: id)
        guard pending[owner] != nil else { return }
        send(PluginEnvelope(id: id, result: result, error: error))
    }
    private func send(_ envelope: PluginEnvelope) {
        let token = runToken
        child?.channel.enqueue(envelope) { [weak self] error in
            Task { await self?.readFailed(error, token: token) }
        }
    }
    private func retire(_ id: String) {
        if retired.count > 1024 { retired.removeAll() }
        retired.insert(id)
    }
    private func cancel(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.deadline?.cancel(); retire(id)
        for (key, value) in serviceTasks where value.owner == id { value.task.cancel(); serviceTasks.removeValue(forKey: key) }
        send(PluginEnvelope(method: "cancel", params: .object(["requestID": .string(id)])))
        entry.continuation.resume(throwing: CancellationError())
        if !persistent { stopChild() }
    }
    private func readFailed(_ error: any Error, token: UUID) {
        guard token == runToken else { return }; fail(RPCError("protocol", String(describing: error)))
    }
    private func ended(token: UUID) {
        guard token == runToken, child != nil else { return }
        fail(RPCError("protocol", "Provider exited unexpectedly. Use Reload Plugins to retry."))
    }
    private func fail(_ error: RPCError) {
        guard failure == nil else { return }
        failure = error
        for entry in pending.values { entry.deadline?.cancel(); entry.continuation.resume(throwing: error) }
        pending.removeAll(); stopChild()
        Task { await event("failure", .string(error.message)) }
    }
    private func stopChild() {
        runToken = UUID()
        reader?.cancel(); monitor?.cancel(); reader = nil; monitor = nil
        for value in serviceTasks.values { value.task.cancel() }; serviceTasks.removeAll()
        child?.stop(); child = nil
    }
    public func stop() {
        send(PluginEnvelope(method: "shutdown", params: .object([:])))
        for id in Array(pending.keys) { cancel(id) }
        stopChild()
    }
}
