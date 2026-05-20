import Foundation
import ServiceManagement

// MARK: - LaunchAtLoginManager
//
// Регистрация KeenSwitch в «Объекты входа» macOS через SMAppService (macOS 13+).

enum LaunchAtLoginManager {
    enum LoginItemError: LocalizedError {
        case registrationFailed(String)
        case requiresApproval

        nonisolated var errorDescription: String? {
            switch self {
            case .registrationFailed(let details):
                return String(format: L10n.tr("Launch At Login Failed"), details)
            case .requiresApproval:
                return L10n.tr("Allow Login Items")
            }
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }

    /// Приводит регистрацию в соответствие с настройкой (после переустановки и т.п.).
    static func syncWithPreference(_ shouldEnable: Bool) throws {
        let currentlyEnabled = isEnabled
        if shouldEnable == currentlyEnabled { return }
        try setEnabled(shouldEnable)
    }

    private static func register() throws {
        switch SMAppService.mainApp.status {
        case .enabled:
            return
        case .requiresApproval:
            throw LoginItemError.requiresApproval
        case .notRegistered, .notFound:
            do {
                try SMAppService.mainApp.register()
            } catch {
                throw LoginItemError.registrationFailed(error.userFacingMessage)
            }
        @unknown default:
            do {
                try SMAppService.mainApp.register()
            } catch {
                throw LoginItemError.registrationFailed(error.userFacingMessage)
            }
        }
    }

    private static func unregister() throws {
        guard isEnabled else { return }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw LoginItemError.registrationFailed(error.userFacingMessage)
        }
    }
}
