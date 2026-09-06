import AppKit
import OddFrogCore

private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

@MainActor
final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    private var pending = Set<String>()
    var onLoaded: ((String) -> Void)?

    init() {
        cache.countLimit = 1000
    }

    func icon(for item: LauncherItem) -> NSImage? {
        switch item {
        case .app(let app):
            return icon(forFile: app.url.path)
        case .command(let command):
            let name: String
            switch command.action {
            case .shell: name = command.terminal ? "terminal" : "chevron.left.forwardslash.chevron.right"
            case .path: name = "folder"
            case .url: name = "globe"
            }
            return symbol(name)
        case .script(let script):
            if let emoji = script.icon { return emojiImage(emoji) }
            return symbol("scroll")
        }
    }

    private func emojiImage(_ emoji: String) -> NSImage? {
        let key = "emoji:\(emoji)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { rect in
            let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            let bounds = text.size()
            text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
            return true
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private func symbol(_ name: String) -> NSImage? {
        let key = "symbol:\(name)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private func icon(forFile path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard pending.insert(path).inserted else { return nil }
        Task.detached(priority: .userInitiated) {
            let boxed = Self.loadIcon(path: path)
            await MainActor.run { [weak self] in
                self?.store(boxed, path: path)
            }
        }
        return nil
    }

    private nonisolated static func loadIcon(path: String) -> SendableImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 24, height: 24)
        return SendableImage(image: image)
    }

    private func store(_ boxed: SendableImage, path: String) {
        cache.setObject(boxed.image, forKey: path as NSString)
        pending.remove(path)
        onLoaded?(path)
    }

    func prewarm(_ apps: [AppItem]) {
        for app in apps { _ = icon(forFile: app.url.path) }
    }
}
