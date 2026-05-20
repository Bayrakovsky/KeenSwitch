import Foundation

/// Настройки самого приложения macOS (не роутера).
struct AppPreferences: Codable, Equatable, Sendable {
    /// Добавить KeenSwitch в «Объекты входа» (SMAppService).
    var launchAtLogin: Bool
    /// При автозапуске не показывать главное окно — только иконка в строке меню.
    var quietLaunchAtLogin: Bool
    /// Код языка (например, "en", "ru"), nil — использовать системную локаль.
    var languageCode: String?
    /// Автоматически проверять обновления при запуске.
    var autoCheckForUpdates: Bool

    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case quietLaunchAtLogin
        case languageCode
        case autoCheckForUpdates
    }

    static let `default` = AppPreferences(
        launchAtLogin: false,
        quietLaunchAtLogin: true,
        languageCode: nil,
        autoCheckForUpdates: true
    )
}
