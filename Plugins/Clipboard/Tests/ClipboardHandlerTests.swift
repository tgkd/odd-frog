import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
import ClipboardPluginCore
import OddFrogPluginAPI

private actor EmissionRecorder {
    private(set) var methods: [String] = []
    func record(_ method: String) {
        methods.append(method)
    }
}

struct ClipboardHandlerTests {
    private func temp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("odd-frog-clip-\(UUID().uuidString)")
    }
    private var operation: ProviderOperation {
        ProviderOperation(id: "test", service: { _, _ in throw RPCError("test", "No host services.") }, emit: { _, _ in })
    }
    private func initParams(storage: URL, settings: [String: JSONValue] = [:]) throws -> JSONValue {
        .object(["apiVersion": .number(2),
                 "context": try .encode(PluginContext(settings: settings, storagePath: storage.path))])
    }
    private func settingsParams(storage: URL, settings: [String: JSONValue]) throws -> JSONValue {
        .object(["apiVersion": .number(2),
                 "context": try .encode(PluginContext(settings: settings, storagePath: storage.path))])
    }
    private func queryParams(_ query: String, storage: URL, maxResults: Int = 8) throws -> JSONValue {
        .object(["apiVersion": .number(2),
                 "context": try .encode(PluginContext(storagePath: storage.path)),
                 "input": try .encode(PluginQuery(query: query, fullQuery: "clip " + query, maxResults: maxResults))])
    }
    private func activateParams(_ actionID: String, payload: JSONValue = .object([:]), storage: URL) throws -> JSONValue {
        .object(["apiVersion": .number(2),
                 "context": try .encode(PluginContext(storagePath: storage.path)),
                 "input": try .encode(PluginActivation(actionID: actionID, payload: payload,
                                                       item: PluginItem(id: "x", title: "x"), argument: nil))])
    }
    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw RPCError("test", "Timed out waiting for clipboard capture.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func writeText(_ text: String, to name: NSPasteboard.Name) {
        let pasteboard = NSPasteboard(name: name)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
    private func writeImage(_ png: Data, to name: NSPasteboard.Name) {
        let pasteboard = NSPasteboard(name: name)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
    private func makePNG(width: Int, height: Int) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    @Test func emptyQueryOnANamedPasteboardListsTheEmptyRow() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ClipboardHandler(archive: ClipboardArchive(),
                                       pasteboard: ClipboardPasteboard(name: NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        #expect(items.map(\.id) == ["empty"])
    }

    @Test func pollCapturesCopiedText() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("hello clipboard", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "hello clipboard" } == true
        }
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        let captured = try #require(items.first { $0.title == "hello clipboard" })
        #expect(captured.primary == PluginAction(.callback, "paste", payload: .object(["id": .string(captured.id)])))
    }

    @Test func pollEmitsQueryInvalidatedAfterACapture() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        let recorder = EmissionRecorder()
        await handler.start(emit: { method in await recorder.record(method) })
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("ping", to: name)
        try await wait { await recorder.methods.contains("queryInvalidated") }
    }

    @Test func pollCapturesCopiedImages() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeImage(makePNG(width: 6, height: 4), to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.symbol == "photo" } == true
        }
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        let image = try #require(items.first { $0.symbol == "photo" })
        #expect(image.title == "Image 6×4")
        #expect(image.icon == ClipboardArchive.thumbnailPath(in: root, id: image.id))
        #expect(FileManager.default.fileExists(atPath: image.icon!))
    }

    @Test func copyWritesTheEntryBackToThePasteboard() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("secret", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "secret" } == true
        }
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        let captured = try #require(items.first { $0.title == "secret" })
        NSPasteboard(name: name).clearContents()
        _ = try await handler.handle("activate",
                                     params: activateParams("copy", payload: .object(["id": .string(captured.id)]), storage: root),
                                     operation: operation)
        #expect(NSPasteboard(name: name).string(forType: .string) == "secret")
    }

    @Test func pasteWritesTheEntryAndAsksTheHostToPaste() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("pasted", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "pasted" } == true
        }
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        let captured = try #require(items.first { $0.title == "pasted" })
        NSPasteboard(name: name).clearContents()
        let effects = try await handler.handle("activate",
                                               params: activateParams("paste", payload: .object(["id": .string(captured.id)]), storage: root),
                                               operation: operation).decode(PluginEffects.self)
        #expect(effects.paste == true)
        #expect(NSPasteboard(name: name).string(forType: .string) == "pasted")
    }

    @Test func deleteRemovesAnEntry() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("temp", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "temp" } == true
        }
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        let captured = try #require(items.first { $0.title == "temp" })
        let effects = try await handler.handle("activate",
                                               params: activateParams("delete", payload: .object(["id": .string(captured.id)]), storage: root),
                                               operation: operation).decode(PluginEffects.self)
        #expect(effects.refreshQuery)
        let after = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        #expect(!after.contains { $0.id == captured.id })
        #expect(after.map(\.id) == ["empty"])
    }

    @Test func clearRemovesEverything() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("one", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "one" } == true
        }
        writeText("two", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "two" } == true
        }
        let effects = try await handler.handle("activate", params: activateParams("clear", storage: root), operation: operation)
            .decode(PluginEffects.self)
        #expect(effects.notification == "Cleared 2 clipboard entries.")
        let after = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        #expect(after.map(\.id) == ["empty"])
    }

    @Test func authorizeAsksForTextWhenThePasteboardIsEmpty() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ClipboardHandler(archive: ClipboardArchive(),
                                       pasteboard: ClipboardPasteboard(name: NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        let effects = try await handler.handle("activate", params: activateParams("authorize", storage: root), operation: operation)
            .decode(PluginEffects.self)
        #expect(effects.notification == "Copy some text in another app first, then press Return here again.")
        #expect(effects.refreshQuery)
    }

    @Test func authorizeReportsClipboardOnAfterTextIsCopied() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("hi", to: name)
        let effects = try await handler.handle("activate", params: activateParams("authorize", storage: root), operation: operation)
            .decode(PluginEffects.self)
        #expect(effects.notification == "Clipboard history is on.")
    }

    @Test func settingsAppliesTheLimitImmediately() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let handler = ClipboardHandler(archive: ClipboardArchive(), pasteboard: ClipboardPasteboard(name: name),
                                       interval: .milliseconds(20))
        defer { Task { await handler.shutdown() } }
        _ = try await handler.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("one", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "one" } == true
        }
        writeText("two", to: name)
        try await wait {
            let items = try? await handler.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "two" } == true
        }
        _ = try await handler.handle("settings", params: settingsParams(storage: root, settings: ["limit": .number(1)]), operation: operation)
        let items = try await handler.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        #expect(items.filter { $0.id != "clear" }.map(\.title) == ["two"])
    }

    @Test func aStaleHandlerDoesNotPoll() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let name = NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")
        let archive = ClipboardArchive()
        let first = ClipboardHandler(archive: archive, pasteboard: ClipboardPasteboard(name: name), interval: .milliseconds(20))
        let second = ClipboardHandler(archive: archive, pasteboard: ClipboardPasteboard(name: name), interval: .milliseconds(20))
        defer {
            Task { await first.shutdown() }
            Task { await second.shutdown() }
        }
        _ = try await first.handle("initialize", params: initParams(storage: root), operation: operation)
        _ = try await second.handle("initialize", params: initParams(storage: root), operation: operation)
        writeText("only second", to: name)
        try await wait {
            let items = try? await second.handle("query", params: queryParams("", storage: root), operation: operation)
                .decode([PluginItem].self)
            return items?.contains { $0.title == "only second" } == true
        }
        let firstItems = try await first.handle("query", params: queryParams("", storage: root), operation: operation)
            .decode([PluginItem].self)
        #expect(firstItems.map(\.id) == ["empty"])
    }

    @Test func unknownActionsAndMethodsAreRejected() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let handler = ClipboardHandler(archive: ClipboardArchive(),
                                       pasteboard: ClipboardPasteboard(name: NSPasteboard.Name("odd-frog-clip-\(UUID().uuidString)")))
        defer { Task { await handler.shutdown() } }
        await #expect(throws: RPCError("action", "Unknown action: nope")) {
            try await handler.handle("activate", params: activateParams("nope", storage: root), operation: operation)
        }
        await #expect(throws: RPCError("method", "Unsupported method: catalog")) {
            try await handler.handle("catalog", params: .object([:]), operation: operation)
        }
    }
}
