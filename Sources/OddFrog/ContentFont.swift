import AppKit
import OddFrogCore

@MainActor
struct ContentFont: Equatable {
    var family: String?
    var size: CGFloat

    static var current = ContentFont(family: nil, size: CGFloat(Settings.Appearance.defaultSize))

    init(family: String? = nil, size: CGFloat) {
        self.family = family
        self.size = size
    }

    init(_ appearance: Settings.Appearance) {
        self.init(family: appearance.fontFamily, size: CGFloat(appearance.fontSize))
    }

    func font(_ style: NSFont.TextStyle) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: style)
        let body = NSFont.preferredFont(forTextStyle: .body)
        let pointSize = (preferred.pointSize * (size / body.pointSize)).rounded()
        let resized = NSFont(descriptor: preferred.fontDescriptor, size: pointSize) ?? preferred
        guard let family else { return resized }
        return NSFontManager.shared.convert(resized, toFamily: family)
    }
}
