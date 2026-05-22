import AppKit
import Foundation
import Observation
import OSLog

// MARK: - AppViewModel
//
// Тонкий координатор: управляет настройками, языком и автозапуском.
// Всё, что касается роутера (устройства, политики, соединение), делегируется RouterConnectionManager.
// Все экраны читают данные через AppViewModel; те, кому нужен прямой доступ, могут
// обращаться к viewModel.connection напрямую.

@MainActor
@Observable
final class AppViewModel {

    // MARK: - Зависимости

    /// Менеджер соединения: состояние, устройства, политики, сетевые операции.
    let connection: RouterConnectionManager

    /// Менеджер обновлений приложения.
    let updateChecker: UpdateChecker

    /// Монитор сетевой доступности для автообновления при восстановлении связи.
    let networkMonitor: NetworkMonitor

    private let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "ViewModel")
    private var saveDebounceTask: Task<Void, Never>?
    private var becomeActiveObserver: NSObjectProtocol?
    /// Подписка на восстановление сети. Живёт в AppViewModel (он существует всё время работы),
    /// поэтому автообновление срабатывает и в режиме только-меню-бар, где ContentView нет.
    private var networkRestoreObserver: NSObjectProtocol?

    // MARK: - Настройки подключения

    /// Параметры подключения к роутеру (хост, порт, логин).
    var settings = AppSettings.router

    /// Пароль хранится только в памяти; при старте читается из Keychain.
    var password = ""

    /// true если заполнены хост, имя пользователя и пароль.
    var isConfigured: Bool {
        !settings.host.isEmpty && !settings.username.isEmpty && !password.isEmpty
    }

    // MARK: - Настройки приложения

    /// Пользовательские настройки: язык, автозапуск, автообновления.
    var appPreferences = AppSettings.preferences

    /// Увеличивается при смене языка — заставляет SwiftUI перерисовать все тексты.
    private(set) var localeRevision = 0

    // MARK: - Инициализация

    init(service: (any RouterServiceProtocol)? = nil) {
        connection = RouterConnectionManager(service: service ?? KeeneticService())
        updateChecker = UpdateChecker()
        networkMonitor = NetworkMonitor()
        appPreferences = AppSettings.preferences
        LocalizationManager.apply(languageCode: appPreferences.languageCode)
        loadStoredPassword()

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleAppDidBecomeActive() }
        }

        networkRestoreObserver = NotificationCenter.default.addObserver(
            forName: .networkDidRestore,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshFromUI() }
        }

        Task { @MainActor in
            // Ждём завершения системных диалогов (Keychain, локальная сеть) при первом запуске.
            try? await Task.sleep(for: .milliseconds(800))
            await reloadStoredCredentialsIfNeeded()
            await connection.refreshIfNeeded()
            if appPreferences.autoCheckForUpdates {
                await updateChecker.checkForUpdates()
            }
        }
    }

    // MARK: - Форвардинг свойств RouterConnectionManager
    //
    // Вью-слой использует viewModel.X вместо viewModel.connection.X.
    // @Observable корректно транслирует изменения через вычисляемые свойства:
    // SwiftUI отслеживает доступ к connection.X внутри геттера и перерисовывает при изменении.

    var connectionState: ConnectionState { connection.connectionState }
    var routerInfo: RouterInfo? { connection.routerInfo }
    var statusMessage: String? {
        get { connection.statusMessage }
        set { connection.statusMessage = newValue }
    }
    var isBusy: Bool { connection.isBusy }
    var devices: [NetworkDevice] { connection.devices }
    var policies: [AccessPolicy] { connection.policies }
    var selectedDeviceMAC: String? {
        get { connection.selectedDeviceMAC }
        set { connection.selectedDeviceMAC = newValue }
    }
    var pinnedDeviceMACs: [String] {
        get { connection.pinnedDeviceMACs }
        set { connection.pinnedDeviceMACs = newValue }
    }
    var selectedDevice: NetworkDevice? { connection.selectedDevice }
    var pinnedDevices: [NetworkDevice] { connection.pinnedDevices }
    var unpinnedDevices: [NetworkDevice] { connection.unpinnedDevices }
    var displayDevices: [NetworkDevice] { connection.displayDevices }
    var onlineDevices: [NetworkDevice] { connection.onlineDevices }
    var offlineDevices: [NetworkDevice] { connection.offlineDevices }

    func isPinned(mac: String) -> Bool { connection.isPinned(mac: mac) }
    func setPinned(_ pinned: Bool, mac: String) { connection.setPinned(pinned, mac: mac) }
    func togglePin(mac: String) { connection.togglePin(mac: mac) }
    func selectDevice(_ mac: String?) { connection.selectDevice(mac) }
    func activePolicy(for device: NetworkDevice?) -> AccessPolicy? { connection.activePolicy(for: device) }

    func refreshIfNeeded() async {
        // При тихом старте credentials могли ещё не подгрузиться (Keychain заблокирован).
        // Перед запросом убеждаемся, что они есть — иначе connection молча выйдет по guard.
        if !connection.hasCredentials {
            await reloadStoredCredentialsIfNeeded()
        }
        await connection.refreshIfNeeded()
    }
    func refreshAll() async { await connection.refreshAll() }
    func applyPolicy(_ policy: AccessPolicy, for mac: String? = nil) async {
        await connection.applyPolicy(policy, for: mac)
    }
    func testConnection() async {
        await saveConnectionSettings()
        await connection.testConnection(settings: settings, password: password)
        guard connection.connectionState == .connected else { return }
        await connection.refreshAll()
    }
    func disconnect() async { await connection.disconnect() }

    // MARK: - Настройки подключения — операции

    /// Читает пароль из Keychain при старте; при необходимости выполняет одноразовую миграцию.
    func loadStoredPassword() {
        if let stored = try? KeychainStore.loadPassword(account: AppSettings.keychainAccount) {
            password = stored
            return
        }
        migrateKeychainIfNeeded()
    }

    /// Повторная загрузка credentials после системных диалогов первого запуска.
    func reloadStoredCredentialsIfNeeded() async {
        if password.isEmpty {
            if let stored = try? await KeychainStore.loadPasswordWithRetry(account: AppSettings.keychainAccount) {
                password = stored
            } else {
                migrateKeychainIfNeeded()
            }
        }
        guard isConfigured else { return }
        await applyStoredCredentials()
    }

    private func handleAppDidBecomeActive() async {
        let wasConfigured = connection.hasCredentials
        await reloadStoredCredentialsIfNeeded()
        guard isConfigured else { return }
        if !wasConfigured || connection.devices.isEmpty || connection.connectionState != .connected {
            await connection.refreshIfNeeded()
        }
    }

    /// Refresh, вызываемый из UI (кнопки в окне и menu bar). В отличие от «голого»
    /// refreshAll, сначала пытается дочитать credentials: при тихом старте Keychain
    /// мог быть заблокирован, и без этого refreshAll молча выходит по guard hasCredentials.
    func refreshFromUI() async {
        if !connection.hasCredentials {
            await reloadStoredCredentialsIfNeeded()
        }
        await connection.refreshAll()
    }

    /// Отложенное сохранение при наборе текста в форме подключения.
    func scheduleSaveConnectionSettings() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await saveConnectionSettings()
        }
    }

    /// Переносит пароль из старого хост-зависимого Keychain-аккаунта в фиксированный.
    /// Запускается один раз при первом старте после обновления до версии с фиксированным аккаунтом.
    private func migrateKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacyAccount = defaults.string(forKey: AppSettings.legacyKeychainAccountKey),
              !legacyAccount.isEmpty,
              legacyAccount != AppSettings.keychainAccount else { return }

        // ВАЖНО: маркер миграции стираем только если чтение Keychain РЕАЛЬНО состоялось
        // (мигрировали пароль или старой записи нет). При временной ошибке — например,
        // Keychain ещё заблокирован на тихом старте — loadPassword бросает; тогда маркер
        // оставляем, чтобы повторить миграцию на следующем запуске и не потерять пароль.
        do {
            let migrated = try KeychainStore.loadPassword(account: legacyAccount)
            if let pw = migrated, !pw.isEmpty {
                try? KeychainStore.savePassword(pw, account: AppSettings.keychainAccount)
                try? KeychainStore.deletePassword(account: legacyAccount)
                password = pw
            }
            defaults.removeObject(forKey: AppSettings.legacyKeychainAccountKey)
        } catch {
            logger.error("Keychain migration deferred: \(error.localizedDescription)")
        }
    }

    /// Применяет сохранённые credentials к RouterConnectionManager (единственный вызов configure).
    private func applyStoredCredentials() async {
        guard isConfigured else { return }
        await connection.updateCredentials(settings: settings, password: password)
    }

    /// Сохраняет настройки подключения и обновляет credentials в RouterConnectionManager.
    func saveConnectionSettings() async {
        settings.normalize()
        settings.migrateLegacyPortIfNeeded()
        AppSettings.router = settings

        if !password.isEmpty {
            do {
                try await KeychainStore.savePasswordWithRetry(password, account: AppSettings.keychainAccount)
            } catch {
                logger.error("Keychain save failed: \(error.localizedDescription)")
                statusMessage = error.userFacingMessage
            }
        }

        await connection.updateCredentials(settings: settings, password: password)
    }

    /// Сохраняет только поведение роутера (без сброса соединения).
    func saveRouterBehaviorSettings() {
        AppSettings.router = settings
    }

    /// Сохраняет всё: подключение, настройки приложения, автозапуск.
    func saveSettings() async {
        await saveConnectionSettings()
        AppSettings.preferences = appPreferences
        _ = applyLaunchAtLoginPreference()
    }

    // MARK: - Настройки приложения — операции

    /// Переключает автозапуск и синхронизирует с Login Items.
    /// Возвращает сообщение об ошибке, если синхронизация не удалась.
    @discardableResult
    func updateLaunchAtLogin(enabled: Bool) -> String? {
        appPreferences.launchAtLogin = enabled
        return applyLaunchAtLoginPreference()
    }

    /// Сохраняет настройки приложения и синхронизирует автозапуск.
    func persistAppPreferences() {
        AppSettings.preferences = appPreferences
        _ = applyLaunchAtLoginPreference()
    }

    /// Переключает язык интерфейса и немедленно применяет его.
    func setAppLanguage(_ language: AppLanguage) {
        let code = language.languageCode
        guard appPreferences.languageCode != code else { return }
        appPreferences.languageCode = code
        AppSettings.preferences = appPreferences
        applyAppLanguage()
    }

    /// Применяет текущий язык к LocalizationManager и инкрементирует localeRevision.
    func applyAppLanguage() {
        LocalizationManager.apply(languageCode: appPreferences.languageCode)
        localeRevision += 1
    }

    @discardableResult
    private func applyLaunchAtLoginPreference() -> String? {
        AppSettings.preferences = appPreferences
        do {
            try LaunchAtLoginManager.syncWithPreference(appPreferences.launchAtLogin)
            appPreferences.launchAtLogin = LaunchAtLoginManager.isEnabled
            AppSettings.preferences = appPreferences
            return nil
        } catch {
            let message = error.userFacingMessage
            appPreferences.launchAtLogin = LaunchAtLoginManager.isEnabled
            return message
        }
    }

    // MARK: - Вспомогательные

    /// Строка вида «https://192.168.1.1» или «http://192.168.1.1:8080» для отображения в UI.
    func connectionEndpointLabel() -> String {
        let scheme = settings.useHTTPS ? "https" : "http"
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPort = settings.useHTTPS ? 443 : 80
        if settings.port == defaultPort {
            return "\(scheme)://\(host)"
        }
        return "\(scheme)://\(host):\(settings.port)"
    }
}
