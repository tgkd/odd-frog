import Foundation
import CryptoKit
import Synchronization
import OddFrogPluginAPI

public actor ClipboardArchive {
    private struct StoredImage {
        var png: Data
        var thumbnail: Data
        var icon: String
    }

    public nonisolated let counter = Atomic<Int>(0)
    private var owner: Int?
    private var newest = 0
    private var directory: URL?
    private var limits = ClipboardLimits(count: 50, captureImages: true)
    private var entries: [ClipboardEntry] = []
    private var memoryImages: [String: StoredImage] = [:]

    public init() {}

    public nonisolated func nextGeneration() -> Int {
        counter.add(1, ordering: .relaxed).newValue
    }

    public func claim(generation: Int, directory: URL?, limits: ClipboardLimits) throws -> Bool {
        guard generation >= newest else {
            return false
        }
        let loaded = try Self.load(from: directory)
        newest = generation
        owner = generation
        self.directory = directory
        self.limits = limits
        entries = loaded
        memoryImages = [:]
        var reconciled = loaded
        reconcile(&reconciled)
        applyLimits(&reconciled)
        if reconciled != loaded {
            try commit(reconciled)
        }
        removeOrphans()
        return true
    }

    public func release(generation: Int) {
        guard owner == generation else {
            return
        }
        owner = nil
        entries = []
        memoryImages = [:]
    }

    public func configure(generation: Int, directory: URL?, limits: ClipboardLimits) throws {
        guard generation == owner else {
            return
        }
        self.limits = limits
        guard directory != self.directory else {
            var next = entries
            applyLimits(&next)
            try commit(next)
            return
        }
        try move(to: directory)
    }

    public func entries(generation: Int) -> [ClipboardEntry] {
        guard generation == owner else {
            return []
        }
        return entries
    }

    public func icons(generation: Int) -> [String: String] {
        guard generation == owner else {
            return [:]
        }
        var icons: [String: String] = [:]
        for entry in entries where entry.kind == .image {
            if let directory {
                icons[entry.id] = Self.thumbnailPath(in: directory, id: entry.id)
            } else if let image = memoryImages[entry.id] {
                icons[entry.id] = image.icon
            }
        }
        return icons
    }

    public func imageData(generation: Int, id: String) -> Data? {
        guard generation == owner, entries.contains(where: { $0.id == id && $0.kind == .image }) else {
            return nil
        }
        return storedImage(id: id)?.png
    }

    public nonisolated static func thumbnailPath(in directory: URL, id: String) -> String {
        thumbnailURL(in: directory, id: id).path
    }

    public func record(_ capture: ClipboardCapture, image: ProcessedImage?, generation: Int, now: Date) throws -> Bool {
        guard generation == owner else {
            return false
        }
        let entry: ClipboardEntry
        switch capture {
        case .text(let text):
            entry = ClipboardEntry(id: Self.newID(), kind: .text, text: text,
                                   byteSize: text.utf8.count, hash: Self.sha256(Data(text.utf8)), copied: now)
        case .image:
            guard limits.captureImages, let image else {
                return false
            }
            entry = ClipboardEntry(id: Self.newID(), kind: .image, width: image.width, height: image.height,
                                   byteSize: image.png.count + image.thumbnail.count, hash: Self.sha256(image.png), copied: now)
        }
        var next = entries
        var deduped = false
        if let index = next.firstIndex(where: { $0.hash == entry.hash }) {
            var moved = next.remove(at: index)
            moved.copied = now
            next.insert(moved, at: 0)
            deduped = true
        } else {
            next.insert(entry, at: 0)
        }
        applyLimits(&next)
        var newImages: [(String, Data, Data)] = []
        if !deduped, entry.kind == .image, let image, next.contains(where: { $0.id == entry.id }) {
            newImages = [(entry.id, image.png, image.thumbnail)]
        }
        try commit(next, newImages: newImages)
        return true
    }

    public func touch(generation: Int, id: String, now: Date) throws {
        guard generation == owner else {
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        var next = entries
        var entry = next.remove(at: index)
        entry.copied = now
        next.insert(entry, at: 0)
        try commit(next)
    }

    public func delete(generation: Int, id: String) throws {
        guard generation == owner else {
            return
        }
        guard entries.contains(where: { $0.id == id }) else {
            return
        }
        var next = entries
        next.removeAll { $0.id == id }
        try commit(next)
    }

    public func clear(generation: Int) throws -> Int {
        guard generation == owner else {
            return 0
        }
        let removed = entries.count
        try commit([])
        return removed
    }

    private func move(to target: URL?) throws {
        let carried = entries.compactMap { entry -> (ClipboardEntry, StoredImage?)? in
            guard entry.kind == .image else {
                return (entry, nil)
            }
            return storedImage(id: entry.id).map { (entry, $0) }
        }
        let loaded = try Self.load(from: target)
        directory = target
        entries = loaded
        memoryImages = [:]
        var current = loaded
        reconcile(&current)
        entries = current
        removeOrphans()
        let loadedHashes = Set(current.map(\.hash))
        let incoming = carried.filter { !loadedHashes.contains($0.0.hash) }
        var next = (current + incoming.map(\.0)).sorted { $0.copied > $1.copied }
        applyLimits(&next)
        let kept = Set(next.map(\.id))
        let newImages = incoming.compactMap { entry, image -> (String, Data, Data)? in
            guard let image, kept.contains(entry.id) else {
                return nil
            }
            return (entry.id, image.png, image.thumbnail)
        }
        try commit(next, newImages: newImages)
    }

    private func storedImage(id: String) -> StoredImage? {
        guard let directory else {
            return memoryImages[id]
        }
        guard let png = try? Data(contentsOf: Self.imageURL(in: directory, id: id)),
              let thumbnail = try? Data(contentsOf: Self.thumbnailURL(in: directory, id: id)) else {
            return nil
        }
        return StoredImage(png: png, thumbnail: thumbnail, icon: Self.thumbnailPath(in: directory, id: id))
    }

    private func applyLimits(_ list: inout [ClipboardEntry]) {
        while list.count > limits.count {
            list.removeLast()
        }
        let cap = directory == nil ? min(limits.maxTotalImageBytes, ClipboardLimits.maxMemoryImageBytes) : limits.maxTotalImageBytes
        var total = list.reduce(0) { $0 + ($1.kind == .image ? $1.byteSize : 0) }
        while total > cap {
            guard let index = list.lastIndex(where: { $0.kind == .image }) else {
                break
            }
            total -= list[index].byteSize
            list.remove(at: index)
        }
    }

    private func reconcile(_ list: inout [ClipboardEntry]) {
        guard let directory else {
            return
        }
        list.removeAll { entry in
            guard entry.kind == .image else {
                return false
            }
            return !FileManager.default.fileExists(atPath: Self.imageURL(in: directory, id: entry.id).path)
                || !FileManager.default.fileExists(atPath: Self.thumbnailURL(in: directory, id: entry.id).path)
        }
    }

    private func commit(_ newEntries: [ClipboardEntry], newImages: [(String, Data, Data)] = []) throws {
        let removed = entries.filter { old in !newEntries.contains(where: { $0.id == old.id }) }
        guard let directory else {
            for (id, png, thumbnail) in newImages {
                memoryImages[id] = StoredImage(png: png, thumbnail: thumbnail, icon: Self.inlineIcon(thumbnail))
            }
            entries = newEntries
            for entry in removed {
                memoryImages[entry.id] = nil
            }
            return
        }
        let images = directory.appendingPathComponent("images", isDirectory: true)
        var written: [URL] = []
        do {
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            for (id, png, thumb) in newImages {
                let full = Self.imageURL(in: directory, id: id)
                try png.write(to: full, options: .atomic)
                written.append(full)
                let thumbnail = Self.thumbnailURL(in: directory, id: id)
                try thumb.write(to: thumbnail, options: .atomic)
                written.append(thumbnail)
            }
            try Self.writeIndex(newEntries, to: directory)
        } catch {
            for url in written {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
        entries = newEntries
        for entry in removed {
            try? FileManager.default.removeItem(at: Self.imageURL(in: directory, id: entry.id))
            try? FileManager.default.removeItem(at: Self.thumbnailURL(in: directory, id: entry.id))
        }
    }

    private func removeOrphans() {
        guard let directory else {
            return
        }
        let images = directory.appendingPathComponent("images", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil) else {
            return
        }
        let kept = Set(entries.map(\.id))
        for file in files {
            let base = file.deletingPathExtension().lastPathComponent
            let id = base.hasSuffix("-thumb") ? String(base.dropLast("-thumb".count)) : base
            guard !kept.contains(id) else {
                continue
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func inlineIcon(_ png: Data) -> String {
        PluginItem.inlinePNGPrefix + png.base64EncodedString()
    }

    private static func imageURL(in directory: URL, id: String) -> URL {
        directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent("\(id).png", isDirectory: false)
    }

    private static func thumbnailURL(in directory: URL, id: String) -> URL {
        directory.appendingPathComponent("images", isDirectory: true).appendingPathComponent("\(id)-thumb.png", isDirectory: false)
    }

    private static func writeIndex(_ entries: [ClipboardEntry], to directory: URL) throws {
        let data = try PluginProtocol.encoder().encode(entries)
        try data.write(to: directory.appendingPathComponent("index.json", isDirectory: false), options: .atomic)
    }

    private static func load(from directory: URL?) throws -> [ClipboardEntry] {
        guard let directory else {
            return []
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("index.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        guard let data = try? Data(contentsOf: url),
              let entries = try? PluginProtocol.decoder().decode([ClipboardEntry].self, from: data) else {
            throw RPCError("clipboard", "Clipboard history in \(directory.path) could not be read. Nothing was changed.")
        }
        return entries
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
