import Foundation
import Testing
@testable import KeenSwitch

// MARK: - UpdateCheckerTests
//
// UpdateChecker сейчас завязан на сеть (api.github.com) и shell-установщик —
// полноценный интеграционный тест потребовал бы DI URLSession + Process, чего пока нет.
// Покрываем то, что доступно публично: версию из Bundle, State Equatable, сравнение версий,
// и стартовое состояние .idle.

@MainActor
struct UpdateCheckerTests {

    @Test("Начальное состояние UpdateChecker — .idle")
    func initialState() {
        let checker = UpdateChecker()
        #expect(checker.state == .idle)
    }

    @Test("State Equatable различает разные тэг-значения upToDate")
    func upToDateEquality() {
        let a = UpdateChecker.State.upToDate(version: "1.0.0")
        let b = UpdateChecker.State.upToDate(version: "1.0.0")
        let c = UpdateChecker.State.upToDate(version: "2.0.0")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("State Equatable: available с одинаковыми тройками равны")
    func availableEquality() {
        let a = UpdateChecker.State.available(current: "1.0.0", latest: "1.1.0", assetId: 42)
        let b = UpdateChecker.State.available(current: "1.0.0", latest: "1.1.0", assetId: 42)
        let c = UpdateChecker.State.available(current: "1.0.0", latest: "1.2.0", assetId: 42)
        let d = UpdateChecker.State.available(current: "1.0.0", latest: "1.1.0", assetId: 99)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("State Equatable: downloading сравнивает progress")
    func downloadingEquality() {
        #expect(UpdateChecker.State.downloading(progress: 0.5) == .downloading(progress: 0.5))
        #expect(UpdateChecker.State.downloading(progress: 0.5) != .downloading(progress: 0.6))
    }

    @Test("State Equatable: failed сравнивает текст ошибки")
    func failedEquality() {
        #expect(UpdateChecker.State.failed("net") == .failed("net"))
        #expect(UpdateChecker.State.failed("net") != .failed("io"))
    }

    @Test("State Equatable: разные кейсы не равны")
    func differentCasesNotEqual() {
        #expect(UpdateChecker.State.idle != .checking)
        #expect(UpdateChecker.State.checking != .installing)
        #expect(UpdateChecker.State.idle != .upToDate(version: "1.0"))
    }
}

// MARK: - String.isNewerVersionThan

struct VersionComparisonTests {

    @Test("1.0.1 новее, чем 1.0.0")
    func patchBump() {
        #expect("1.0.1".isNewerVersionThan("1.0.0"))
    }

    @Test("1.1.0 новее, чем 1.0.9")
    func minorBumpBeatsLargePatch() {
        #expect("1.1.0".isNewerVersionThan("1.0.9"))
    }

    @Test("2.0.0 новее, чем 1.99.99")
    func majorBump() {
        #expect("2.0.0".isNewerVersionThan("1.99.99"))
    }

    @Test("Та же версия не считается новее")
    func sameVersionNotNewer() {
        #expect(!"1.0.0".isNewerVersionThan("1.0.0"))
    }

    @Test("Старая версия не считается новее")
    func olderVersionNotNewer() {
        #expect(!"1.0.0".isNewerVersionThan("1.0.1"))
        #expect(!"1.0.0".isNewerVersionThan("2.0.0"))
    }

    @Test("Числовое сравнение — 1.0.10 новее, чем 1.0.9")
    func numericComparison() {
        // .numeric исключает лексикографическое 1.0.10 < 1.0.9.
        #expect("1.0.10".isNewerVersionThan("1.0.9"))
    }

    @Test("Bundle.appVersion возвращает не пустую строку (fallback или реальная версия)")
    func bundleAppVersionFallback() {
        let version = Bundle.main.appVersion
        #expect(!version.isEmpty)
    }
}
