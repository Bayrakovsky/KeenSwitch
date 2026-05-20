import Network
import Observation
import OSLog

// MARK: - NetworkMonitor
//
// Следит за доступностью сети через NWPathMonitor.
// При восстановлении соединения после обрыва инициирует автообновление данных с роутера.

@Observable
@MainActor
final class NetworkMonitor {

    /// true пока хотя бы один сетевой путь удовлетворён (WiFi, Ethernet, Cellular).
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "Network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleUpdate(connected: connected)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bayrakovskiy.KeenSwitch.network", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    private func handleUpdate(connected: Bool) {
        let restored = !isConnected && connected
        isConnected = connected
        logger.info("Сеть: \(connected ? "подключена" : "недоступна")")
        if restored {
            NotificationCenter.default.post(name: .networkDidRestore, object: nil)
        }
    }
}

extension Notification.Name {
    static let networkDidRestore = Notification.Name("com.bayrakovskiy.KeenSwitch.networkDidRestore")
}
