import Foundation
import ServiceManagement
import Testing
@testable import KeenSwitch

// MARK: - LaunchAtLoginManagerTests
//
// Полноценная регистрация SMAppService.mainApp из тестовой обвязки невозможна:
// у тестового бандла нет своего entry в LaunchServices, поэтому система отказывает
// в register(). Тесты ограничены чтением статуса и идемпотентным sync вызовом.

struct LaunchAtLoginManagerTests {

    @Test("isEnabled возвращает Bool без падений")
    func isEnabledIsReadable() {
        _ = LaunchAtLoginManager.isEnabled
        // Никакого специфического значения не ожидаем — лишь то, что вызов не падает.
    }

    @Test("syncWithPreference согласованный с текущим состоянием — no-op")
    func syncWithCurrentStateIsNoop() {
        let current = LaunchAtLoginManager.isEnabled
        #expect(throws: Never.self) {
            try LaunchAtLoginManager.syncWithPreference(current)
        }
        #expect(LaunchAtLoginManager.isEnabled == current)
    }

    @Test("LoginItemError имеет локализованное errorDescription")
    func loginItemErrorDescriptions() {
        let approval = LaunchAtLoginManager.LoginItemError.requiresApproval
        #expect(approval.errorDescription != nil)
        #expect(!(approval.errorDescription ?? "").isEmpty)

        let failure = LaunchAtLoginManager.LoginItemError.registrationFailed("test")
        #expect(failure.errorDescription?.contains("test") == true)
    }

    @Test("isEnabled консистентен между двумя последовательными чтениями")
    func isEnabledIsStable() {
        let a = LaunchAtLoginManager.isEnabled
        let b = LaunchAtLoginManager.isEnabled
        #expect(a == b)
    }
}
