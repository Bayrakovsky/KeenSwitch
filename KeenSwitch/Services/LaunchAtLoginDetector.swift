import AppKit

// MARK: - LaunchAtLoginDetector
//
// Определяет, запустилось ли приложение из автозагрузки (для тихого старта).

enum LaunchAtLoginDetector {
    /// Ключ Apple Event `keyLaunchIsLoginItem` (`'alis'`).
    private static let launchIsLoginItemKeyword: AEKeyword = 0x616C_6973

    /// Запуск из «Объекты входа» (kAEOpenApplication + keyLaunchIsLoginItem).
    static var isLoginItemLaunch: Bool {
        if ProcessInfo.processInfo.arguments.contains("--quiet-launch") {
            return true
        }

        // Старый механизм (loginwindow): Apple Event с ключом keyLaunchIsLoginItem.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           let descriptor = event.paramDescriptor(forKeyword: launchIsLoginItemKeyword),
           descriptor.booleanValue {
            return true
        }

        // SMAppService (macOS 13+): приложение запускает launchd, Apple Event не несёт
        // keyLaunchIsLoginItem. Launchd выставляет XPC_SERVICE_NAME = "application.<bundleID>…",
        // тогда как при ручном запуске это значение равно "0" или пусто.
        if let bundleID = Bundle.main.bundleIdentifier {
            let xpcName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? "0"
            if xpcName.hasPrefix("application.\(bundleID)") {
                return true
            }
        }

        return false
    }
}
