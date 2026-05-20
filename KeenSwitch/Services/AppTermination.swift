import AppKit

// MARK: - AppTermination
//
// Полный выход только по явному действию пользователя (меню Dock, ⌘Q).

enum AppTermination {
    private(set) static var userRequestedQuit = false

    static func quit() {
        userRequestedQuit = true
        NSApp.terminate(nil)
    }

    static func resetQuitRequest() {
        userRequestedQuit = false
    }
}
