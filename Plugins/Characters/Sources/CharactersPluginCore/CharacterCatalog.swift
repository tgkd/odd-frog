import Foundation

public enum CharacterKind: String, Sendable {
    case emoji, symbols
}

public struct CharacterEntry: Sendable, Hashable {
    public let glyph: String
    public let name: String
    let nameWords: [String]
    let keywordWords: [String]
    let keywordPhrase: String

    /// Code points as `U+1F600`, several joined by spaces for flags. Variation selectors stay out.
    public var code: String {
        glyph.unicodeScalars.filter { $0.value != 0xFE0F }
            .map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }
}

public struct CharacterCatalog: Sendable {
    public let entries: [CharacterEntry]
    public let featured: [CharacterEntry]

    init(entries: [CharacterEntry], featured: String) {
        self.entries = entries
        let byGlyph = Dictionary(entries.map { (Self.normalized($0.glyph), $0) }, uniquingKeysWith: { first, _ in first })
        self.featured = featured.map { byGlyph[Self.normalized(String($0))] }.compactMap { $0 }
    }

    /// Entries whose every query word matches a name word or keyword, best match first.
    public func search(_ query: String) -> [CharacterEntry] {
        let glyph = Self.normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let tokens = Self.words(Self.fold(query))
        let phrase = tokens.joined(separator: " ")
        guard !phrase.isEmpty || entries.contains(where: { Self.normalized($0.glyph) == glyph }) else {
            return []
        }
        var scored: [(score: Int, index: Int)] = []
        for (index, entry) in entries.enumerated() {
            if Self.normalized(entry.glyph) == glyph {
                scored.append((1000, index))
                continue
            }
            var total = 0
            for token in tokens {
                guard let score = Self.score(token, in: entry) else {
                    total = 0
                    break
                }
                total += score
            }
            if total > 0 {
                if entry.nameWords.joined(separator: " ").hasPrefix(phrase) {
                    total += 10
                }
                // An alias such as "right arrow" should beat longer names that merely contain both words.
                if entry.keywordPhrase.hasPrefix(phrase) {
                    total += 40
                }
                scored.append((total, index))
            }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            let (a, b) = (entries[$0.index].nameWords.count, entries[$1.index].nameWords.count)
            return a != b ? a < b : $0.index < $1.index
        }
        return scored.map { entries[$0.index] }
    }

    private static func score(_ token: String, in entry: CharacterEntry) -> Int? {
        var best: Int?
        func consider(_ words: [String], exact: Int, prefix: Int, inner: Int) {
            for word in words {
                let value: Int
                if word == token {
                    value = exact
                } else if word.hasPrefix(token) {
                    value = prefix
                } else if token.count >= 3, word.contains(token) {
                    value = inner
                } else {
                    continue
                }
                best = max(best ?? 0, value)
            }
        }
        consider(entry.nameWords, exact: 30, prefix: 20, inner: 5)
        consider(entry.keywordWords, exact: 25, prefix: 15, inner: 4)
        return best
    }

    static func entry(glyph: String, name: String, keywords: String = "") -> CharacterEntry {
        let keywordWords = words(fold(keywords))
        return CharacterEntry(glyph: glyph, name: name, nameWords: words(fold(name)), keywordWords: keywordWords,
                              keywordPhrase: keywordWords.joined(separator: " "))
    }

    static func displayName(_ raw: String) -> String {
        let lowered = raw.lowercased()
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func normalized(_ glyph: String) -> String {
        String(String.UnicodeScalarView(glyph.unicodeScalars.filter { $0.value != 0xFE0F }))
    }
}
