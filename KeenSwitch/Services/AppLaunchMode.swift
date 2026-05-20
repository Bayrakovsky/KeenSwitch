import AppKit
import Foundation

// MARK: - AppLaunchMode
//
// Тихий старт (автозагрузка + настройка): только иконка в строке меню.
// Обычный старт (клик по приложению и т.п.): иконка + главное окно.

@MainActor
enum AppLaunchMode {
    /// Главное окно не показывать при появлении (тихий старт).
    private(set) static var suppressMainWindow = false

    private static var didConfigureActivationPolicy = false

    /// Определяется один раз при старте процесса.
    static func resolveAtStartup() {
        suppressMainWindow = isQuietLoginLaunch
    }

    /// LSUIElement в Info.plist убран — activation policy задаётся в коде до Window-сцены.
    /// Окно, созданное в .accessory, не получает vibrancy/glass и не «лечится» сменой политики.
    static func configureActivationPolicyAtLaunchIfNeeded() {
        guard !didConfigureActivationPolicy else { return }
        didConfigureActivationPolicy = true
        resolveAtStartup()
        let policy: NSApplication.ActivationPolicy = shouldShowMainWindowAtLaunch ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
    }

    /// Пользователь явно открыл главное окно (Open, Dock, ⌘N…).
    static func allowMainWindow() {
        suppressMainWindow = false
    }

    /// Автозагрузка с «тихим запуском».
    static var isQuietLoginLaunch: Bool {
        let preferences = AppSettings.preferences
        guard preferences.launchAtLogin, preferences.quietLaunchAtLogin else { return false }
        return LaunchAtLoginDetector.isLoginItemLaunch
    }

    static var shouldShowMainWindowAtLaunch: Bool {
        !suppressMainWindow
    }
}
