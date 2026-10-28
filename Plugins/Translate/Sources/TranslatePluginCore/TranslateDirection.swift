import Foundation
import NaturalLanguage
import OddFrogPluginAPI

public struct TranslateDirection: Sendable, Hashable {
    public var source: TranslateLanguage
    public var target: TranslateLanguage
    public init(source: TranslateLanguage, target: TranslateLanguage) {
        self.source = source
        self.target = target
    }

    public static func resolve(_ text: String, primary: TranslateLanguage, secondary: TranslateLanguage) -> TranslateDirection {
        let source = detect(text, primary: primary, secondary: secondary)
        return TranslateDirection(source: source, target: source == primary ? secondary : primary)
    }

    public static func languages(_ settings: [String: JSONValue]) -> (primary: TranslateLanguage, secondary: TranslateLanguage) {
        (settings["primary_language"]?.string.flatMap(TranslateLanguage.named) ?? .russian,
         settings["secondary_language"]?.string.flatMap(TranslateLanguage.named) ?? .english)
    }

    private static func detect(_ text: String, primary: TranslateLanguage, secondary: TranslateLanguage) -> TranslateLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = TranslateLanguage.all.map { NLLanguage($0.code) } + [.simplifiedChinese, .traditionalChinese]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
            .compactMap { language, probability in
                TranslateLanguage.matching(code: language.rawValue).map { ($0, probability) }
            }
            .sorted { $0.1 > $1.1 }
        // One or two words often look like a third language, so the chosen pair wins whenever it is plausible.
        if let preferred = hypotheses.first(where: { ($0.0 == primary || $0.0 == secondary) && $0.1 >= 0.15 }) {
            return preferred.0
        }
        return hypotheses.first?.0 ?? secondary
    }
}
