import AppKit

// MARK: - AppTermination
//
// Полный выход только по явному действию пользователя (меню Dock, ⌘Q).

enum AppTermination {
    private(set) static var userRequestedQuit = false

    /// Система инициировала logout / restart / shutdown. В этом случае нельзя отменять
    /// завершение (иначе приложение блокирует выход из системы), даже без явного «Quit».
    private(set) static var systemWillPowerOff = false

    /// Можно ли завершаться по-настоящему: по явному действию пользователя или при
    /// системном logout/restart/shutdown.
    static var allowsTermination: Bool {
        userRequestedQuit || systemWillPowerOff
    }

    static func quit() {
        userRequestedQuit = true
        NSApp.terminate(nil)
    }

    static func resetQuitRequest() {
        userRequestedQuit = false
    }

    /// Вызывается по NSWorkspace.willPowerOffNotification (logout/restart/shutdown).
    static func markSystemPowerOff() {
        systemWillPowerOff = true
    }
}
