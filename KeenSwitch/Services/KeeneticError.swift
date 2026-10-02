import Foundation

/// Ошибки при работе с роутером через RCI (HTTP).
nonisolated enum KeeneticError: LocalizedError {
    case notConfigured
    case invalidURL
    case authenticationFailed
    case httpError(status: Int, message: String)
    case emptyResponse
    case apiError(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.tr("Configure Router First")
        case .invalidURL:
            return L10n.tr("Invalid Router Address")
        case .authenticationFailed:
            return L10n.tr("Invalid Credentials")
        case .httpError(let status, let message):
            return "HTTP \(status): \(message)"
        case .emptyResponse:
            return L10n.tr("Empty Router Response")
        case .apiError(let message):
            return message
        case .connectionFailed(let message):
            return message
        }
    }
}
