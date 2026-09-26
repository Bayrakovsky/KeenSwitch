import Foundation

// MARK: - LocalizationStorage
//
// Потокобезопасное хранилище bundle/locale без привязки к MainActor.

nonisolated enum LocalizationStorage: Sendable {
    private struct Snapshot: Sendable {
        var bundle: Bundle
        var locale: Locale
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var snapshot = Snapshot(bundle: .main, locale: .autoupdatingCurrent)

    static var bundle: Bundle {
        lock.withLock { snapshot.bundle }
    }

    static var locale: Locale {
        lock.withLock { snapshot.locale }
    }

    static func setLanguageCode(_ languageCode: String?) {
        let next = makeSnapshot(languageCode: languageCode)
        lock.withLock { snapshot = next }
    }

    private static func makeSnapshot(languageCode: String?) -> Snapshot {
        if let code = languageCode,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return Snapshot(bundle: localizedBundle, locale: Locale(identifier: code))
        }
        return Snapshot(bundle: .main, locale: .autoupdatingCurrent)
    }
}

nonisolated private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
