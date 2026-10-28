import Foundation
import Translation

public struct AppleTranslator: OfflineTranslator {
    public init() {}

    public func translate(_ text: String, from source: TranslateLanguage, to target: TranslateLanguage) async -> TranslationOutcome {
        let from = Locale.Language(identifier: source.code), to = Locale.Language(identifier: target.code)
        switch await LanguageAvailability().status(from: from, to: to) {
        case .installed:
            break
        case .supported:
            return .notInstalled
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
        do {
            return .text(try await TranslationSession(installedSource: from, target: to).translate(text).targetText)
        } catch TranslationError.notInstalled {
            return .notInstalled
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
