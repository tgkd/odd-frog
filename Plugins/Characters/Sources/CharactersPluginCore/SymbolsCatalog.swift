import Foundation

extension CharacterCatalog {
    // Emoji-presentation characters live in the emoji catalog.
    public static func symbols() -> CharacterCatalog {
        var entries: [CharacterEntry] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else {
                    continue
                }
                let properties = scalar.properties
                guard !properties.isEmojiPresentation, let name = properties.name else {
                    continue
                }
                entries.append(entry(glyph: String(scalar), name: displayName(name), keywords: symbolAliases[String(scalar)] ?? ""))
            }
        }
        return CharacterCatalog(entries: entries, featured: symbolFeatured)
    }

    static let ranges: [ClosedRange<UInt32>] = [
        0x00A1...0x00BF, 0x00D7...0x00D7, 0x00F7...0x00F7, 0x0391...0x03C9,
        0x2010...0x2027, 0x2030...0x205E, 0x2070...0x209F, 0x20A0...0x20C0,
        0x2100...0x218B, 0x2190...0x23FF, 0x2500...0x27BF, 0x27F0...0x27FF,
        0x2900...0x297F, 0x2B00...0x2BFF,
    ]

    static let symbolFeatured = "→←↑↓⇒⌘⌥⇧⌃⏎⌫✓✗•…—–©®™°±×÷≠≈≤≥∞√€£¥₽§¶†πΩ"

    static let symbolAliases: [String: String] = Dictionary([
        ("×", "times multiply x"), ("÷", "divide"), ("±", "plus minus"), ("°", "degree deg"),
        ("…", "dots ellipsis"), ("–", "en dash hyphen"), ("—", "em dash"),
        ("←", "left arrow"), ("→", "right arrow"), ("↑", "up arrow"), ("↓", "down arrow"),
        ("↔", "left right arrow"), ("⇒", "implies right double arrow"), ("⇐", "left double arrow"),
        ("⌘", "command cmd mac"), ("⌥", "option alt mac"), ("⇧", "shift mac"), ("⌃", "control ctrl mac"),
        ("⎋", "escape esc mac"), ("⌫", "backspace delete mac"), ("⌦", "forward delete mac"),
        ("⏎", "return enter mac"), ("⇥", "tab mac"), ("⇪", "caps lock mac"), ("⏏", "eject mac"),
        ("✓", "check tick"), ("✗", "cross"), ("★", "star"), ("☆", "star"), ("♥", "heart"),
        ("≈", "approx"), ("≤", "less equal"), ("≥", "greater equal"), ("√", "root sqrt square root"),
        ("µ", "micro mu"), ("•", "bullet dot"), ("·", "middle dot interpunct"), ("§", "section"),
        ("¶", "paragraph pilcrow"), ("†", "dagger"), ("‰", "per mille"), ("™", "tm trademark"),
        ("©", "copyright c"), ("®", "registered r"), ("€", "euro eur"), ("₽", "ruble rub рубль"),
        ("£", "pound gbp"), ("¥", "yen jpy"), ("¢", "cent"),
    ] as [(String, String)], uniquingKeysWith: { first, _ in first })
}
