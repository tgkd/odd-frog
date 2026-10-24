import Foundation
import OddFrogPluginAPI

public struct FileHit: Sendable, Equatable {
    public var root: String
    public var relativePath: String
    public var isDirectory: Bool
    public var score: Int
    public var path: String { root + "/" + relativePath }
    public init(root: String, relativePath: String, isDirectory: Bool, score: Int) {
        self.root = root; self.relativePath = relativePath; self.isDirectory = isDirectory; self.score = score
    }
}

public enum FilesProvider {
    public enum State: Sendable, Equatable {
        case ready(scanning: Bool)
        case unavailable(String)
        case noFolders
    }

    public static func respond(to request: PluginQuery, state: State, hits: [FileHit], home: String) -> [PluginItem] {
        if request.root {
            // Root search shows only real hits: status notices belong to the plugin's own view.
            guard case .ready = state else { return [] }
            return rows(hits, for: request, home: home)
        }
        switch state {
        case .unavailable(let reason):
            return [notice("unavailable", "File search is unavailable", reason, symbol: "exclamationmark.triangle")]
        case .noFolders:
            return [notice("no-folders", "No folders to index",
                           "Add folders in Settings › Plugins › Files.", symbol: "folder.badge.questionmark")]
        case .ready(let scanning):
            if request.query.trimmingCharacters(in: .whitespaces).isEmpty {
                return [notice("hint", "Type a file or folder name",
                               scanning ? "Indexing your folders…" : "Fuzzy search over your indexed folders.",
                               symbol: "magnifyingglass")]
            }
            if hits.isEmpty {
                return [notice("empty", scanning ? "Indexing your folders…" : "No matching files",
                               scanning ? "Results will appear when indexing finishes." : "Try a different name.",
                               symbol: scanning ? "hourglass" : "magnifyingglass")]
            }
            return rows(hits, for: request, home: home)
        }
    }

    private static func rows(_ hits: [FileHit], for request: PluginQuery, home: String) -> [PluginItem] {
        let cap = max(1, min(request.maxResults, 50)), typed = request.query.trimmingCharacters(in: .whitespaces)
        return hits.prefix(cap).map { row($0, query: typed, home: home) }
    }

    public static func merge(_ groups: [[FileHit]]) -> [FileHit] {
        var best: [String: FileHit] = [:]
        for hit in groups.joined() where (best[hit.path]?.score ?? .min) < hit.score {
            best[hit.path] = hit
        }
        return best.values.sorted { ($0.score, $1.path) > ($1.score, $0.path) }
    }

    private static func row(_ hit: FileHit, query: String, home: String) -> PluginItem {
        let url = URL(fileURLWithPath: hit.path)
        let remember = PluginAfter("track", payload: .object([
            "root": .string(hit.root), "path": .string(hit.relativePath), "query": .string(query),
        ]))
        return PluginItem(id: hit.path, title: url.lastPathComponent,
                          subtitle: abbreviate(url.deletingLastPathComponent().path, home: home),
                          kind: hit.isDirectory ? "Folder" : "File",
                          icon: "file:" + hit.path,
                          primary: PluginAction(.openPath, hit.path, after: remember),
                          secondary: PluginAction(.reveal, hit.path, after: remember))
    }

    private static func notice(_ id: String, _ title: String, _ subtitle: String, symbol: String) -> PluginItem {
        PluginItem(id: id, title: title, subtitle: subtitle, kind: "Files", symbol: symbol)
    }

    static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
