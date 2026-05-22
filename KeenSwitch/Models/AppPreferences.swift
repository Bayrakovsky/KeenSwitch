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

    init(
        launchAtLogin: Bool,
        quietLaunchAtLogin: Bool,
        languageCode: String?,
        autoCheckForUpdates: Bool
    ) {
        self.launchAtLogin = launchAtLogin
        self.quietLaunchAtLogin = quietLaunchAtLogin
        self.languageCode = languageCode
        self.autoCheckForUpdates = autoCheckForUpdates
    }

    /// Устойчивое декодирование: отсутствующие поля берутся из .default, а не роняют
    /// весь объект. Без этого добавление любого нового поля сбрасывало бы ВСЕ настройки
    /// существующих пользователей при обновлении (старый JSON не содержит нового ключа).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences.default
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
            ?? fallback.launchAtLogin
        quietLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .quietLaunchAtLogin)
            ?? fallback.quietLaunchAtLogin
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
            ?? fallback.languageCode
        autoCheckForUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckForUpdates)
            ?? fallback.autoCheckForUpdates
    }

    static let `default` = AppPreferences(
        launchAtLogin: false,
        quietLaunchAtLogin: true,
        languageCode: nil,
        autoCheckForUpdates: true
    )
}
