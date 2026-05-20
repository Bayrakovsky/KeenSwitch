import Foundation
import Testing
@testable import KeenSwitch

// MARK: - KeychainStoreTests
//
// Тесты Keychain используют уникальный account-ключ на каждый запуск, чтобы:
//   1) не пересекаться с реальным паролем пользователя,
//   2) обеспечивать чистый старт даже при падении предыдущего прогона.
//
// В CI Keychain недоступен только при запуске под sandboxed runner без HOME — на стандартных
// macOS-runner'ах GitHub Actions Generic Password keychain работает.

struct KeychainStoreTests {

    private static func uniqueAccount(_ tag: String) -> String {
        "keenswitch-tests-\(tag)-\(UUID().uuidString)"
    }

    @Test("save → load возвращает тот же пароль")
    func saveAndLoad() throws {
        let account = Self.uniqueAccount("roundtrip")
        defer { try? KeychainStore.deletePassword(account: account) }

        try KeychainStore.savePassword("hunter2", account: account)
        let loaded = try KeychainStore.loadPassword(account: account)
        #expect(loaded == "hunter2")
    }

    @Test("save поверх существующей записи перезаписывает значение")
    func saveOverwrites() throws {
        let account = Self.uniqueAccount("overwrite")
        defer { try? KeychainStore.deletePassword(account: account) }

        try KeychainStore.savePassword("first", account: account)
        try KeychainStore.savePassword("second", account: account)
        let loaded = try KeychainStore.loadPassword(account: account)
        #expect(loaded == "second")
    }

    @Test("load для несуществующего account возвращает nil, не бросает ошибку")
    func loadMissingReturnsNil() throws {
        let account = Self.uniqueAccount("missing")
        let loaded = try KeychainStore.loadPassword(account: account)
        #expect(loaded == nil)
    }

    @Test("delete несуществующей записи не бросает (errSecItemNotFound трактуется как успех)")
    func deleteMissingIsIdempotent() {
        let account = Self.uniqueAccount("delete-missing")
        #expect(throws: Never.self) {
            try KeychainStore.deletePassword(account: account)
        }
    }

    @Test("delete удаляет запись — последующий load возвращает nil")
    func deleteRemovesEntry() throws {
        let account = Self.uniqueAccount("delete-roundtrip")

        try KeychainStore.savePassword("temp", account: account)
        #expect(try KeychainStore.loadPassword(account: account) == "temp")

        try KeychainStore.deletePassword(account: account)
        #expect(try KeychainStore.loadPassword(account: account) == nil)
    }

    @Test("savePasswordWithRetry сохраняет с первой попытки, если Keychain доступен")
    func saveWithRetrySucceeds() async throws {
        let account = Self.uniqueAccount("retry-save")
        defer { try? KeychainStore.deletePassword(account: account) }

        try await KeychainStore.savePasswordWithRetry("retry-value", account: account)
        let loaded = try KeychainStore.loadPassword(account: account)
        #expect(loaded == "retry-value")
    }

    @Test("loadPasswordWithRetry читает уже записанный пароль")
    func loadWithRetrySucceeds() async throws {
        let account = Self.uniqueAccount("retry-load")
        defer { try? KeychainStore.deletePassword(account: account) }

        try KeychainStore.savePassword("retry-load-value", account: account)
        let loaded = try await KeychainStore.loadPasswordWithRetry(account: account)
        #expect(loaded == "retry-load-value")
    }

    @Test("Различные account-ключи хранятся независимо (например, router vs github-token)")
    func accountsAreIsolated() throws {
        let routerAccount = Self.uniqueAccount("router")
        let tokenAccount = Self.uniqueAccount("token")
        defer {
            try? KeychainStore.deletePassword(account: routerAccount)
            try? KeychainStore.deletePassword(account: tokenAccount)
        }

        try KeychainStore.savePassword("router-pass", account: routerAccount)
        try KeychainStore.savePassword("ghp_xxx", account: tokenAccount)

        #expect(try KeychainStore.loadPassword(account: routerAccount) == "router-pass")
        #expect(try KeychainStore.loadPassword(account: tokenAccount) == "ghp_xxx")
    }

    @Test("Пустая строка — валидный пароль (нет специальной обработки)")
    func emptyStringPassword() throws {
        let account = Self.uniqueAccount("empty")
        defer { try? KeychainStore.deletePassword(account: account) }

        try KeychainStore.savePassword("", account: account)
        #expect(try KeychainStore.loadPassword(account: account) == "")
    }

    @Test("UTF-8 строки сохраняются и читаются корректно")
    func utf8Password() throws {
        let account = Self.uniqueAccount("utf8")
        defer { try? KeychainStore.deletePassword(account: account) }

        let value = "пароль-🔐-密码"
        try KeychainStore.savePassword(value, account: account)
        #expect(try KeychainStore.loadPassword(account: account) == value)
    }
}
