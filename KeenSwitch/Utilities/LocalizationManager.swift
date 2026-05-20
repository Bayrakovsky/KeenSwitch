import Foundation

// MARK: - LocalizationManager
//
// Точка входа для UI: смена языка с MainActor.

enum LocalizationManager {
    nonisolated static var locale: Locale { LocalizationStorage.locale }

    @MainActor
    static func apply(languageCode: String?) {
        LocalizationStorage.setLanguageCode(languageCode)
    }
}
