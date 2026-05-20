import Foundation

// MARK: - KeeneticService
//
// Тонкая обёртка над KeeneticRCIClient. Actor сериализует вызовы с роутера;
// ViewModel держит один экземпляр и передаёт актуальные settings/password через configure().

actor KeeneticService: RouterServiceProtocol {
    private var settings: RouterSettings?
    private var password: String?

    func configure(settings: RouterSettings, password: String) {
        self.settings = settings
        self.password = password
    }

    func disconnect() async {
        settings = nil
        password = nil
    }

    func testConnection(settings: RouterSettings, password: String) async throws -> RouterInfo {
        let client = KeeneticRCIClient(settings: settings, password: password)
        return try await client.testConnection()
    }

    func fetchRouterInfo() async throws -> RouterInfo {
        let client = try makeClient()
        return try await client.fetchRouterInfo()
    }

    func fetchPolicies() async throws -> [AccessPolicy] {
        let client = try makeClient()
        return try await client.fetchPolicies()
    }

    func fetchDevices() async throws -> [NetworkDevice] {
        let client = try makeClient()
        return try await client.fetchDevices()
    }

    func setPolicy(mac: String, policyName: String, saveConfiguration: Bool) async throws {
        let client = try makeClient()
        try await client.setPolicy(mac: mac, policyName: policyName, saveConfiguration: saveConfiguration)
    }

    func fetchHostPolicyMap() async throws -> [String: String] {
        let client = try makeClient()
        return try await client.fetchHostPolicyMap()
    }

    private func makeClient() throws -> KeeneticRCIClient {
        guard let settings, let password else {
            throw KeeneticError.notConfigured
        }
        return KeeneticRCIClient(settings: settings, password: password)
    }
}
