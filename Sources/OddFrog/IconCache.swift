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
        case .app(let app):
            return icon(forFile: app.url.path, size: size)
        case .command(let command):
            switch command.action {
            case .shell:
                return tile(name: "shell", color: NSColor(white: 0.16, alpha: 1), glyph: "$", glyphSize: 13, size: size)
            case .path:
                return tile(name: "path", color: .systemBlue, symbol: "folder.fill", symbolSize: 12, size: size)
            case .url:
                return tile(name: "url", color: .systemTeal, symbol: "link", symbolSize: 14, size: size)
            }
        case .plugin(let result):
            return NSImage(systemSymbolName: result.item.symbol ?? "puzzlepiece.extension", accessibilityDescription: nil)
        case .script(let script):
            if let emoji = script.icon { return emojiImage(emoji, size: size) }
            return tile(name: "script", color: .systemGray, glyph: ">_", glyphSize: 10, size: size)
        case .window(let item):
            let symbol = switch item.action {
            case .place(.left, _): "rectangle.lefthalf.filled"
            case .place(.right, _): "rectangle.righthalf.filled"
            case .place(.top, _): "rectangle.tophalf.filled"
            case .place(.bottom, _): "rectangle.bottomhalf.filled"
            case .maximize: "rectangle.fill"
            case .tidy: "rectangle.stack.fill"
            }
            return tile(name: "window-" + symbol, color: .systemPurple, symbol: symbol, symbolSize: 13, size: size)
        case .quick(let quick):
            switch quick {
            case .openURL:
                return tile(name: "url", color: .systemTeal, symbol: "link", symbolSize: 14, size: size)
            case .webSearch:
                return tile(name: "search", color: .systemIndigo, symbol: "magnifyingglass", symbolSize: 13, size: size)
            case .terminal:
                return tile(name: "shell", color: NSColor(white: 0.16, alpha: 1), glyph: "$", glyphSize: 13, size: size)
            case .calculation(_, _, let kind):
                switch kind {
                case .arithmetic:
                    return tile(name: "calc", color: .systemOrange, symbol: "plus.forwardslash.minus", symbolSize: 13, size: size)
                case .measurement:
                    return tile(name: "units", color: .systemGreen, symbol: "ruler", symbolSize: 13, size: size)
                case .currency:
                    return tile(name: "currency", color: .systemMint, symbol: "dollarsign", symbolSize: 13, size: size)
                }
            }
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

    private func tile(name: String, color: NSColor, glyph: String, glyphSize: CGFloat, size: CGFloat) -> NSImage? {
        tile(name: name, color: color, size: size) { rect in
            let font = NSFont.monospacedSystemFont(ofSize: glyphSize * size / 24, weight: .bold)
            let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor.white])
            let bounds = text.size()
            text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
        }
    }

    private func tile(name: String, color: NSColor, symbol: String, symbolSize: CGFloat, size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize * size / 24, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        return tile(name: name, color: color, size: size) { rect in
            let bounds = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2, width: bounds.width, height: bounds.height))
        }
    }

    private func tile(name: String, color: NSColor, size: CGFloat, content: @escaping (NSRect) -> Void) -> NSImage? {
        let key = "tile:\(name):\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: size / 4, yRadius: size / 4).fill()
            content(rect)
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

    func prewarm(_ apps: [AppItem]) {
        let paths = apps.map(\.url.path).filter { path in
            cache.object(forKey: "app:\(path)" as NSString) == nil && !pending.contains(path)
        }
        guard !paths.isEmpty else { return }
        for path in paths { pending.insert(path) }
        Task.detached(priority: .utility) {
            for path in paths {
                let boxed = Self.loadIcon(path: path)
                await MainActor.run { [weak self] in
                    self?.store(boxed, path: path)
                }
            }
        }
    }
}
