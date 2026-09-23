import AppKit
import OddFrogCore

private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

@MainActor
final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    private var pending = Set<String>()
    private var observers: [(String) -> Void] = []

    init() {
        cache.countLimit = 1000
    }

    func observeLoads(_ handler: @escaping (String) -> Void) {
        observers.append(handler)
    }

    func icon(for item: LauncherItem, size: CGFloat = 24) -> NSImage? {
        switch item {
        case .plugin(let result):
            if let icon = result.item.icon {
                if icon.hasPrefix("text:") { return emojiImage(String(icon.dropFirst(5)), size: size) }
                let path = icon.hasPrefix("/") ? icon : result.directory?.appendingPathComponent(icon).path
                if let path {
                    if path.hasSuffix(".app") { return self.icon(forFile: path, size: size) }
                    if let image = NSImage(contentsOfFile: path) { return image }
                }
            }
            return NSImage(systemSymbolName: result.item.symbol ?? "puzzlepiece.extension", accessibilityDescription: nil)
        }
    }

    private func emojiImage(_ emoji: String, size: CGFloat) -> NSImage? {
        let key = "emoji:\(emoji):\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: size * 20 / 24)])
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let bounds = text.size()
            text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
            return true
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private func icon(forFile path: String, size: CGFloat) -> NSImage? {
        let sized = "app:\(size):\(path)" as NSString
        if let cached = cache.object(forKey: sized) { return cached }
        guard let native = cache.object(forKey: "app:\(path)" as NSString) else {
            load(path: path)
            return nil
        }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            native.draw(in: rect)
            return true
        }
        cache.setObject(image, forKey: sized)
        return image
    }

    private func load(path: String) {
        guard pending.insert(path).inserted else { return }
        Task.detached(priority: .userInitiated) {
            let boxed = Self.loadIcon(path: path)
            await MainActor.run { [weak self] in
                self?.store(boxed, path: path)
            }
        }
    }

    private nonisolated static func loadIcon(path: String) -> SendableImage {
        SendableImage(image: NSWorkspace.shared.icon(forFile: path))
    }

    private func store(_ boxed: SendableImage, path: String) {
        cache.setObject(boxed.image, forKey: "app:\(path)" as NSString)
        pending.remove(path)
        for observer in observers { observer(path) }
    }

}
