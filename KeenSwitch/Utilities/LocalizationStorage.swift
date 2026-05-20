import Foundation

// MARK: - LocalizationStorage
//
// Потокобезопасное хранилище bundle/locale без привязки к MainActor.

enum LocalizationStorage: Sendable {
    private struct Snapshot: Sendable {
        var bundle: Bundle
        var locale: Locale
    }

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var snapshot = Snapshot(bundle: .main, locale: .autoupdatingCurrent)

    nonisolated static var bundle: Bundle {
        lock.withLock { snapshot.bundle }
    }

    nonisolated static var locale: Locale {
        lock.withLock { snapshot.locale }
    }

    nonisolated static func setLanguageCode(_ languageCode: String?) {
        let next = makeSnapshot(languageCode: languageCode)
        lock.withLock { snapshot = next }
    }

    private nonisolated static func makeSnapshot(languageCode: String?) -> Snapshot {
        if let code = languageCode,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return Snapshot(bundle: localizedBundle, locale: Locale(identifier: code))
        }
        return Snapshot(bundle: .main, locale: .autoupdatingCurrent)
    }
}

private extension NSLock {
    nonisolated func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
