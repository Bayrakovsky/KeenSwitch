import Foundation
import Testing
@testable import KeenSwitch

// MARK: - PersistenceModelTests
//
// Устойчивость декодирования персистентных моделей: старый/частичный JSON не должен
// ронять весь объект и сбрасывать настройки пользователя — отсутствующие поля берутся
// из значений по умолчанию.

struct PersistenceModelTests {

    // MARK: - AppPreferences

    @Test("AppPreferences: полный JSON декодируется как есть")
    func appPreferencesFullDecode() throws {
        let json = """
        {
          "launchAtLogin": true,
          "quietLaunchAtLogin": false,
          "languageCode": "ru",
          "autoCheckForUpdates": false
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(AppPreferences.self, from: json)
        #expect(p.launchAtLogin == true)
        #expect(p.quietLaunchAtLogin == false)
        #expect(p.languageCode == "ru")
        #expect(p.autoCheckForUpdates == false)
    }

    @Test("AppPreferences: отсутствие нового поля не роняет декодирование")
    func appPreferencesMissingNewFieldFallsBack() throws {
        // Старый JSON до появления autoCheckForUpdates.
        let json = """
        {
          "launchAtLogin": true,
          "quietLaunchAtLogin": false,
          "languageCode": "en"
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(AppPreferences.self, from: json)
        // Сохранённые поля остаются, новое берётся из .default — НЕ сброс всего объекта.
        #expect(p.launchAtLogin == true)
        #expect(p.quietLaunchAtLogin == false)
        #expect(p.languageCode == "en")
        #expect(p.autoCheckForUpdates == AppPreferences.default.autoCheckForUpdates)
    }

    @Test("AppPreferences: пустой объект → все значения по умолчанию")
    func appPreferencesEmptyObjectUsesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let p = try JSONDecoder().decode(AppPreferences.self, from: json)
        #expect(p == AppPreferences.default)
    }

    @Test("AppPreferences: encode → decode round-trip")
    func appPreferencesRoundTrip() throws {
        let original = AppPreferences(
            launchAtLogin: true,
            quietLaunchAtLogin: true,
            languageCode: "ru",
            autoCheckForUpdates: false
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(restored == original)
    }

    // MARK: - RouterSettings

    @Test("RouterSettings: старый JSON без useHTTPS/saveConfiguration не падает")
    func routerSettingsMissingFieldsFallBack() throws {
        let json = """
        {
          "host": "192.168.1.1",
          "port": 80,
          "username": "admin"
        }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(RouterSettings.self, from: json)
        #expect(s.host == "192.168.1.1")
        #expect(s.useHTTPS == false)
        #expect(s.saveConfigurationAfterChange == true)
    }

    @Test("RouterSettings: legacy-порт 23 мигрирует в HTTP 80")
    func routerSettingsLegacyPortMigration() {
        var s = RouterSettings.default
        s.port = 23
        s.migrateLegacyPortIfNeeded()
        #expect(s.port == RouterSettings.httpPort)
    }

    @Test("RouterSettings: encode → decode round-trip")
    func routerSettingsRoundTrip() throws {
        let original = RouterSettings(
            host: "10.0.0.1",
            port: 8080,
            useHTTPS: true,
            username: "root",
            saveConfigurationAfterChange: false
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(RouterSettings.self, from: data)
        #expect(restored == original)
    }
}
