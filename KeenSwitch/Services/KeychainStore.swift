import Foundation
import Security

// MARK: - KeychainStore
//
// Хранение пароля роутера в связке ключей macOS (Generic Password).

nonisolated enum KeychainStore {
    private static let service = "com.bayrakovskiy.KeenSwitch.router"
    /// Аккаунт Keychain для хранения GitHub Token. Использовался когда репозиторий
    /// был приватным; сейчас не задействован. Константа оставлена для ссылок из
    /// закомментированного кода в UpdateChecker / SettingsView — на случай возврата
    /// к приватному режиму.
    static let githubTokenAccount = "github-token"

    private static let retryableStatuses: Set<OSStatus> = [
        errSecInteractionNotAllowed,
        errSecAuthFailed,
    ]

    static func savePassword(_ password: String, account: String) throws {
        try savePasswordOnce(password, account: account)
    }

    /// Повторяет запись после системных диалогов Keychain / Local Network при первом запуске.
    static func savePasswordWithRetry(_ password: String, account: String) async throws {
        try await performWithRetry {
            try savePasswordOnce(password, account: account)
        }
    }

    static func loadPassword(account: String) throws -> String? {
        try loadPasswordOnce(account: account)
    }

    static func loadPasswordWithRetry(account: String) async throws -> String? {
        try await performWithRetry {
            try loadPasswordOnce(account: account)
        }
    }

    static func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }

    // MARK: - Private

    private static func savePasswordOnce(_ password: String, account: String) throws {
        let data = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.operationFailed(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
    }

    private static func loadPasswordOnce(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.operationFailed(status)
        }

        return password
    }

    private static func performWithRetry<T>(
        maxAttempts: Int = 8,
        initialDelayMs: UInt64 = 200,
        operation: () throws -> T
    ) async throws -> T {
        var lastError: KeychainError?
        for attempt in 0..<maxAttempts {
            do {
                return try operation()
            } catch let error as KeychainError {
                lastError = error
                guard case .operationFailed(let status) = error,
                      retryableStatuses.contains(status),
                      attempt < maxAttempts - 1 else {
                    throw error
                }
                try await Task.sleep(for: .milliseconds(initialDelayMs * UInt64(attempt + 1)))
            }
        }
        throw lastError ?? KeychainError.operationFailed(errSecInternalComponent)
    }
}

nonisolated enum KeychainError: LocalizedError {
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            return String(format: L10n.tr("Keychain Error"), Int(status))
        }
    }
}
