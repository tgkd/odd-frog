import Foundation

public struct TranslateLanguage: Sendable, Hashable {
    public var name: String
    public var code: String
    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }

    public static let all: [TranslateLanguage] = [
        TranslateLanguage(name: "Arabic", code: "ar"),
        TranslateLanguage(name: "Chinese", code: "zh"),
        TranslateLanguage(name: "Danish", code: "da"),
        TranslateLanguage(name: "Dutch", code: "nl"),
        TranslateLanguage(name: "English", code: "en"),
        TranslateLanguage(name: "French", code: "fr"),
        TranslateLanguage(name: "German", code: "de"),
        TranslateLanguage(name: "Indonesian", code: "id"),
        TranslateLanguage(name: "Italian", code: "it"),
        TranslateLanguage(name: "Japanese", code: "ja"),
        TranslateLanguage(name: "Korean", code: "ko"),
        TranslateLanguage(name: "Norwegian", code: "nb"),
        TranslateLanguage(name: "Polish", code: "pl"),
        TranslateLanguage(name: "Portuguese", code: "pt"),
        TranslateLanguage(name: "Russian", code: "ru"),
        TranslateLanguage(name: "Spanish", code: "es"),
        TranslateLanguage(name: "Swedish", code: "sv"),
        TranslateLanguage(name: "Turkish", code: "tr"),
        TranslateLanguage(name: "Ukrainian", code: "uk"),
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
