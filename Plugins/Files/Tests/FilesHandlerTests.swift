import Foundation
import Testing
import OddFrogPluginAPI
@testable import FilesPluginCore

struct FilesHandlerTests {
    private static let library = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("vendor/fff/libfff_c.dylib").path

    private func operation() -> ProviderOperation {
        ProviderOperation(id: "t", service: { _, _ in .null }, emit: { _, _ in })
    }

    private func params(folders: [String], storage: String, query: String? = nil) -> JSONValue {
        var value: [String: JSONValue] = [
            "context": .object([
                "settings": .object(["folders": .array(folders.map(JSONValue.string))]),
                "storagePath": .string(storage), "configPath": .string(""),
            ]),
        ]
        if let query {
            value["input"] = try! .encode(PluginQuery(query: query, fullQuery: "f " + query, maxResults: 8))
        }
        return .object(value)
    }

    @Test func missingLibraryShowsSetupRow() async throws {
        let handler = FilesHandler(loader: { try FffLibrary.load(candidates: ["/nonexistent/libfff_c.dylib"]) })
        _ = try await handler.handle("initialize", params: params(folders: ["/tmp"], storage: NSTemporaryDirectory()), operation: operation())
        let rows = try await handler.handle("query", params: params(folders: ["/tmp"], storage: NSTemporaryDirectory(), query: "x"),
                                            operation: operation()).decode([PluginItem].self)
        #expect(rows.first?.title == "File search is unavailable")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: FilesHandlerTests.library)))
    func findsFilesAndFoldersWithRealLibrary() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("fff-test-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let storage = base.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes/archive"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("notes/quarterly-report.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("unrelated.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: base) }

        let handler = FilesHandler(loader: { try FffLibrary.load(candidates: [Self.library]) }, pollInterval: .milliseconds(20))
        _ = try await handler.handle("initialize", params: params(folders: [root.path], storage: storage.path), operation: operation())
        var titles: [String] = []
        for _ in 0..<100 {
            let rows = try await handler.handle("query", params: params(folders: [root.path], storage: storage.path, query: "quarterly"),
                                                operation: operation()).decode([PluginItem].self)
            titles = rows.map(\.title)
            if titles.contains("quarterly-report.txt") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(titles.first == "quarterly-report.txt")
        await handler.shutdown()
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: FilesHandlerTests.library)))
    func trackedFileRanksFirstForTheSameQuery() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("fff-track-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let storage = base.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["budget-alpha.txt", "budget-beta.txt"] {
            try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let handler = FilesHandler(loader: { try FffLibrary.load(candidates: [Self.library]) }, pollInterval: .milliseconds(20))
        _ = try await handler.handle("initialize", params: params(folders: [root.path], storage: storage.path), operation: operation())
        func titles() async throws -> [String] {
            var found: [PluginItem] = []
            for _ in 0..<100 {
                found = try await handler.handle("query", params: params(folders: [root.path], storage: storage.path, query: "budget"),
                                                 operation: operation()).decode([PluginItem].self)
                if found.count == 2 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            return found.map(\.title)
        }
        let before = try await titles()
        let loser = try #require(before.last)
        let item = try await handler.handle("query", params: params(folders: [root.path], storage: storage.path, query: "budget"),
                                            operation: operation()).decode([PluginItem].self).first { $0.title == loser }
        let after = try #require(item?.primary?.after)
        for _ in 0..<3 {
            let activation = PluginActivation(actionID: after.callback, payload: after.payload ?? .null, item: try #require(item), argument: nil)
            var input = params(folders: [root.path], storage: storage.path)
            if case .object(var fields) = input { fields["input"] = try .encode(activation); input = .object(fields) }
            _ = try await handler.handle("activate", params: input, operation: operation())
        }
        #expect(try await titles().first == loser)
        await handler.shutdown()
    }
}
