import Foundation
@testable import KeenSwitch

// MARK: - MockRouterService
//
// Тестовая реализация RouterServiceProtocol.
// Конфигурируется через публичные свойства: devicesToReturn, policiesToReturn, errorToThrow.

final class MockRouterService: RouterServiceProtocol, @unchecked Sendable {

    // MARK: - Конфигурация ответов

    var devicesToReturn: [NetworkDevice] = []
    var policiesToReturn: [AccessPolicy] = []
    var routerInfoToReturn: RouterInfo = RouterInfo(
        hostname: "Router",
        model: "Keenetic",
        hardwareID: nil,
        firmwareRelease: nil,
        firmwareTitle: nil,
        vendor: nil,
        description: nil
    )
    var errorToThrow: Error? = nil
    var hostPolicyMapToReturn: [String: String] = [:]

    /// Искусственная задержка перед возвратом из «сетевых» методов. Позволяет тестам
    /// проверять отмену запросов: пока первый запрос «висит», тест запускает второй.
    var artificialDelayNanos: UInt64 = 0

    // MARK: - Счётчики вызовов (для проверки в тестах)

    private(set) var configureCallCount = 0
    private(set) var fetchDevicesCallCount = 0
    private(set) var fetchPoliciesCallCount = 0
    private(set) var setPolicyCallCount = 0
    private(set) var disconnectCallCount = 0
    /// Сколько раз метод увидел Task.isCancelled и завершился с CancellationError.
    private(set) var cancelledCallCount = 0

    var lastSetPolicyMAC: String?
    var lastSetPolicyName: String?

    private func sleepIfNeeded() async throws {
        guard artificialDelayNanos > 0 else { return }
        do {
            try await Task.sleep(nanoseconds: artificialDelayNanos)
        } catch is CancellationError {
            cancelledCallCount += 1
            throw CancellationError()
        }
    }

    // MARK: - RouterServiceProtocol

    func configure(settings: RouterSettings, password: String) async {
        configureCallCount += 1
    }

    func testConnection(settings: RouterSettings, password: String) async throws -> RouterInfo {
        try await sleepIfNeeded()
        if let error = errorToThrow { throw error }
        return routerInfoToReturn
    }

    func fetchRouterInfo() async throws -> RouterInfo {
        try await sleepIfNeeded()
        if let error = errorToThrow { throw error }
        return routerInfoToReturn
    }

    func fetchPolicies() async throws -> [AccessPolicy] {
        try await sleepIfNeeded()
        if let error = errorToThrow { throw error }
        fetchPoliciesCallCount += 1
        return policiesToReturn
    }

    func fetchDevices() async throws -> [NetworkDevice] {
        try await sleepIfNeeded()
        if let error = errorToThrow { throw error }
        fetchDevicesCallCount += 1
        return devicesToReturn
    }

    func setPolicy(mac: String, policyName: String, saveConfiguration: Bool) async throws {
        try await sleepIfNeeded()
        if let error = errorToThrow { throw error }
        setPolicyCallCount += 1
        lastSetPolicyMAC = mac
        lastSetPolicyName = policyName
    }

    func fetchHostPolicyMap() async throws -> [String: String] {
        try await sleepIfNeeded()
        if let error = errorToThrow { throw error }
        return hostPolicyMapToReturn
    }

    func disconnect() async {
        disconnectCallCount += 1
    }
}
