import XCTest

// MARK: - KeenSwitchUITests
//
// Лёгкие smoke-проверки UI: приложение запускается, окно поднимается.
// Тяжёлые сценарии (Keychain, реальное соединение с роутером) намеренно опущены —
// они требуют внешней инфраструктуры, недоступной в CI. Логика покрыта юнит-тестами.

final class KeenSwitchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesWithoutCrashing() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testMainWindowExistsAfterLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // SwiftUI Window scene с id="main" — XCUI видит её как первое окно приложения.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
