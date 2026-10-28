import Foundation
import OddFrogPluginAPI

public enum TranslateProvider {
    public enum Online: Sendable, Equatable {
        case off
        case pending
        case done(TranslationOutcome)
    }
    public static let limit = 2_000
    static let languageSettingsURL = "x-apple.systempreferences:com.apple.Localization-Settings.extension"

    public static func hint(primary: TranslateLanguage, secondary: TranslateLanguage, deepL: Bool) -> [PluginItem] {
        let engines = deepL ? "Apple Translation and DeepL" : "Apple Translation"
        return [PluginItem(id: "hint", title: "Type text to translate",
                           subtitle: "\(primary.name) ⇄ \(secondary.name) · \(engines)",
                           kind: "Translate", symbol: "character.bubble")]
    }

    public static func sameLanguages() -> [PluginItem] {
        [PluginItem(id: "same", title: "Pick two different languages in Translate settings.",
                    kind: "Translate", symbol: "exclamationmark.triangle")]
    }

    public static func respond(direction: TranslateDirection, offline: TranslationOutcome?, online: Online,
                               truncated: Bool = false) -> [PluginItem] {
        let pair = "\(direction.source.name) → \(direction.target.name)" + (truncated ? " · first \(limit) characters" : "")
        if case .text(let apple) = offline, case .done(.text(let deepL)) = online, apple == deepL {
            return [translation(apple, id: "apple", subtitle: "Apple and DeepL · \(pair)")]
        }
        let apple = appleRow(offline, direction: direction, pair: pair)
        guard let deepL = deepLRow(online, pair: pair) else {
            return [apple]
        }
        if case .text = offline {
            return [apple, deepL]
        }
        if case .done(.text) = online {
            return [deepL, apple]
        }
        return [apple, deepL]
    }

    private static func appleRow(_ outcome: TranslationOutcome?, direction: TranslateDirection, pair: String) -> PluginItem {
        let subtitle = "Apple · \(pair)"
        switch outcome {
        case nil:
            return PluginItem(id: "apple", title: "Translating…", subtitle: subtitle, kind: "Translate", symbol: "hourglass")
        case .text(let text):
            return translation(text, id: "apple", subtitle: subtitle)
        case .notInstalled:
            return PluginItem(id: "apple", title: "Download \(direction.source.name) and \(direction.target.name) for offline translation",
                              subtitle: "Press Return to open Translation Languages in System Settings.",
                              kind: "Translate", symbol: "arrow.down.circle",
                              primary: PluginAction(.openURL, languageSettingsURL))
        case .unsupported:
            return PluginItem(id: "apple", title: "Apple can't translate \(pair)", kind: "Translate",
                              symbol: "exclamationmark.triangle")
        case .failed(let message):
            return PluginItem(id: "apple", title: "Apple Translation failed", subtitle: message, kind: "Translate",
                              symbol: "exclamationmark.triangle")
        }
    }

    private static func deepLRow(_ online: Online, pair: String) -> PluginItem? {
        switch online {
        case .off:
            return nil
        case .pending:
            return PluginItem(id: "deepl", title: "Translating with DeepL…", subtitle: "DeepL · \(pair)",
                              kind: "Translate", symbol: "hourglass")
        case .done(.text(let text)):
            return translation(text, id: "deepl", subtitle: "DeepL · \(pair)")
        case .done(.failed(let message)):
            return PluginItem(id: "deepl", title: "DeepL translation failed", subtitle: message,
                              kind: "Translate", symbol: "exclamationmark.triangle")
        case .done:
            return PluginItem(id: "deepl", title: "DeepL can't translate \(pair)",
                              kind: "Translate", symbol: "exclamationmark.triangle")
        }
    }

    private static func translation(_ text: String, id: String, subtitle: String) -> PluginItem {
        PluginItem(id: id, title: text, subtitle: subtitle, kind: "Translate", symbol: "translate",
                   primary: PluginAction(.paste, text), secondary: PluginAction(.copy, text))
    }
}
