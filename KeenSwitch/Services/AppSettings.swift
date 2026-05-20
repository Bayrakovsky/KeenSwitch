import Foundation
import OSLog

// MARK: - AppSettings
//
// Персистентность в UserDefaults (настройки роутера, автозапуск, выбор устройства).
// Пароль — только в Keychain (см. KeychainStore), сюда не попадает.

enum AppSettings {
    private static let settingsKey = "routerSettings"
    private static let preferencesKey = "appPreferences"
    private static let selectedDeviceKey = "selectedDeviceMAC"
    private static let pinnedDevicesKey = "pinnedDeviceMACs"

    /// Ключ UserDefaults, где хранилось имя Keychain-аккаунта в старых версиях (до 1.1).
    /// Используется только для одноразовой миграции в AppViewModel.
    static let legacyKeychainAccountKey = "keychainAccount"

    private static let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "Settings")

    static var router: RouterSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: settingsKey),
                  var settings = try? JSONDecoder().decode(RouterSettings.self, from: data) else {
                logger.debug("RouterSettings не найдены в UserDefaults, возвращаем .default")
                return .default
            }
            settings.migrateLegacyPortIfNeeded()
            return settings
        }
        set {
            var value = newValue
            value.migrateLegacyPortIfNeeded()
            if let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: settingsKey)
            }
        }
    }

    static var preferences: AppPreferences {
        get {
            guard let data = UserDefaults.standard.data(forKey: preferencesKey),
                  let value = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
                logger.debug("AppPreferences не найдены в UserDefaults, возвращаем .default")
                return .default
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: preferencesKey)
            }
        }
    }

    static var selectedDeviceMAC: String? {
        get { UserDefaults.standard.string(forKey: selectedDeviceKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedDeviceKey) }
    }

    /// MAC закреплённых устройств (порядок = порядок в списке).
    static var pinnedDeviceMACs: [String] {
        get { UserDefaults.standard.stringArray(forKey: pinnedDevicesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: pinnedDevicesKey) }
    }

    /// Фиксированное имя Keychain-аккаунта. Не привязано к хосту — не создаёт осиротевших записей при смене роутера.
    static let keychainAccount = "router-password"
}
