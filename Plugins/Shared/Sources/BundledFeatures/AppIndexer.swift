import Foundation
import OddFrogCore

public enum AppScanner {
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        ]
    }

    public struct AppScanCache: Sendable, Equatable {
        public struct Entry: Sendable, Equatable {
            public var modified: Date
            public var item: AppItem

            public init(modified: Date, item: AppItem) {
                self.modified = modified
                self.item = item
            }
        }

        public var entries: [String: Entry]

        public init(entries: [String: Entry] = [:]) {
            self.entries = entries
        }
    }

    public static func scan(roots: [URL] = defaultRoots, maxDepth: Int = 2) -> [AppItem] {
        scan(roots: roots, maxDepth: maxDepth, cache: AppScanCache()).apps
    }

    public static func scan(roots: [URL] = defaultRoots, maxDepth: Int = 2, cache: AppScanCache) -> (apps: [AppItem], cache: AppScanCache) {
        let fm = FileManager.default
        var seen = Set<String>()
        var items: [AppItem] = []
        var newEntries: [String: AppScanCache.Entry] = [:]
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                    continue
                }
                if enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: canonical, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                guard seen.insert(canonical).inserted else { continue }
                let standardized = url.standardizedFileURL
                let modified = modificationDate(of: standardized, fm: fm)
                if let existing = cache.entries[canonical], existing.modified == modified {
                    newEntries[canonical] = existing
                    items.append(existing.item)
                } else {
                    let item = makeItem(standardized)
                    newEntries[canonical] = AppScanCache.Entry(modified: modified, item: item)
                    items.append(item)
                }
            }
        }
        let sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (sorted, AppScanCache(entries: newEntries))
    }

    private static func modificationDate(of bundleURL: URL, fm: FileManager) -> Date {
        let infoPlist = bundleURL.appendingPathComponent("Contents/Info.plist")
        if let values = try? infoPlist.resourceValues(forKeys: [.contentModificationDateKey]), let date = values.contentModificationDate {
            return date
        }
        if let values = try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey]), let date = values.contentModificationDate {
            return date
        }
        return .distantPast
    }

    public static func watchedDirectories(roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var result = roots
        for root in roots {
            guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for url in contents {
                guard url.pathExtension != "app", !url.lastPathComponent.hasPrefix(".") else { continue }
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                result.append(url)
            }
        }
        return result
    }

    static func makeItem(_ url: URL) -> AppItem {
        let bundle = Bundle(url: url)
        let localized = bundle?.localizedInfoDictionary
        let info = bundle?.infoDictionary
        let candidates = [
            localized?["CFBundleDisplayName"], info?["CFBundleDisplayName"],
            localized?["CFBundleName"], info?["CFBundleName"],
        ]
        let name = candidates
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? url.deletingPathExtension().lastPathComponent
        return AppItem(url: url, name: name, bundleID: bundle?.bundleIdentifier)
    }
}

public actor AppIndexer {
    public private(set) var apps: [AppItem] = []
    private let roots: [URL]
    private var cache = AppScanner.AppScanCache()
    private var inFlight: Task<(apps: [AppItem], cache: AppScanner.AppScanCache), Never>?

    public init(roots: [URL] = AppScanner.defaultRoots) {
        self.roots = roots
    }

    public func refresh() async -> [AppItem] {
        if let inFlight { return await inFlight.value.apps }
        let roots = roots
        let cache = cache
        let task = Task.detached(priority: .utility) { AppScanner.scan(roots: roots, cache: cache) }
        inFlight = task
        let result = await task.value
        apps = result.apps
        self.cache = result.cache
        inFlight = nil
        return result.apps
    }
}
