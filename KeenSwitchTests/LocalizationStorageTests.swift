import Foundation
import Testing
@testable import KeenSwitch

// MARK: - LocalizationStorageTests
//
// Хранилище потокобезопасно (NSLock), не зависит от MainActor.
// Тесты сериализованы (.serialized) — каждый тест сбрасывает состояние через setLanguageCode(nil),
// чтобы не оставлять побочный эффект для других тестов в пакете.

@Suite(.serialized)
struct LocalizationStorageTests {

    init() {
        LocalizationStorage.setLanguageCode(nil)
    }

    @Test("По умолчанию locale = autoupdatingCurrent, bundle = .main")
    func defaultsAfterReset() {
        LocalizationStorage.setLanguageCode(nil)
        #expect(LocalizationStorage.locale == .autoupdatingCurrent)
        #expect(LocalizationStorage.bundle == .main)
    }

    @Test("Установка русского кода обновляет locale")
    func russianLocale() {
        LocalizationStorage.setLanguageCode("ru")
        defer { LocalizationStorage.setLanguageCode(nil) }
        #expect(LocalizationStorage.locale.identifier == "ru")
    }

    @Test("Установка английского кода обновляет locale")
    func englishLocale() {
        LocalizationStorage.setLanguageCode("en")
        defer { LocalizationStorage.setLanguageCode(nil) }
        #expect(LocalizationStorage.locale.identifier == "en")
    }

    @Test("Невалидный код языка → fallback на main bundle и autoupdatingCurrent")
    func unknownCodeFallsBack() {
        LocalizationStorage.setLanguageCode("xx-fake")
        defer { LocalizationStorage.setLanguageCode(nil) }
        // Bundle.path(forResource: "xx-fake", ofType: "lproj") вернёт nil — снапшот сброшен.
        #expect(LocalizationStorage.locale == .autoupdatingCurrent)
        #expect(LocalizationStorage.bundle == .main)
    }

    @Test("Установка nil сбрасывает на дефолтный locale")
    func nilResetsToDefault() {
        LocalizationStorage.setLanguageCode("en")
        LocalizationStorage.setLanguageCode(nil)
        #expect(LocalizationStorage.locale == .autoupdatingCurrent)
    }

    @Test("Конкурентные чтения и записи не падают (lock работает)")
    func concurrentAccess() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    LocalizationStorage.setLanguageCode(i.isMultiple(of: 2) ? "ru" : "en")
                }
                group.addTask {
                    _ = LocalizationStorage.locale
                    _ = LocalizationStorage.bundle
                }
            }
        }
        // Главное условие — не упало. Финальное состояние неважно.
        LocalizationStorage.setLanguageCode(nil)
    }

    @Test("AppLanguage init корректно мапит коды в перечисление")
    func appLanguageInitMapping() {
        #expect(AppLanguage(languageCode: "ru") == .russian)
        #expect(AppLanguage(languageCode: "en") == .english)
        #expect(AppLanguage(languageCode: nil) == .automatic)
        #expect(AppLanguage(languageCode: "xx") == .automatic)
    }

    @Test("AppLanguage.languageCode совпадает с тем, что принимает init")
    func appLanguageRoundTrip() {
        for language in AppLanguage.allCases {
            let restored = AppLanguage(languageCode: language.languageCode)
            #expect(restored == language)
        }
    }
}
