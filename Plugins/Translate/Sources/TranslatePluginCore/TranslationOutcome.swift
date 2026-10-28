import Foundation

public enum TranslationOutcome: Sendable, Equatable {
    case text(String)
    case notInstalled
    case unsupported
    case failed(String)
}

public protocol OfflineTranslator: Sendable {
    func translate(_ text: String, from source: TranslateLanguage, to target: TranslateLanguage) async -> TranslationOutcome
}

public protocol OnlineTranslator: Sendable {
    func translate(_ text: String, from source: TranslateLanguage, to target: TranslateLanguage, email: String) async -> TranslationOutcome
}
