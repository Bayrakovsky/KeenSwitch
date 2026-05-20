import Foundation

/// Локализованная строка с учётом выбранного в настройках языка.
/// `nonisolated` — вызов допустим из сетевого слоя и моделей с `nonisolated`.
enum L10n: Sendable {
    nonisolated static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: LocalizationStorage.bundle, locale: LocalizationStorage.locale)
    }
}
