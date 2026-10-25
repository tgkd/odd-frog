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

    /// Rows whose icon is a found character get a larger icon slot so the character is easy to read.
    static func side(for item: LauncherItem) -> CGFloat {
        if case .plugin(let result) = item, result.item.glyph != nil {
            return ResultRowView.glyphSide
        }
        return ResultRowView.iconSide
    }

    func icon(for item: LauncherItem, size: CGFloat = 24) -> NSImage? {
        switch item {
        case .plugin(let result):
            if let glyph = result.item.glyph { return glyphImage(glyph, size: size) }
            if let icon = result.item.icon {
                if icon.hasPrefix("text:") { return emojiImage(String(icon.dropFirst(5)), size: size) }
                if icon.hasPrefix("file:") { return self.icon(forFile: String(icon.dropFirst(5)), size: size) }
                let path = icon.hasPrefix("/") ? icon : result.directory?.appendingPathComponent(icon).path
                if let path {
                    if path.hasSuffix(".app") { return self.icon(forFile: path, size: size) }
                    if let image = NSImage(contentsOfFile: path) { return image }
                }
            }
            return NSImage(systemSymbolName: result.item.symbol ?? "puzzlepiece.extension", accessibilityDescription: nil)
        }
    }

    /// Color emoji keep their colors. Text-style characters become template images, so they follow
    /// the label color and turn white on the selected row like SF Symbols do.
    private func glyphImage(_ glyph: String, size: CGFloat) -> NSImage? {
        let isColor = glyph.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
        let image = textImage(glyph, size: size, fontScale: 0.8, fitsWidth: true, template: !isColor, kind: "glyph")
        image?.accessibilityDescription = glyph
        return image
    }

    private func emojiImage(_ emoji: String, size: CGFloat) -> NSImage? {
        textImage(emoji, size: size, fontScale: 20.0 / 24.0, fitsWidth: false, template: false, kind: "emoji")
    }

    private func textImage(_ text: String, size: CGFloat, fontScale: CGFloat, fitsWidth: Bool, template: Bool, kind: String) -> NSImage? {
        let key = "\(kind):\(text):\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        func attributed(_ fontSize: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black])
        }
        var drawn = attributed(size * fontScale)
        let width = drawn.size().width
        if fitsWidth, width > size * 0.95 { drawn = attributed(size * fontScale * size * 0.95 / width) }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let bounds = drawn.size()
            drawn.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
            return true
        }
        image.isTemplate = template
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
