import Foundation

// MARK: - Модели данных с роутера

/// IP-политика маршрутизации на Keenetic (Policy0, Policy1, …).
nonisolated struct AccessPolicy: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let description: String?
    /// Основной интерфейс маршрута по умолчанию (OpenVPN0, Home, …).
    let routingInterface: String?

    nonisolated var displayTitle: String {
        if let description, !description.isEmpty {
            return description
        }
        return name
    }

    /// Заголовок с учётом локализации встроенных режимов Keenetic.
    nonisolated var localizedDisplayTitle: String {
        KeeneticPolicyCatalog.localizedTitle(for: name) ?? displayTitle
    }

    nonisolated var displaySubtitle: String {
        if let description, !description.isEmpty {
            return name
        }
        return ""
    }
}

nonisolated struct NetworkDevice: Identifiable, Hashable, Sendable {
    var id: String { mac }
    let mac: String
    let name: String?
    let ip: String?
    let interfaceName: String?
    /// Устройство сейчас в сети (поле `active` в RCI hotspot).
    let isOnline: Bool
    var currentPolicy: String?

    nonisolated var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return L10n.tr("Device")
    }

    var hasAssignedPolicy: Bool {
        guard let currentPolicy, !currentPolicy.isEmpty else { return false }
        return true
    }
}

nonisolated extension NetworkDevice {
    /// Сначала закреплённые (в порядке закрепления), затем в сети, затем остальные; внутри группы — по имени.
    nonisolated static func sortedForDisplay(_ devices: [NetworkDevice], pinnedMACs: [String] = []) -> [NetworkDevice] {
        guard !pinnedMACs.isEmpty else {
            return sortedByReachability(devices)
        }

        let pinnedSet = Set(pinnedMACs)
        let byMAC = Dictionary(uniqueKeysWithValues: devices.map { ($0.mac, $0) })
        var result: [NetworkDevice] = pinnedMACs.compactMap { byMAC[$0] }
        let unpinned = devices.filter { !pinnedSet.contains($0.mac) }
        result.append(contentsOf: sortedByReachability(unpinned))
        return result
    }

    private nonisolated static func sortedByReachability(_ devices: [NetworkDevice]) -> [NetworkDevice] {
        devices.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline {
                return lhs.isOnline && !rhs.isOnline
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    func routingSummary(policies: [AccessPolicy]) -> String {
        let iface = interfaceName ?? "—"
        guard hasAssignedPolicy, let policyName = currentPolicy else {
            return L10n.tr("Default Segment Policy") + " · \(iface)"
        }
        if let policy = policies.first(where: { $0.name == policyName }) {
            if let route = policy.routingInterface {
                return "\(policy.localizedDisplayTitle) · \(route)"
            }
            return "\(policy.localizedDisplayTitle) · \(iface)"
        }
        return "\(policyName) · \(iface)"
    }
}

/// Состояние последней попытки связи с роутером (для UI настроек и статуса).
nonisolated enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
