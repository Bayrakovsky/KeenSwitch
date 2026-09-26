import Foundation

// MARK: - Информация о роутере (RCI show version / show system)

nonisolated struct RouterInfo: Equatable, Sendable {
    /// Имя из `show system hostname`, если задано.
    let hostname: String?
    /// Маркетинговое имя модели (`device` в show version).
    let model: String
    let hardwareID: String?
    let firmwareRelease: String?
    let firmwareTitle: String?
    let vendor: String?
    let description: String?

    /// Заголовок в настройках: hostname → description → модель.
    var displayName: String {
        if let hostname, !hostname.isEmpty { return hostname }
        if let description, !description.isEmpty { return description }
        return model
    }

    /// Вторая строка: модель и артикул (KN-xxxx).
    var modelLine: String {
        if let hardwareID, !hardwareID.isEmpty, hardwareID != model {
            return "\(model) · \(hardwareID)"
        }
        return model
    }

    var firmwareLine: String? {
        if let firmwareRelease, !firmwareRelease.isEmpty {
            if let firmwareTitle, !firmwareTitle.isEmpty, firmwareTitle != firmwareRelease {
                return "\(firmwareTitle) (\(firmwareRelease))"
            }
            return firmwareRelease
        }
        if let firmwareTitle, !firmwareTitle.isEmpty { return firmwareTitle }
        return nil
    }

    func withHostname(_ hostname: String?) -> RouterInfo {
        RouterInfo(
            hostname: hostname,
            model: model,
            hardwareID: hardwareID,
            firmwareRelease: firmwareRelease,
            firmwareTitle: firmwareTitle,
            vendor: vendor,
            description: description
        )
    }
}
