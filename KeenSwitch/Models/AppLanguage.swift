import Foundation

/// Выбор языка интерфейса в настройках.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case russian
    case english

    var id: String { rawValue }

    var languageCode: String? {
        switch self {
        case .automatic: nil
        case .russian: "ru"
        case .english: "en"
        }
    }

    init(languageCode: String?) {
        switch languageCode {
        case "ru": self = .russian
        case "en": self = .english
        default: self = .automatic
        }
    }

    @MainActor
    var pickerTitle: String {
        switch self {
        case .automatic: L10n.tr("Language Automatic")
        case .russian: L10n.tr("Language Russian")
        case .english: L10n.tr("Language English")
        }
    }
}
