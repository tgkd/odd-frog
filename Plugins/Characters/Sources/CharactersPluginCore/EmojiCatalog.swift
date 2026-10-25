import Foundation

extension CharacterCatalog {
    /// Single-scalar emoji named by Unicode, plus a flag for every ISO region.
    /// Skin tones and ZWJ sequences are not listed.
    public static func emoji(locale: Locale = .current) -> CharacterCatalog {
        var entries: [CharacterEntry] = []
        for range in [0x203C...0x3299, 0x1F000...0x1FAFF] as [ClosedRange<UInt32>] {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else {
                    continue
                }
                let properties = scalar.properties
                guard properties.isEmoji, !properties.isEmojiModifier, !(0x1F1E6...0x1F1FF).contains(value),
                      let name = properties.name else {
                    continue
                }
                let glyph = String(scalar) + (properties.isEmojiPresentation ? "" : "\u{FE0F}")
                entries.append(entry(glyph: glyph, name: displayName(name), keywords: aliases[String(scalar)] ?? ""))
            }
        }
        entries += flags(locale: locale)
        return CharacterCatalog(entries: entries, featured: featured)
    }

    static func flags(locale: Locale) -> [CharacterEntry] {
        let english = Locale(identifier: "en")
        let indicators = Array(UInt32(0x1F1E6)...UInt32(0x1F1FF)).compactMap(Unicode.Scalar.init)
        return Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier
            guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }),
                  let name = english.localizedString(forRegionCode: code) else {
                return nil
            }
            let glyph = String(String.UnicodeScalarView(code.uppercased().unicodeScalars.map {
                indicators[Int($0.value) - 0x41]
            }))
            let local = locale.localizedString(forRegionCode: code) ?? ""
            return entry(glyph: glyph, name: "Flag: \(name)", keywords: "\(code) \(local)")
        }
    }

    static let featured = "😀😂🙂😊😍😎🤔😉😢😭😡🥳🤯🙏👍👎👏👋👌🤝💪👀❤💔🔥✨⭐🎉💯✅❌⚠🚀💡🐛🎯📌🔒🔑📝☕🐸🤷"

    // Unicode names read like "white smiling face" or "heavy black heart", so common words go here.
    static let aliases: [String: String] = Dictionary([
        ("😀", "smile happy улыбка"), ("😂", "lol laugh joy tears смех"), ("🙂", "smile"),
        ("😊", "blush smile happy"), ("😍", "love heart eyes"), ("😎", "cool sunglasses"),
        ("😢", "sad cry грусть"), ("😭", "sob cry плач"), ("😡", "angry mad злой"),
        ("🤔", "think thinking hmm думаю"), ("😴", "sleep zzz сон"), ("😉", "wink подмигивание"),
        ("🙃", "upside down"), ("😅", "sweat smile nervous"), ("🤣", "rofl lol"),
        ("😱", "scream shock"), ("🥳", "party celebrate"), ("🤯", "mind blown explode"),
        ("🙏", "pray please thanks спасибо молитва"), ("👍", "thumbs up like yes ok лайк"),
        ("👎", "thumbs down dislike no"), ("👏", "clap applause аплодисменты"),
        ("🙌", "praise hooray hands up"), ("👋", "wave hello hi привет"), ("👌", "ok perfect"),
        ("✌", "peace victory"), ("🤝", "handshake deal"), ("💪", "muscle strong flex"),
        ("👀", "eyes look глаза"), ("❤", "heart love red сердце любовь"), ("💔", "broken heart"),
        ("🔥", "fire hot lit огонь"), ("✨", "sparkles magic shine"), ("⭐", "star звезда"),
        ("🎉", "tada party celebration hooray"), ("💯", "hundred perfect score"),
        ("✅", "check done yes ok"), ("❌", "cross no wrong"), ("⚠", "warning caution"),
        ("❓", "question"), ("❗", "exclamation"), ("🚀", "rocket launch ship"),
        ("💡", "idea bulb"), ("🐛", "bug"), ("🎯", "target goal"), ("📌", "pin"),
        ("📎", "paperclip attach"), ("🔒", "lock secure"), ("🔑", "key"),
        ("📝", "memo note write"), ("📅", "calendar date"), ("☕", "coffee tea кофе"),
        ("🍕", "pizza"), ("🍺", "beer"), ("🎁", "gift present"), ("💰", "money bag"),
        ("💩", "poop shit"), ("🤷", "shrug idk"), ("🤦", "facepalm"), ("🐸", "frog лягушка"),
        ("🐱", "cat кот"), ("🐶", "dog собака"), ("☀", "sun sunny солнце"), ("🌙", "moon night"),
        ("🌈", "rainbow"), ("⚡", "lightning zap bolt"), ("✔", "check mark tick"),
    ] as [(String, String)], uniquingKeysWith: { first, _ in first })
}
