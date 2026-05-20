import Foundation
import Testing
@testable import KeenSwitch

// MARK: - CancellationTests
//
// RouterConnectionManager хранит refreshTask и applyTask — при повторном вызове предыдущая
// задача должна быть отменена (Fix 4). Тесты используют MockRouterService.artificialDelayNanos,
// чтобы оставить первую задачу в полёте и проверить отмену.

@MainActor
struct CancellationTests {

    private func makeManager(delayMs: UInt64 = 200) async -> (RouterConnectionManager, MockRouterService) {
        let service = MockRouterService()
        service.artificialDelayNanos = delayMs * 1_000_000
        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")
        return (manager, service)
    }

    @Test("Второй вызов refreshAll отменяет первый")
    func refreshAllCancelsPrevious() async {
        let (manager, service) = await makeManager(delayMs: 300)

        let first = Task { await manager.refreshAll() }
        try? await Task.sleep(for: .milliseconds(50))

        let second = Task { await manager.refreshAll() }

        await first.value
        await second.value

        // Минимум один вызов был прерван по Task.isCancelled внутри MockRouterService.sleepIfNeeded.
        #expect(service.cancelledCallCount > 0)
    }

    @Test("Второй applyPolicy отменяет первый")
    func applyPolicyCancelsPrevious() async {
        let (manager, service) = await makeManager(delayMs: 300)

        // Сначала подгрузим список устройств без задержки.
        service.artificialDelayNanos = 0
        service.devicesToReturn = [
            NetworkDevice(mac: "AA:BB:CC:DD:EE:FF", name: "Mac", ip: nil,
                          interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]
        service.policiesToReturn = [
            AccessPolicy(name: "Policy0", description: nil, routingInterface: nil),
        ]
        await manager.refreshAll()

        // Теперь включим задержку для setPolicy и запустим два apply подряд.
        service.artificialDelayNanos = 300 * 1_000_000
        let policy = AccessPolicy(name: "Policy0", description: nil, routingInterface: nil)

        let first = Task { await manager.applyPolicy(policy, for: "AA:BB:CC:DD:EE:FF") }
        try? await Task.sleep(for: .milliseconds(50))
        let second = Task { await manager.applyPolicy(policy, for: "AA:BB:CC:DD:EE:FF") }

        await first.value
        await second.value

        #expect(service.cancelledCallCount > 0)
    }

    @Test("После отмены менеджер не остаётся в isBusy")
    func cancellationLeavesNoBusyFlag() async {
        let (manager, _) = await makeManager(delayMs: 300)

        let first = Task { await manager.refreshAll() }
        try? await Task.sleep(for: .milliseconds(50))
        let second = Task { await manager.refreshAll() }

        await first.value
        await second.value

        #expect(!manager.isBusy)
    }

    @Test("refreshIfNeeded — повторный вызов в течение одного 'окна' не запускает второй fetch")
    func refreshIfNeededDeduplicates() async {
        let service = MockRouterService()
        service.devicesToReturn = [
            NetworkDevice(mac: "AA:BB:CC:DD:EE:FF", name: "Mac", ip: nil,
                          interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]
        let manager = RouterConnectionManager(service: service)
        await manager.updateCredentials(settings: .default, password: "test")

        await manager.refreshAll()
        #expect(service.fetchDevicesCallCount == 1)

        await manager.refreshIfNeeded()
        await manager.refreshIfNeeded()
        // .connected + devices непусты → refreshIfNeeded пропускает.
        #expect(service.fetchDevicesCallCount == 1)
    }
}
