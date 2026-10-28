import Foundation
import OddFrogPluginAPI

public enum TranslateProvider {
    public enum Online: Sendable, Equatable {
        case off
        case pending
        case done(TranslationOutcome)
    }
    static let languageSettingsURL = "x-apple.systempreferences:com.apple.Localization-Settings.extension"

    public static func respond(to request: PluginQuery, direction: TranslateDirection,
                               offline: TranslationOutcome?, online: Online) -> [PluginItem] {
        let pair = "\(direction.source.name) → \(direction.target.name)"
        guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let engines = online == .off ? "Apple Translation" : "Apple Translation and DeepL"
            return [PluginItem(id: "hint", title: "Type text to translate",
                               subtitle: "\(direction.target.name) ⇄ \(direction.source.name) · \(engines)",
                               kind: "Translate", symbol: "character.bubble")]
        }
        guard direction.source != direction.target else {
            return [PluginItem(id: "same", title: "Pick two different languages in Translate settings.",
                               kind: "Translate", symbol: "exclamationmark.triangle")]
        }
        if case .text(let apple) = offline, case .done(.text(let deepL)) = online, apple == deepL {
            return [translation(apple, id: "apple", subtitle: "Apple and DeepL · \(pair)")]
        }
        var rows = [appleRow(offline, direction: direction, pair: pair)]
        switch online {
        case .off:
            break
        case .pending:
            rows.append(PluginItem(id: "deepl", title: "Translating with DeepL…", subtitle: "DeepL · \(pair)",
                                   kind: "Translate", symbol: "hourglass"))
        case .done(.text(let text)):
            rows.append(translation(text, id: "deepl", subtitle: "DeepL · \(pair)"))
        case .done(.failed(let message)):
            rows.append(PluginItem(id: "deepl", title: "DeepL translation failed", subtitle: message,
                                   kind: "Translate", symbol: "exclamationmark.triangle"))
        case .done:
            rows.append(PluginItem(id: "deepl", title: "DeepL can't translate \(pair)",
                                   kind: "Translate", symbol: "exclamationmark.triangle"))
        }
        return rows
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

    private static func translation(_ text: String, id: String, subtitle: String) -> PluginItem {
        PluginItem(id: id, title: text, subtitle: subtitle, kind: "Translate", symbol: "translate",
                   primary: PluginAction(.paste, text), secondary: PluginAction(.copy, text))
    }
}
