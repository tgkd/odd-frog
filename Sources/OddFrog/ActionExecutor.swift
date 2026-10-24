import AppKit
import Foundation
import OddFrogCore
import OddFrogPluginAPI

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
    let windows = WindowManager()
    var cascadeStep: CGFloat = 32
    var terminal = TerminalChoice.preset(.terminal)
    var onFailure: ((String) -> Void)?
    var onRecorded: (() -> Void)?
    var onPluginAction: ((PluginResult, String?, Bool) -> Void)?
    private var running: [UUID: BackgroundRun] = [:]

    init(config: Config, frecency: FrecencyStore, notifier: Notifier) {
        self.config = config
        self.frecency = frecency
        self.notifier = notifier
    }

    func run(_ item: LauncherItem, argument: String? = nil, secondary: Bool = false) {
        guard case .plugin(let result) = item else { return }
        onPluginAction?(result, argument, secondary)
    }

    func runHost(_ action: PluginAction, result: PluginResult, argument: String?) {
        let id = result.historyEligible ? result.id : ""
        let name = result.item.title
        let value: String
        if action.value.contains("{query}"), let resolved = URLTemplate.resolve(template: action.value, query: argument ?? "") {
            value = resolved.absoluteString
        } else { value = action.value.replacingOccurrences(of: "{argument}", with: argument ?? "") }
        let argv = action.argv?.compactMap { text -> String? in
            if text == "{argument}" { return argument }
            return text.replacingOccurrences(of: "{argument}", with: argument ?? "")
        } ?? []
        let cwd = action.cwd.map { URL(fileURLWithPath: ConfigParser.expandTilde($0)) }
        switch action.kind {
        case .copy:
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); record(id)
        case .paste:
            if let path = action.payload?["png"].string {
                // Read before clearing: a missing file must not wipe the user's current clipboard.
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    fail("Could not read \(path)"); return
                }
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setData(data, forType: .png) else {
                    fail("Could not copy \(path)"); return
                }
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            if !PasteKeystroke.send() {
                notifier.post(title: name, body: "Copied. Allow Odd Frog in Privacy & Security › Accessibility to paste automatically.", log: false)
            }
            record(id)
        case .openURL, .openPath:
            let url = action.kind == .openPath ? URL(fileURLWithPath: ConfigParser.expandTilde(value)) : URL(string: value)
            guard let url, NSWorkspace.shared.open(url) else { fail("Could not open \(value)"); return }; record(id)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: ConfigParser.expandTilde(value))]); record(id)
        case .openApplication:
            let url = value.hasPrefix("/") ? URL(fileURLWithPath: value) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
            guard let url else { fail("Application \(value) was not found."); return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                Task { @MainActor in
                    if let error { self?.fail(error.localizedDescription) } else { self?.record(id) }
                }
            }
        case .execute:
            spawn(id: id, name: name, executable: URL(fileURLWithPath: value), arguments: argv, cwd: cwd, reportOutput: action.output == "notification")
        case .terminal:
            let command = action.argv == nil ? value : ([action.value] + argv).map(ShellCommand.quote).joined(separator: " ")
            runInTerminal(id: id, name: name, command: command, cwd: cwd)
        case .callback, .service: break
        }
    }

    func recordPlugin(_ result: PluginResult) { if result.historyEligible { record(result.id) } }

    private func runInTerminal(id: String, name: String, command: String, cwd: URL?) {
        let shell = config.general.shell
        switch terminal {
        case .preset(let kind):
            Task { [weak self] in
                guard let self else { return }
                let outcome = await terminals.launch(command: command, cwd: cwd, name: name, kind: kind, shell: shell)
                switch outcome {
                case .launched: record(id)
                case .failed(let message): fail("\(name): \(message)")
                }
            }
        case .custom(let template):
            let directory = cwd ?? FileManager.default.homeDirectoryForCurrentUser
            guard let result = ShellCommand.customTerminalCommand(template: template, shell: shell, cwd: directory.path, command: command) else {
                fail("\(name): set a custom command containing {command} in Settings › Plugins › Terminal.")
                return
            }
            spawn(id: id, name: name, executable: URL(fileURLWithPath: shell), arguments: ShellCommand.backgroundArguments(command: result), cwd: directory, reportOutput: false)
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
        guard !id.isEmpty else { return }
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
