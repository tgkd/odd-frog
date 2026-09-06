import Foundation

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

    public static func scan(roots: [URL] = defaultRoots, maxDepth: Int = 2) -> [AppItem] {
        let fm = FileManager.default
        var seen = Set<String>()
        var items: [AppItem] = []
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
                items.append(makeItem(url.standardizedFileURL))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    public private(set) var lastScan: Date?
    private let roots: [URL]
    private var inFlight: Task<[AppItem], Never>?

    public init(roots: [URL] = AppScanner.defaultRoots) {
        self.roots = roots
    }

    public func refreshIfStale(olderThan interval: TimeInterval) async -> [AppItem] {
        if let lastScan, Date().timeIntervalSince(lastScan) < interval { return apps }
        return await refresh()
    }

    public func refresh() async -> [AppItem] {
        if let inFlight { return await inFlight.value }
        let roots = roots
        let task = Task.detached(priority: .utility) { AppScanner.scan(roots: roots) }
        inFlight = task
        let result = await task.value
        apps = result
        lastScan = Date()
        inFlight = nil
        return result
    }
}
