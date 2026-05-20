import Foundation
import Observation
import OSLog

// MARK: - RouterConnectionManager
//
// Управляет состоянием соединения с роутером и списком устройств/политик.
// Хранит учётные данные и выступает единственной точкой входа для сетевых операций.
// AppViewModel держит один экземпляр и делегирует ему всё, что касается роутера.

@Observable
@MainActor
final class RouterConnectionManager {

    // MARK: - Состояние соединения

    /// Текущий статус связи с роутером.
    private(set) var connectionState: ConnectionState = .disconnected

    /// Информация о роутере — модель, прошивка. Заполняется после успешного подключения.
    private(set) var routerInfo: RouterInfo?

    /// Человекочитаемое сообщение о статусе последней операции. Можно задавать снаружи
    /// (например, AppViewModel записывает ошибки из операций вне сетевого слоя).
    var statusMessage: String?

    /// true пока выполняется сетевой запрос.
    private(set) var isBusy = false

    // MARK: - Данные роутера

    /// Все устройства, загруженные с роутера.
    private(set) var devices: [NetworkDevice] = []

    /// Список политик маршрутизации.
    private(set) var policies: [AccessPolicy] = []

    // MARK: - Выбор и закрепление устройств

    /// MAC выбранного устройства; используется как ключ выделения в списке.
    var selectedDeviceMAC: String? {
        didSet { AppSettings.selectedDeviceMAC = selectedDeviceMAC }
    }

    /// Упорядоченный список MAC закреплённых устройств.
    var pinnedDeviceMACs: [String] = [] {
        didSet { AppSettings.pinnedDeviceMACs = pinnedDeviceMACs }
    }

    /// Выбранное устройство из текущего списка.
    var selectedDevice: NetworkDevice? {
        guard let selectedDeviceMAC else { return nil }
        return devices.first { $0.mac == selectedDeviceMAC }
    }

    /// Закреплённые устройства в том же порядке, что и pinnedDeviceMACs.
    var pinnedDevices: [NetworkDevice] {
        let byMAC = Dictionary(uniqueKeysWithValues: devices.map { ($0.mac, $0) })
        return pinnedDeviceMACs.compactMap { byMAC[$0] }
    }

    /// Незакреплённые устройства: онлайн → офлайн, внутри группы по имени.
    var unpinnedDevices: [NetworkDevice] {
        let pinnedSet = Set(pinnedDeviceMACs)
        return NetworkDevice.sortedForDisplay(devices.filter { !pinnedSet.contains($0.mac) })
    }

    /// Все устройства в порядке отображения: закреплённые → онлайн → офлайн.
    var displayDevices: [NetworkDevice] {
        NetworkDevice.sortedForDisplay(devices, pinnedMACs: pinnedDeviceMACs)
    }

    var onlineDevices: [NetworkDevice] { displayDevices.filter(\.isOnline) }
    var offlineDevices: [NetworkDevice] { displayDevices.filter { !$0.isOnline } }

    // MARK: - Зависимости

    private let service: any RouterServiceProtocol
    private let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "Connection")

    // MARK: - Внутреннее состояние

    /// Актуальные настройки подключения — обновляются через updateCredentials().
    private var currentSettings: RouterSettings?
    private var currentPassword: String = ""

    /// Есть ли учётные данные для подключения к роутеру.
    var hasCredentials: Bool { currentSettings != nil && !currentPassword.isEmpty }

    // MARK: - Task management (Fix 4 — отмена запросов)

    private var refreshTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?

    // MARK: - Init

    init(service: any RouterServiceProtocol) {
        self.service = service
        selectedDeviceMAC = AppSettings.selectedDeviceMAC
        pinnedDeviceMACs = AppSettings.pinnedDeviceMACs
    }

    convenience init() {
        self.init(service: KeeneticService())
    }

    // MARK: - Учётные данные (Fix 2 — единственная точка передачи credentials)

    /// Обновляет учётные данные в сервисе. Вызывается ТОЛЬКО при изменении настроек,
    /// не перед каждым запросом — в отличие от прежнего паттерна.
    func updateCredentials(settings: RouterSettings, password: String) async {
        currentSettings = settings
        currentPassword = password
        await service.configure(settings: settings, password: password)
    }

    // MARK: - Подключение

    /// Проверяет соединение с заданными параметрами (используется из формы настроек).
    /// Принимает явные settings/password т.к. форма может содержать несохранённые изменения.
    func testConnection(settings: RouterSettings, password: String) async {
        isBusy = true
        connectionState = .connecting
        statusMessage = L10n.tr("Testing Connection")
        routerInfo = nil

        do {
            let info = try await service.testConnection(settings: settings, password: password)
            routerInfo = info
            connectionState = .connected
            statusMessage = nil
        } catch {
            routerInfo = nil
            let message = error.userFacingMessage
            connectionState = .error(message)
            statusMessage = message
        }

        isBusy = false
    }

    func disconnect() async {
        await service.disconnect()
        connectionState = .disconnected
        routerInfo = nil
        statusMessage = L10n.tr("Disconnected")
    }

    // MARK: - Обновление данных (Fix 4 — отмена предыдущего запроса)

    /// Загружает данные только если они не актуальны или соединение разорвано.
    func refreshIfNeeded() async {
        guard hasCredentials, !isBusy else { return }
        if !devices.isEmpty, connectionState == .connected { return }
        await refreshAll()
    }

    /// Параллельно загружает устройства, политики и информацию о роутере.
    /// Отменяет предыдущий незавершённый запрос перед запуском нового.
    func refreshAll() async {
        guard hasCredentials else {
            connectionState = .error(L10n.tr("Fill Connection Settings"))
            return
        }
        refreshTask?.cancel()
        let task = Task { await doRefresh() }
        refreshTask = task
        await task.value
    }

    private func doRefresh() async {
        logger.info("Начало загрузки данных с роутера")
        isBusy = true
        connectionState = .connecting
        statusMessage = L10n.tr("Loading Router Data")

        do {
            async let policiesTask = service.fetchPolicies()
            async let devicesTask = service.fetchDevices()
            async let routerInfoTask = service.fetchRouterInfo()
            let (loadedPolicies, loadedDevices, loadedRouterInfo) = try await (
                policiesTask, devicesTask, routerInfoTask
            )

            guard !Task.isCancelled else {
                isBusy = false
                return
            }

            policies = loadedPolicies
            devices = loadedDevices
            routerInfo = loadedRouterInfo
            prunePinnedDevices()
            restoreSelectedDeviceAfterRefresh()
            connectionState = .connected
            statusMessage = refreshSummaryMessage()
            logger.info("Загружено: \(loadedDevices.count) устройств, \(loadedPolicies.count) политик")
        } catch {
            guard !Task.isCancelled else {
                isBusy = false
                return
            }
            logger.error("Ошибка загрузки: \(error.localizedDescription)")
            routerInfo = nil
            let message = error.userFacingMessage
            connectionState = .error(message)
            statusMessage = message
            await service.disconnect()
        }

        isBusy = false
    }

    // MARK: - Применение политики (Fix 4 — отмена предыдущего)

    /// Применяет политику маршрутизации к устройству и синхронизирует состояние с роутером.
    func applyPolicy(_ policy: AccessPolicy, for mac: String? = nil) async {
        let targetMAC = mac ?? selectedDeviceMAC
        guard let targetMAC else {
            statusMessage = L10n.tr("Select Device")
            return
        }
        applyTask?.cancel()
        let task = Task { await doApplyPolicy(policy, targetMAC: targetMAC) }
        applyTask = task
        await task.value
    }

    private func doApplyPolicy(_ policy: AccessPolicy, targetMAC: String) async {
        logger.info("Применение политики '\(policy.name)' к \(targetMAC)")
        isBusy = true
        statusMessage = String(format: L10n.tr("Applying Policy"), policy.localizedDisplayTitle)

        do {
            try await service.setPolicy(
                mac: targetMAC,
                policyName: policy.name,
                saveConfiguration: currentSettings?.saveConfigurationAfterChange ?? true
            )
            guard !Task.isCancelled else { isBusy = false; return }
            try await syncDevicePolicyFromRouter(mac: targetMAC)
            statusMessage = routingStatusMessage(for: targetMAC, expected: policy)
            connectionState = .connected
            logger.info("Политика '\(policy.name)' успешно применена")
        } catch {
            guard !Task.isCancelled else { isBusy = false; return }
            logger.error("Ошибка применения политики: \(error.localizedDescription)")
            let message = error.userFacingMessage
            statusMessage = message
            connectionState = .error(message)
        }

        isBusy = false
    }

    // MARK: - Политики устройств

    /// Политика роутера, назначенная устройству (если есть в загруженном списке политик).
    func activePolicy(for device: NetworkDevice?) -> AccessPolicy? {
        guard let device, let name = device.currentPolicy else { return nil }
        return policies.first { $0.name == name }
    }

    /// После POST перечитывает конфигурацию с роутера — источник правды, не локальный кэш.
    private func syncDevicePolicyFromRouter(mac: String) async throws {
        let policyMap = try await service.fetchHostPolicyMap()
        let normalizedMAC = mac.uppercased()
        updateDevicePolicy(mac: normalizedMAC, policyName: policyMap[normalizedMAC])
    }

    private func updateDevicePolicy(mac: String, policyName: String?) {
        guard let index = devices.firstIndex(where: { $0.mac == mac }) else { return }
        var device = devices[index]
        device.currentPolicy = policyName
        devices[index] = device
    }

    private func routingStatusMessage(for mac: String, expected: AccessPolicy) -> String {
        guard let device = devices.first(where: { $0.mac == mac }) else {
            return L10n.tr("Router Updated")
        }
        let onRouter = device.routingSummary(policies: policies)
        if activePolicy(for: device)?.name == expected.name { return onRouter }
        return String(format: L10n.tr("Mismatch On Router"), onRouter, expected.localizedDisplayTitle)
    }

    // MARK: - Устройства — выбор и закрепление

    func selectDevice(_ mac: String?) {
        selectedDeviceMAC = mac
    }

    func isPinned(mac: String) -> Bool {
        pinnedDeviceMACs.contains(mac)
    }

    func setPinned(_ pinned: Bool, mac: String) {
        if pinned {
            guard !pinnedDeviceMACs.contains(mac) else { return }
            pinnedDeviceMACs.append(mac)
        } else {
            pinnedDeviceMACs.removeAll { $0 == mac }
        }
    }

    func togglePin(mac: String) {
        setPinned(!isPinned(mac: mac), mac: mac)
    }

    // MARK: - Вспомогательные

    private func prunePinnedDevices() {
        let known = Set(devices.map(\.mac))
        let pruned = pinnedDeviceMACs.filter { known.contains($0) }
        if pruned.count != pinnedDeviceMACs.count {
            pinnedDeviceMACs = pruned
        }
    }

    private func restoreSelectedDeviceAfterRefresh() {
        if let saved = AppSettings.selectedDeviceMAC,
           devices.contains(where: { $0.mac == saved }) {
            selectedDeviceMAC = saved
            return
        }
        if let current = selectedDeviceMAC,
           devices.contains(where: { $0.mac == current }) {
            return
        }
        selectedDeviceMAC = devices.first(where: \.isOnline)?.mac ?? devices.first?.mac
    }

    private func refreshSummaryMessage() -> String {
        let dc = devices.count
        let pc = policies.count
        let dl = Self.pluralize(dc, one: L10n.tr("Device Count One"),
                                few: L10n.tr("Device Count Few"), many: L10n.tr("Device Count Many"))
        let pl = Self.pluralize(pc, one: L10n.tr("Policy Count One"),
                                few: L10n.tr("Policy Count Few"), many: L10n.tr("Policy Count Many"))
        return String(format: L10n.tr("Refreshed Summary"), dc, dl, pc, pl)
    }

    /// Склонение для русского: 1 устройство, 2 устройства, 5 устройств.
    static func pluralize(_ count: Int, one: String, few: String, many: String) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if (11...14).contains(mod100) { return many }
        switch mod10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }
}
