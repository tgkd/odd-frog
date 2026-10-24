import Foundation
import AppKit
import OddFrogPluginAPI

public actor ClipboardHandler: ProviderHandler {
    private let archive: ClipboardArchive
    private let pasteboard: ClipboardPasteboard
    private let interval: Duration
    private let generation: Int

    private var emit: (@Sendable (String) async -> Void)?
    private var closed = false
    private var claimed = false
    private var failure: String?
    private var poll: Task<Void, Never>?
    private var lastCount = 0
    private var lastBehavior: NSPasteboard.AccessBehavior = .default
    private var limits = ClipboardLimits(count: 50, captureImages: true)

    public init(archive: ClipboardArchive, pasteboard: ClipboardPasteboard, interval: Duration = .milliseconds(500)) {
        self.archive = archive
        self.pasteboard = pasteboard
        self.interval = interval
        generation = archive.nextGeneration()
    }

    public func start(emit: @escaping @Sendable (String) async -> Void) async {
        self.emit = emit
    }

    public func handle(_ method: String, params: JSONValue, operation: ProviderOperation) async throws -> JSONValue {
        switch method {
        case "initialize":
            return try await initialize(params: params)
        case "settings":
            return try await settings(params: params)
        case "query":
            return try await query(params: params)
        case "activate":
            return try await activate(params: params)
        default:
            throw RPCError("method", "Unsupported method: \(method)")
        }
    }

    public func shutdown() async {
        closed = true
        poll?.cancel()
        await poll?.value
        await archive.release(generation: generation)
    }

    private func initialize(params: JSONValue) async throws -> JSONValue {
        if closed || Task.isCancelled {
            return .object(["apiVersion": .number(2)])
        }
        let context = try params["context"].decode(PluginContext.self)
        let state = await pasteboard.state()
        lastCount = state.changeCount
        lastBehavior = state.behavior
        let directory = URL(fileURLWithPath: context.storagePath)
        let newLimits = ClipboardLimits(settings: context.settings)
        limits = newLimits
        let owned = try await archive.claim(generation: generation, directory: directory, limits: newLimits)
        if closed {
            await archive.release(generation: generation)
            return .object(["apiVersion": .number(2)])
        }
        guard owned else {
            return .object(["apiVersion": .number(2)])
        }
        claimed = true
        startPoll()
        return .object(["apiVersion": .number(2)])
    }

    private func settings(params: JSONValue) async throws -> JSONValue {
        let context = try params["context"].decode(PluginContext.self)
        let newLimits = ClipboardLimits(settings: context.settings)
        limits = newLimits
        try await archive.configure(generation: generation, limits: newLimits)
        return .object([:])
    }

    private func query(params: JSONValue) async throws -> JSONValue {
        let context = try params["context"].decode(PluginContext.self)
        let input = try params["input"].decode(PluginQuery.self)
        let state = await pasteboard.state()
        let access: ClipboardProvider.Access
        switch state.behavior {
        case .alwaysAllow:
            access = .allowed
        case .alwaysDeny:
            access = .denied
        default:
            access = .setup
        }
        let entries = await archive.entries(generation: generation)
        let directory = URL(fileURLWithPath: context.storagePath)
        return try .encode(ClipboardProvider.respond(to: input, access: access, entries: entries,
                                                     directory: directory, failure: failure))
    }

    private func activate(params: JSONValue) async throws -> JSONValue {
        let activation = try params["input"].decode(PluginActivation.self)
        switch activation.actionID {
        case "copy":
            try await restore(id: activation.payload["id"].string ?? "")
            return try .encode(PluginEffects())
        case "paste":
            try await restore(id: activation.payload["id"].string ?? "")
            return try .encode(PluginEffects(paste: true))
        case "delete":
            try await archive.delete(generation: generation, id: activation.payload["id"].string ?? "")
            return try .encode(PluginEffects(refreshQuery: true))
        case "clear":
            let removed = try await archive.clear(generation: generation)
            return try .encode(PluginEffects(notification: "Cleared \(removed) clipboard entries.", refreshQuery: true))
        case "authorize":
            let request = await pasteboard.requestAccess()
            let state = await pasteboard.state()
            let notification: String
            switch request {
            case .noText:
                notification = "Copy some text in another app first, then press Return here again."
            case .read:
                switch state.behavior {
                case .alwaysAllow:
                    notification = "Clipboard history is on."
                case .default:
                    notification = "macOS did not ask for access. Copy some text in another app and try again."
                default:
                    notification = "Now set Odd Frog to Always Allow in System Settings › Privacy & Security."
                }
            }
            return try .encode(PluginEffects(notification: notification, refreshQuery: true))
        default:
            throw RPCError("action", "Unknown action: \(activation.actionID)")
        }
    }

    private func restore(id: String) async throws {
        let entries = await archive.entries(generation: generation)
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw RPCError("clipboard", "This entry no longer exists.")
        }
        switch entry.kind {
        case .text:
            guard let text = entry.text else {
                throw RPCError("clipboard", "This entry no longer exists.")
            }
            guard await pasteboard.write(text: text) else {
                throw RPCError("clipboard", "The clipboard changed while copying. Try again.")
            }
        case .image:
            guard let data = await archive.imageData(generation: generation, id: id) else {
                throw RPCError("clipboard", "This entry no longer exists.")
            }
            guard await pasteboard.write(png: data) else {
                throw RPCError("clipboard", "The clipboard changed while copying. Try again.")
            }
        }
        try await archive.touch(generation: generation, id: id, now: Date())
    }

    private func startPoll() {
        poll = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                if closed {
                    return
                }
                await tick()
            }
        }
    }

    private func tick() async {
        let state = await pasteboard.state()
        if state.behavior != lastBehavior {
            lastBehavior = state.behavior
            if state.behavior == .alwaysAllow {
                lastCount = state.changeCount
            }
            await emitInvalidated()
            return
        }
        if state.behavior != .alwaysAllow || state.changeCount == lastCount {
            return
        }
        lastCount = state.changeCount
        guard let capture = await pasteboard.capture() else {
            return
        }
        let after = await pasteboard.state()
        guard after.changeCount == state.changeCount else {
            return
        }
        switch capture {
        case .text:
            await record(capture, image: nil)
        case .image(let data, let type):
            guard limits.captureImages else {
                return
            }
            let processed = await Task.detached {
                ClipboardImages.process(data, type: type)
            }.value
            guard let processed else {
                return
            }
            await record(capture, image: processed)
        }
    }

    private func record(_ capture: ClipboardCapture, image: ProcessedImage?) async {
        if closed {
            return
        }
        do {
            let saved = try await archive.record(capture, image: image, generation: generation, now: Date())
            if saved {
                failure = nil
                await emitInvalidated()
            }
        } catch {
            failure = "The last copy was not saved: \(error)"
            await emitInvalidated()
        }
    }

    private func emitInvalidated() async {
        await emit?("queryInvalidated")
    }
}
