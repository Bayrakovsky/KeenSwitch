import Foundation

/// Локализованная строка с учётом выбранного в настройках языка.
/// Тип `nonisolated`: вызов допустим из сетевого слоя и из моделей, минуя MainActor.
nonisolated enum L10n: Sendable {
    static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: LocalizationStorage.bundle, locale: LocalizationStorage.locale)
    }
}
