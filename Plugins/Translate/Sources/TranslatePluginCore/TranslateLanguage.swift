import Foundation

public struct TranslateLanguage: Sendable, Hashable {
    public var name: String
    public var code: String
    public var deepLTarget: String
    public init(name: String, code: String, deepLTarget: String) {
        self.name = name
        self.code = code
        self.deepLTarget = deepLTarget
    }

    public static let all: [TranslateLanguage] = [
        TranslateLanguage(name: "Arabic", code: "ar", deepLTarget: "AR"),
        TranslateLanguage(name: "Chinese", code: "zh", deepLTarget: "ZH-HANS"),
        TranslateLanguage(name: "Danish", code: "da", deepLTarget: "DA"),
        TranslateLanguage(name: "Dutch", code: "nl", deepLTarget: "NL"),
        TranslateLanguage(name: "English", code: "en", deepLTarget: "EN-US"),
        TranslateLanguage(name: "French", code: "fr", deepLTarget: "FR"),
        TranslateLanguage(name: "German", code: "de", deepLTarget: "DE"),
        TranslateLanguage(name: "Indonesian", code: "id", deepLTarget: "ID"),
        TranslateLanguage(name: "Italian", code: "it", deepLTarget: "IT"),
        TranslateLanguage(name: "Japanese", code: "ja", deepLTarget: "JA"),
        TranslateLanguage(name: "Korean", code: "ko", deepLTarget: "KO"),
        TranslateLanguage(name: "Norwegian", code: "nb", deepLTarget: "NB"),
        TranslateLanguage(name: "Polish", code: "pl", deepLTarget: "PL"),
        TranslateLanguage(name: "Portuguese", code: "pt", deepLTarget: "PT-BR"),
        TranslateLanguage(name: "Russian", code: "ru", deepLTarget: "RU"),
        TranslateLanguage(name: "Spanish", code: "es", deepLTarget: "ES"),
        TranslateLanguage(name: "Swedish", code: "sv", deepLTarget: "SV"),
        TranslateLanguage(name: "Turkish", code: "tr", deepLTarget: "TR"),
        TranslateLanguage(name: "Ukrainian", code: "uk", deepLTarget: "UK"),
    ]
    public static let russian = named("Russian")!
    public static let english = named("English")!

    public static func named(_ name: String) -> TranslateLanguage? {
        all.first { $0.name == name }
    }

    public static func matching(code: String) -> TranslateLanguage? {
        guard let base = Locale.Language(identifier: code).languageCode?.identifier else {
            return nil
        }
        return all.first { $0.code == base }
    }
}
