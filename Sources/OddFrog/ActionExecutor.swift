import AppKit
import Foundation
import OddFrogCore

final class TailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maxBytes: Int
    private let maxLines: Int

    init(maxBytes: Int = 8192, maxLines: Int = 20) {
        self.maxBytes = maxBytes
        self.maxLines = maxLines
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        if data.count > maxBytes {
            data = data.suffix(maxBytes)
        }
    }

    var tail: String {
        lock.lock()
        defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var kept = lines.suffix(maxLines)
        while let last = kept.last, last.isEmpty { kept.removeLast() }
        return kept.joined(separator: "\n")
    }
}

private final class BackgroundRun: @unchecked Sendable {
    let id = UUID()
    let process = Process()
    let stdout = TailBuffer()
    let stderr = TailBuffer()
    private let lock = NSLock()
    private var exited = false
    private var pendingStreams = 0
    private var finished = false
    var onFinish: (@Sendable (Int32, String, String) -> Void)?

    func attach(_ pipe: Pipe, to buffer: TailBuffer) {
        lock.lock(); pendingStreams += 1; lock.unlock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.streamEnded()
            } else {
                buffer.append(chunk)
            }
        }
    }

    func markExited() {
        lock.lock(); exited = true; lock.unlock()
        finishIfReady()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in self?.forceFinish() }
    }

    private func streamEnded() {
        lock.lock(); pendingStreams -= 1; lock.unlock()
        finishIfReady()
    }

    private func forceFinish() {
        lock.lock(); pendingStreams = 0; lock.unlock()
        finishIfReady()
    }

    private func finishIfReady() {
        lock.lock()
        guard exited, pendingStreams <= 0, !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        onFinish?(process.terminationStatus, stdout.tail, stderr.tail)
    }
}

@MainActor
final class ActionExecutor {
    var config: Config
    let frecency: FrecencyStore
    let notifier: Notifier
    let terminals = TerminalLauncher()
    var onFailure: ((String) -> Void)?
    var onRecorded: (() -> Void)?
    private var running: [UUID: BackgroundRun] = [:]

    init(config: Config, frecency: FrecencyStore, notifier: Notifier) {
        self.config = config
        self.frecency = frecency
        self.notifier = notifier
    }

    func run(_ item: LauncherItem, argument: String? = nil) {
        switch item {
        case .app(let app):
            openApplication(app)
        case .command(let command):
            switch command.action {
            case .path(let url):
                if NSWorkspace.shared.open(url) {
                    record(item.id)
                } else {
                    fail("\(command.name): could not open \(url.absoluteString)")
                }
            case .url(let url):
                let target = URLTemplate.accepts(url) ? URLTemplate.resolve(url, query: argument ?? "") : url
                if NSWorkspace.shared.open(target) {
                    record(item.id)
                } else {
                    fail("\(command.name): could not open \(target.absoluteString)")
                }
            case .shell(let text):
                if command.terminal {
                    runInTerminal(id: command.id, name: command.name, command: text, cwd: command.cwd)
                } else {
                    spawn(
                        id: command.id, name: command.name,
                        executable: URL(fileURLWithPath: config.general.shell),
                        arguments: ShellCommand.backgroundArguments(command: text),
                        cwd: command.cwd, reportOutput: false
                    )
                }
            }
        case .script(let script):
            runScript(script, argument: argument)
        }
    }

    private func runScript(_ script: ScriptItem, argument: String?) {
        if let spec = script.argument, !spec.optional, argument == nil {
            notifier.post(title: script.title, body: "Needs an argument (\(spec.placeholder)): type the command, a space, then the value.")
            return
        }
        let arguments = argument.map { [$0] } ?? []
        let cwd = script.url.deletingLastPathComponent()
        switch script.mode {
        case .fullOutput:
            var command = ShellCommand.quote(script.url.path)
            if let argument { command += " " + ShellCommand.quote(argument) }
            runInTerminal(id: script.id, name: script.title, command: command, cwd: cwd)
        case .silent, .inline:
            spawn(id: script.id, name: script.title, executable: script.url, arguments: arguments, cwd: cwd, reportOutput: true)
        }
    }

    private func openApplication(_ app: AppItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let id = app.id
        let name = app.name
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.fail("\(name): \(error.localizedDescription)")
                } else {
                    self?.record(id)
                }
            }
        }
    }

    private func runInTerminal(id: String, name: String, command: String, cwd: URL?) {
        let kind = config.general.terminal
        let shell = config.general.shell
        Task { [weak self] in
            guard let self else { return }
            let outcome = await terminals.launch(command: command, cwd: cwd, name: name, kind: kind, shell: shell)
            switch outcome {
            case .launched: record(id)
            case .failed(let message): fail("\(name): \(message)")
            }
        }
    }

    private func spawn(id: String, name: String, executable: URL, arguments: [String], cwd: URL?, reportOutput: Bool) {
        let run = BackgroundRun()
        let process = run.process
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        run.attach(errPipe, to: run.stderr)
        if reportOutput {
            let outPipe = Pipe()
            process.standardOutput = outPipe
            run.attach(outPipe, to: run.stdout)
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        let runID = run.id
        run.onFinish = { [weak self] status, stdout, stderr in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.running[runID] = nil
                if status != 0 {
                    let detail = stderr.isEmpty ? (stdout.isEmpty ? "" : "\n\(stdout)") : "\n\(stderr)"
                    self.fail("\(name) exited \(status)\(detail)")
                } else if reportOutput, !stdout.isEmpty {
                    self.notifier.post(title: name, body: stdout)
                }
            }
        }
        process.terminationHandler = { _ in run.markExited() }
        do {
            try process.run()
        } catch {
            fail("\(name): \(error.localizedDescription)")
            return
        }
        running[run.id] = run
        record(id)
    }

    private func record(_ id: String) {
        Task { [frecency, onRecorded] in
            await frecency.record(id)
            await MainActor.run { onRecorded?() }
        }
    }

    private func fail(_ message: String) {
        Log.write("failure: \(message)")
        onFailure?(message)
        notifier.failure(message)
    }
}
