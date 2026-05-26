import Foundation
import Testing
@testable import KeenSwitch

// MARK: - RouterConnectionManagerTests
//
// Тестируем RouterConnectionManager через MockRouterService — без реальной сети.
// Каждый тест создаёт свой экземпляр менеджера, изоляция гарантирована.

@MainActor
struct RouterConnectionManagerTests {

    // MARK: - Начальное состояние

    @Test("Начальное состояние — disconnected, нет устройств")
    func initialState() {
        let manager = RouterConnectionManager(service: MockRouterService())
        #expect(manager.connectionState == .disconnected)
        #expect(manager.devices.isEmpty)
        #expect(manager.policies.isEmpty)
        #expect(!manager.isBusy)
        #expect(manager.statusMessage == nil)
    }

    // MARK: - refreshAll

    @Test("refreshAll — загружает устройства и политики при корректных credentials")
    func refreshAllSuccess() async {
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: "AA:BB:CC:DD:EE:FF", name: "MacBook", ip: "192.168.1.10",
                         interfaceName: "Home", isOnline: true, currentPolicy: nil),
            NetworkDevice(mac: "11:22:33:44:55:66", name: "iPhone", ip: "192.168.1.20",
                         interfaceName: "Home", isOnline: false, currentPolicy: "Policy0"),
        ]
        service.policiesToReturn = [
            AccessPolicy(name: "Policy0", description: "VPN", routingInterface: "OpenVPN0"),
        ]

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()

        #expect(manager.connectionState == .connected)
        #expect(manager.devices.count == 2)
        #expect(manager.policies.count == 1)
        #expect(!manager.isBusy)
        #expect(service.fetchDevicesCallCount == 1)
        #expect(service.fetchPoliciesCallCount == 1)
    }

    @Test("refreshAll — устанавливает .error при сетевой ошибке")
    func refreshAllNetworkError() async {
        let service = MockRouterService()
        service.errorToThrow = KeeneticError.connectionFailed("Нет связи")

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()

        if case .error(let msg) = manager.connectionState {
            #expect(msg.contains("Нет связи"))
        } else {
            Issue.record("Ожидался connectionState == .error")
        }
        #expect(manager.devices.isEmpty)
        #expect(!manager.isBusy)
        // Транзиентная ошибка refresh не должна рвать сессию авторизации:
        // следующая попытка обращается с уже валидными credentials.
        #expect(service.disconnectCallCount == 0)
    }

    @Test("refreshAll — не запускается без credentials")
    func refreshAllWithoutCredentials() async {
        let service = MockRouterService()
        let manager = RouterConnectionManager(service: service)

        // credentials не переданы — hasCredentials == false
        await manager.refreshAll()

        #expect(service.fetchDevicesCallCount == 0)
        if case .error = manager.connectionState {
            // ожидаемо — должна быть ошибка "Fill Connection Settings"
        } else {
            Issue.record("Ожидался connectionState == .error без credentials")
        }
    }

    // MARK: - applyPolicy

    @Test("applyPolicy — вызывает setPolicy на сервисе и обновляет статус")
    func applyPolicySuccess() async {
        let mac = "AA:BB:CC:DD:EE:FF"
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: mac, name: "MacBook", ip: nil,
                         interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]
        service.policiesToReturn = [
            AccessPolicy(name: "Policy0", description: "VPN", routingInterface: nil),
        ]
        service.hostPolicyMapToReturn = [mac: "Policy0"]

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()

        let policy = AccessPolicy(name: "Policy0", description: "VPN", routingInterface: nil)
        await manager.applyPolicy(policy, for: mac)

        #expect(service.setPolicyCallCount == 1)
        #expect(service.lastSetPolicyMAC == mac)
        #expect(service.lastSetPolicyName == "Policy0")
        #expect(!manager.isBusy)
        #expect(manager.connectionState == .connected)
    }

    // MARK: - Активная политика

    @Test("activePolicy — устройство без политики наследует встроенный segment")
    func activePolicyFallsBackToSegment() async {
        let mac = "AA:BB:CC:DD:EE:FF"
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: mac, name: "Mac", ip: nil,
                          interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]
        // В реальном потоке segment добавляет assignablePolicies; здесь — вручную.
        service.policiesToReturn = [
            AccessPolicy(name: "segment", description: nil, routingInterface: nil),
            AccessPolicy(name: "Policy0", description: "VPN", routingInterface: nil),
        ]

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()

        let device = manager.devices.first { $0.mac == mac }
        #expect(manager.activePolicy(for: device)?.name == "segment")
    }

    @Test("activePolicy — устройство с PolicyN возвращает именно её, не segment")
    func activePolicyReturnsAssignedPolicy() async {
        let mac = "AA:BB:CC:DD:EE:FF"
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: mac, name: "Mac", ip: nil,
                          interfaceName: nil, isOnline: true, currentPolicy: "Policy0"),
        ]
        service.policiesToReturn = [
            AccessPolicy(name: "segment", description: nil, routingInterface: nil),
            AccessPolicy(name: "Policy0", description: "VPN", routingInterface: nil),
        ]

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()

        let device = manager.devices.first { $0.mac == mac }
        #expect(manager.activePolicy(for: device)?.name == "Policy0")
    }

    @Test("activePolicy — nil device → nil")
    func activePolicyNilDevice() {
        let manager = RouterConnectionManager(service: MockRouterService())
        #expect(manager.activePolicy(for: nil) == nil)
    }

    // MARK: - Закрепление устройств

    @Test("togglePin — добавляет и снимает закрепление устройства")
    func togglePinDevice() async {
        let mac = "AA:BB:CC:DD:EE:01"
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: mac, name: "TV", ip: nil, interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()

        #expect(!manager.isPinned(mac: mac))
        manager.togglePin(mac: mac)
        #expect(manager.isPinned(mac: mac))
        #expect(manager.pinnedDevices.count == 1)

        manager.togglePin(mac: mac)
        #expect(!manager.isPinned(mac: mac))
        #expect(manager.pinnedDevices.isEmpty)
    }

    // MARK: - updateCredentials

    @Test("updateCredentials — вызывает configure на сервисе ровно один раз")
    func updateCredentialsConfigure() async {
        let service = MockRouterService()
        let manager = RouterConnectionManager(service: service)

        await manager.updateCredentials(settings: .default, password: "secret")

        #expect(service.configureCallCount == 1)
        #expect(manager.hasCredentials)
    }

    // MARK: - refreshIfNeeded

    @Test("refreshIfNeeded — пропускает повторную загрузку при connected + есть устройства")
    func refreshIfNeededSkipsWhenConnected() async {
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: "AA:BB:CC:DD:EE:FF", name: "PC", ip: nil,
                         interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]

        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        await manager.refreshAll()                 // первая загрузка
        let countAfterFirst = service.fetchDevicesCallCount

        await manager.refreshIfNeeded()            // должна пропустить
        #expect(service.fetchDevicesCallCount == countAfterFirst)
    }
}
