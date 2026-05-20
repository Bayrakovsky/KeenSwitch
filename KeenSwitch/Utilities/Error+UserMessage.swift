import Foundation

// MARK: - Error+UserMessage
//
// Универсальный конвертер любой ошибки в строку для UI на языке приложения.
//
// Зачем: error.localizedDescription из системных типов (URLError, NSError от SMAppService,
// Foundation decoding errors) возвращается в системной локали macOS, а не в выбранной
// пользователем в KeenSwitch. Этот хелпер вычищает такие случаи через свои L10n-таблицы.

extension Error {
    /// Сообщение об ошибке на языке, выбранном пользователем в KeenSwitch.
    var userFacingMessage: String {
        // KeeneticError, UpdateError и другие LocalizedError уже дают L10n-строки.
        if let described = (self as? LocalizedError)?.errorDescription, !described.isEmpty {
            return described
        }

        if let urlError = self as? URLError {
            return URLErrorLocalization.message(for: urlError)
        }

        if self is CancellationError {
            return L10n.tr("Operation Cancelled")
        }

        // Foundation cocoa errors (Keychain, SMAppService, JSONDecoder) — оборачиваем
        // в шаблон с кодом, чтобы не светить системно-локализованный текст.
        let nsError = self as NSError
        return String(format: L10n.tr("Generic Error With Code"), nsError.code)
    }
}

// MARK: - URLErrorLocalization

/// Локализация URLError на язык приложения. Используется и в KeeneticRCIClient,
/// и в Error.userFacingMessage — общая точка истины для сетевых ошибок.
enum URLErrorLocalization {
    nonisolated static func message(for urlError: URLError) -> String {
        let url = urlError.failingURL
        let urlString = url?.absoluteString ?? ""
        let host = url?.host ?? L10n.tr("Keenetic Router")

        switch urlError.code {
        case .timedOut:
            return String(format: L10n.tr("Connection Timeout"), urlString.isEmpty ? host : urlString)
        case .cannotConnectToHost, .networkConnectionLost:
            return String(format: L10n.tr("No Connection To Host"), host)
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return String(format: L10n.tr("TLS Error"), host)
        case .cannotFindHost, .dnsLookupFailed:
            return String(format: L10n.tr("Host Not Found"), host)
        case .notConnectedToInternet, .dataNotAllowed:
            return L10n.tr("No Internet Connection")
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return L10n.tr("Invalid Credentials")
        case .cancelled:
            return L10n.tr("Operation Cancelled")
        default:
            return String(
                format: L10n.tr("Network Error With Code"),
                urlError.code.rawValue,
                urlString.isEmpty ? host : urlString
            )
        }
    }

    /// Перегрузка для случаев, где URL известен извне (KeeneticRCIClient).
    nonisolated static func message(for urlError: URLError, url: URL) -> String {
        let host = url.host ?? L10n.tr("Keenetic Router")
        switch urlError.code {
        case .timedOut:
            return String(format: L10n.tr("Connection Timeout"), url.absoluteString)
        case .cannotConnectToHost, .networkConnectionLost:
            return String(format: L10n.tr("No Connection To Host"), host)
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return String(format: L10n.tr("TLS Error"), host)
        case .cannotFindHost, .dnsLookupFailed:
            return String(format: L10n.tr("Host Not Found"), host)
        case .notConnectedToInternet, .dataNotAllowed:
            return L10n.tr("No Internet Connection")
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return L10n.tr("Invalid Credentials")
        case .cancelled:
            return L10n.tr("Operation Cancelled")
        default:
            return String(format: L10n.tr("Network Error With Code"), urlError.code.rawValue, url.absoluteString)
        }
    }
}
