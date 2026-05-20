import Foundation

// MARK: - RouterServiceProtocol
//
// Контракт сетевого доступа к роутеру Keenetic.
// AppViewModel работает только с этим протоколом — конкретная реализация (KeeneticService)
// может быть подменена в тестах на mock-объект без изменения логики ViewModel.

protocol RouterServiceProtocol: Sendable {
    /// Обновить учётные данные перед серией запросов.
    func configure(settings: RouterSettings, password: String) async

    /// Проверить соединение с заданными параметрами (используется в форме настроек).
    func testConnection(settings: RouterSettings, password: String) async throws -> RouterInfo

    /// Получить информацию о роутере (модель, прошивка, имя).
    func fetchRouterInfo() async throws -> RouterInfo

    /// Получить список политик маршрутизации.
    func fetchPolicies() async throws -> [AccessPolicy]

    /// Получить список устройств в сети роутера.
    func fetchDevices() async throws -> [NetworkDevice]

    /// Назначить политику маршрутизации устройству по MAC-адресу.
    func setPolicy(mac: String, policyName: String, saveConfiguration: Bool) async throws

    /// Получить актуальную карту MAC → имя политики с роутера.
    func fetchHostPolicyMap() async throws -> [String: String]

    /// Сбросить сохранённые учётные данные (при ошибке соединения).
    func disconnect() async
}
