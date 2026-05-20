import Foundation

// MARK: - RCIJSONParser
//
// Разбор JSON-ответов HTTP API Keenetic (RCI).
// Роутер отдаёт вложенные деревья (show → ip → policy/host); парсер обходит их
// и собирает модели AccessPolicy и NetworkDevice для UI.

enum RCIJSONParser {
    /// Разбирает список политик маршрутизации из ответа RCI.
    nonisolated static func policies(from data: Data) throws -> [AccessPolicy] {
        let json = try JSONSerialization.jsonObject(with: data)
        return mergePolicies(extractPolicies(from: json))
    }

    /// Объединяет списки политик с разных RCI-эндпоинтов (live show и сохранённый rc).
    nonisolated static func mergePolicies(_ lists: [[AccessPolicy]]) -> [AccessPolicy] {
        mergePolicies(lists.flatMap { $0 })
    }

    /// Дедублицирует политики по имени, объединяя поля description и routingInterface.
    nonisolated static func mergePolicies(_ policies: [AccessPolicy]) -> [AccessPolicy] {
        var byName: [String: AccessPolicy] = [:]
        for policy in policies {
            if let existing = byName[policy.name] {
                byName[policy.name] = AccessPolicy(
                    name: policy.name,
                    description: policy.description ?? existing.description,
                    routingInterface: policy.routingInterface ?? existing.routingInterface
                )
            } else {
                byName[policy.name] = policy
            }
        }
        return byName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Выводит имена политик из поля currentPolicy устройств — резерв, если API политик недоступен.
    nonisolated static func policiesInferredFromDevices(_ devices: [NetworkDevice]) -> [AccessPolicy] {
        let names = devices.compactMap(\.currentPolicy).filter { !$0.isEmpty }
        return Array(Set(names))
            .sorted()
            .map { AccessPolicy(name: $0, description: nil, routingInterface: nil) }
    }

    /// Разбирает список устройств из ответа `show/ip/hotspot` и дедублицирует по MAC.
    nonisolated static func devices(from data: Data) throws -> [NetworkDevice] {
        let json = try JSONSerialization.jsonObject(with: data)
        let devices = deduplicateHosts(extractHosts(from: json))
        return NetworkDevice.sortedForDisplay(devices)
    }

    /// Разбирает информацию о роутере из ответа `show/version`.
    nonisolated static func routerInfo(from data: Data) throws -> RouterInfo {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let version = findVersionNode(in: json) else {
            throw KeeneticError.apiError(L10n.tr("Failed To Read Version Data"))
        }
        return routerInfo(fromVersion: version)
    }

    /// Извлекает hostname роутера из ответа `show/system` (дополнение к show/version).
    nonisolated static func systemHostname(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let system = findSystemNode(in: json), let hostname = stringValue(system["hostname"]) {
            return hostname
        }
        return nil
    }

    /// Назначенные политики из конфигурации (`show/rc/ip/hotspot`, `ip/hotspot/host`).
    nonisolated static func hostPolicies(from data: Data) throws -> [String: String] {
        let json = try JSONSerialization.jsonObject(with: data)
        return extractHostPolicyMap(from: json)
    }

    /// Подставляет политики из конфигурации роутера; без записи в конфиге — `nil`.
    nonisolated static func applyingHostPolicies(_ policies: [String: String], to devices: [NetworkDevice]) -> [NetworkDevice] {
        devices.map { device in
            var updated = device
            updated.currentPolicy = policies[device.mac]
            return updated
        }
    }

    /// Проверяет ответ RCI после команды изменения настроек.
    nonisolated static func validateCommandResponse(_ data: Data) throws {
        for entry in statusEntries(in: data) {
            if entry.isError {
                throw KeeneticError.apiError(entry.message)
            }
        }
    }

    /// Первое не-ошибочное сообщение из RCI-ответа (для отображения статуса в UI).
    nonisolated static func commandStatusMessage(in data: Data) -> String? {
        statusEntries(in: data).first { !$0.isError }?.message
    }

    private nonisolated static func statusEntries(in data: Data) -> [StatusEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return collectStatusEntries(from: json)
    }

    private struct StatusEntry {
        let isError: Bool
        let message: String
    }

    private nonisolated static func collectStatusEntries(from node: Any) -> [StatusEntry] {
        var results: [StatusEntry] = []

        func visit(_ node: Any) {
            if let array = node as? [Any] {
                for item in array { visit(item) }
                return
            }
            guard let dict = node as? [String: Any] else { return }

            if let statusKind = stringValue(dict["status"]),
               let message = stringValue(dict["message"]) {
                let lowered = statusKind.lowercased()
                let isError = lowered == "error"
                    || lowered == "failed"
                    || lowered == "warning" && message.localizedCaseInsensitiveContains("error")
                results.append(StatusEntry(isError: isError, message: message))
            }

            for (_, value) in dict {
                visit(value)
            }
        }

        visit(node)
        return results
    }

    private nonisolated static func deduplicateHosts(_ hosts: [NetworkDevice]) -> [NetworkDevice] {
        var byMAC: [String: NetworkDevice] = [:]
        for host in hosts {
            if let existing = byMAC[host.mac] {
                byMAC[host.mac] = mergeHosts(existing, host)
            } else {
                byMAC[host.mac] = host
            }
        }
        return Array(byMAC.values)
    }

    private nonisolated static func mergeHosts(_ lhs: NetworkDevice, _ rhs: NetworkDevice) -> NetworkDevice {
        NetworkDevice(
            mac: lhs.mac,
            name: preferred(lhs.name, rhs.name),
            ip: preferred(lhs.ip, rhs.ip),
            interfaceName: preferred(lhs.interfaceName, rhs.interfaceName),
            isOnline: lhs.isOnline || rhs.isOnline,
            currentPolicy: preferred(lhs.currentPolicy, rhs.currentPolicy)
        )
    }

    private nonisolated static func preferred(_ lhs: String?, _ rhs: String?) -> String? {
        if let lhs, !lhs.isEmpty { return lhs }
        if let rhs, !rhs.isEmpty { return rhs }
        return nil
    }

    /// Сообщение об ошибке RCI для показа пользователю; nil если ответ успешный.
    nonisolated static func apiErrorMessage(in data: Data) -> String? {
        if let error = statusEntries(in: data).first(where: \.isError) {
            return error.message
        }
        return commandStatusMessage(in: data)
    }

    // MARK: - Извлечение политик

    private nonisolated static func extractPolicies(from json: Any) -> [AccessPolicy] {
        var results: [AccessPolicy] = []

        func visit(_ node: Any) {
            if let array = node as? [Any] {
                for item in array { visit(item) }
                return
            }

            guard let dict = node as? [String: Any] else { return }

            // show → (rc →) ip → policy
            if let show = dict["show"] { visit(show) }
            if let rc = dict["rc"] as? [String: Any] {
                if let ip = rc["ip"] as? [String: Any] {
                    results.append(contentsOf: policiesFromIPNode(ip))
                }
                visit(rc)
            }

            if let ip = dict["ip"] as? [String: Any] {
                results.append(contentsOf: policiesFromIPNode(ip))
            }

            results.append(contentsOf: policiesFromIPNode(dict))

            for (key, value) in dict {
                guard isPolicyTableKey(key), let object = value as? [String: Any] else { continue }
                if let policy = policyFromDictionary(object, fallbackName: key) {
                    results.append(policy)
                }
            }

            // Обход остальных веток (кроме маршрутов и уже разобранных PolicyN)
            for (key, value) in dict where !isRouteKey(key) && key != "show" && key != "ip" {
                if isPolicyTableKey(key) { continue }
                visit(value)
            }
        }

        visit(json)
        return results
    }

    private nonisolated static func policiesFromIPNode(_ dict: [String: Any]) -> [AccessPolicy] {
        var results: [AccessPolicy] = []
        guard let policyNode = dict["policy"] else { return results }

        if let array = policyNode as? [[String: Any]] {
            let fromConfig = policiesFromRcConfigSections(array)
            if !fromConfig.isEmpty {
                results.append(contentsOf: fromConfig)
            } else {
                for item in array {
                    if let policy = policyFromDictionary(item) {
                        results.append(policy)
                    }
                }
            }
        } else if let array = policyNode as? [Any] {
            let dicts = array.compactMap { $0 as? [String: Any] }
            let fromConfig = policiesFromRcConfigSections(dicts)
            if !fromConfig.isEmpty {
                results.append(contentsOf: fromConfig)
            } else {
                for item in dicts {
                    if let policy = policyFromDictionary(item) {
                        results.append(policy)
                    }
                }
            }
        } else if let keyed = policyNode as? [String: Any] {
            // policy: { Policy0: { description: ... }, Policy1: ..., route: [...] }
            var foundKeyed = false
            for (name, raw) in keyed where isPolicyTableKey(name) {
                guard let object = raw as? [String: Any],
                      let policy = policyFromDictionary(object, fallbackName: name) else { continue }
                results.append(policy)
                foundKeyed = true
            }
            if !foundKeyed, let policy = policyFromDictionary(keyed) {
                results.append(policy)
            }
        }

        return results
    }

    /// `show rc ip policy` — последовательность config-блоков: policy → description → permit.
    private nonisolated static func policiesFromRcConfigSections(_ sections: [[String: Any]]) -> [AccessPolicy] {
        var policies: [AccessPolicy] = []
        var currentName: String?
        var currentDescription: String?
        var currentInterface: String?

        func flush() {
            guard let name = currentName, isPolicyTableKey(name) else { return }
            policies.append(
                AccessPolicy(
                    name: name,
                    description: currentDescription,
                    routingInterface: currentInterface
                )
            )
            currentName = nil
            currentDescription = nil
            currentInterface = nil
        }

        for section in sections {
            if let policyObj = section["policy"] as? [String: Any],
               let name = stringValue(policyObj["name"]),
               isPolicyTableKey(name) {
                flush()
                currentName = name
                continue
            }

            if let configName = stringValue(section["name"])?.lowercased() {
                switch configName {
                case "policy":
                    flush()
                    if let policyObj = section["policy"] as? [String: Any],
                       let name = stringValue(policyObj["name"]),
                       isPolicyTableKey(name) {
                        currentName = name
                    }
                    continue
                case "description":
                    if let description = stringValue(section["description"]) {
                        currentDescription = description
                    }
                    continue
                case "permit":
                    if let iface = primaryInterfaceFromPermit(section), currentInterface == nil {
                        currentInterface = iface
                    }
                    continue
                default:
                    break
                }
            }

            if let description = stringValue(section["description"]), currentName != nil {
                currentDescription = description
            }

            if let iface = primaryInterfaceFromPermit(section) {
                if currentInterface == nil || isPermitEnabled(section) {
                    currentInterface = iface
                }
            }

            for (key, raw) in section where isPolicyTableKey(key) {
                flush()
                currentName = key
                if let object = raw as? [String: Any] {
                    if let description = stringValue(object["description"]) {
                        currentDescription = description
                    }
                    if currentInterface == nil {
                        currentInterface = primaryRoutingInterface(from: object)
                    }
                }
            }
        }

        flush()
        return policies
    }

    /// Один элемент policy из CLI: `policy, name = Policy0, description = …`
    private nonisolated static func policyFromDictionary(_ dict: [String: Any], fallbackName: String? = nil) -> AccessPolicy? {
        var name = stringValue(dict["name"]) ?? stringValue(dict["id"]) ?? fallbackName

        // В RCI имя иногда лежит в ключе `policy` как строка "Policy0"
        if name == nil, let policyField = dict["policy"] {
            if let policyName = policyField as? String {
                name = policyName
            } else if let nested = policyField as? [String: Any] {
                name = stringValue(nested["name"]) ?? stringValue(nested["id"])
                let description = stringValue(dict["description"]) ?? stringValue(nested["description"])
                if let name, !name.isEmpty {
                    return AccessPolicy(
                        name: name,
                        description: description,
                        routingInterface: primaryRoutingInterface(from: dict)
                    )
                }
            }
        }

        guard let name, !name.isEmpty, isPolicyTableKey(name) else { return nil }
        return AccessPolicy(
            name: name,
            description: stringValue(dict["description"]),
            routingInterface: primaryRoutingInterface(from: dict)
        )
    }

    private nonisolated static func primaryRoutingInterface(from dict: [String: Any]) -> String? {
        for key in ["route4", "route", "route6"] {
            if let iface = interfaceFromRoutes(dict[key]) {
                return iface
            }
        }
        return primaryInterfaceFromPermit(dict)
    }

    private nonisolated static func primaryInterfaceFromPermit(_ dict: [String: Any]) -> String? {
        for permit in permitDictionaries(in: dict) {
            guard isPermitEnabled(permit),
                  let iface = stringValue(permit["interface"]),
                  !iface.isEmpty else { continue }
            return iface
        }
        return nil
    }

    private nonisolated static func permitDictionaries(in dict: [String: Any]) -> [[String: Any]] {
        switch dict["permit"] {
        case let permit as [String: Any]:
            return [permit]
        case let array as [[String: Any]]:
            return array
        case let array as [Any]:
            return array.compactMap { $0 as? [String: Any] }
        default:
            return isPermitSection(dict) ? [dict] : []
        }
    }

    private nonisolated static func isPermitSection(_ dict: [String: Any]) -> Bool {
        stringValue(dict["name"])?.lowercased() == "permit"
            || dict["interface"] != nil
            || dict["enabled"] != nil
    }

    private nonisolated static func isPermitEnabled(_ dict: [String: Any]) -> Bool {
        if boolValue(dict["no"]) == true { return false }
        if let enabled = boolValue(dict["enabled"]) { return enabled }
        return true
    }

    private nonisolated static func interfaceFromRoutes(_ node: Any?) -> String? {
        guard let node else { return nil }

        var routes: [[String: Any]] = []
        if let array = node as? [[String: Any]] {
            routes = array
        } else if let dict = node as? [String: Any] {
            if let nested = dict["route"] as? [[String: Any]] {
                routes = nested
            } else if let single = dict["route"] as? [String: Any] {
                routes = [single]
            } else if let nested6 = dict["route6"] as? [[String: Any]] {
                routes = nested6
            } else if let single6 = dict["route6"] as? [String: Any] {
                routes = [single6]
            }
        }

        for route in routes {
            let destination = stringValue(route["destination"]) ?? ""
            if destination.hasPrefix("0.0.0.0") || destination.isEmpty,
               let iface = stringValue(route["interface"]), !iface.isEmpty {
                return iface
            }
        }

        if let first = routes.first, let iface = stringValue(first["interface"]) {
            return iface
        }
        return nil
    }

    /// Имя таблицы политик Keenetic: Policy0, Policy1, …
    private nonisolated static func isPolicyTableKey(_ name: String) -> Bool {
        name.range(of: #"^Policy\d+$"#, options: .regularExpression) != nil
    }

    private nonisolated static func isRouteKey(_ key: String) -> Bool {
        key == "route" || key == "route4" || key == "route6" || key.hasPrefix("route")
    }

    // MARK: - Извлечение устройств

    private nonisolated static func extractHosts(from json: Any) -> [NetworkDevice] {
        var results: [NetworkDevice] = []

        func visit(_ node: Any) {
            if let array = node as? [Any] {
                for item in array { visit(item) }
                return
            }
            guard let dict = node as? [String: Any] else { return }

            if let show = dict["show"] { visit(show) }

            if let ip = dict["ip"] as? [String: Any] {
                results.append(contentsOf: hostsFromNode(ip))
            }
            results.append(contentsOf: hostsFromNode(dict))

            for (key, value) in dict where key != "show" && key != "ip" {
                visit(value)
            }
        }

        visit(json)
        return results
    }

    private nonisolated static func hostsFromNode(_ dict: [String: Any]) -> [NetworkDevice] {
        var results: [NetworkDevice] = []

        let hostNode = dict["host"] ?? (dict["hotspot"] as? [String: Any])?["host"]
        guard let hostNode else { return results }

        if let array = hostNode as? [[String: Any]] {
            for item in array {
                if let device = hostFromDictionary(item) { results.append(device) }
            }
        } else if let array = hostNode as? [Any] {
            for case let item as [String: Any] in array {
                if let device = hostFromDictionary(item) { results.append(device) }
            }
        } else if let keyed = hostNode as? [String: Any] {
            if keyed.values.allSatisfy({ $0 is [String: Any] }) {
                for (mac, raw) in keyed {
                    guard let object = raw as? [String: Any],
                          let device = hostFromDictionary(object, fallbackMAC: mac) else { continue }
                    results.append(device)
                }
            } else if let device = hostFromDictionary(keyed) {
                results.append(device)
            }
        }

        return results
    }

    private nonisolated static func extractHostPolicyMap(from json: Any) -> [String: String] {
        var map: [String: String] = [:]

        func ingest(_ dict: [String: Any], fallbackMAC: String? = nil) {
            guard let mac = (stringValue(dict["mac"]) ?? fallbackMAC)?.uppercased(),
                  mac.contains(":"),
                  let policy = hostPolicyName(from: dict) else { return }
            map[mac] = policy
        }

        func visit(_ node: Any) {
            if let array = node as? [Any] {
                for item in array { visit(item) }
                return
            }
            guard let dict = node as? [String: Any] else { return }

            for (hostDict, fallbackMAC) in rawHostDictionaries(in: dict) {
                ingest(hostDict, fallbackMAC: fallbackMAC)
            }

            for (key, value) in dict where key != "host" {
                visit(value)
            }
        }

        visit(json)
        return map
    }

    private nonisolated static func rawHostDictionaries(
        in dict: [String: Any]
    ) -> [([String: Any], String?)] {
        let hostNode = dict["host"] ?? (dict["hotspot"] as? [String: Any])?["host"]
        guard let hostNode else { return [] }

        var results: [([String: Any], String?)] = []

        if let array = hostNode as? [[String: Any]] {
            results.append(contentsOf: array.map { ($0, nil) })
        } else if let array = hostNode as? [Any] {
            for case let item as [String: Any] in array {
                results.append((item, nil))
            }
        } else if let keyed = hostNode as? [String: Any] {
            if keyed.values.allSatisfy({ $0 is [String: Any] }) {
                for (mac, raw) in keyed {
                    if let object = raw as? [String: Any] {
                        results.append((object, mac))
                    }
                }
            } else {
                results.append((keyed, nil))
            }
        }

        return results
    }

    /// Назначенная политика устройства: PolicyN, permit, deny.
    private nonisolated static func hostPolicyName(from dict: [String: Any]) -> String? {
        if let policyField = dict["policy"],
           let name = parseAssignedPolicyName(policyField) {
            return name
        }
        if let access = stringValue(dict["access"])?.lowercased() {
            if access == KeeneticPolicyCatalog.builtInPermit || access == KeeneticPolicyCatalog.builtInDeny {
                return access
            }
        }
        if let permit = boolValue(dict["permit"]) {
            return permit ? KeeneticPolicyCatalog.builtInPermit : KeeneticPolicyCatalog.builtInDeny
        }
        return nil
    }

    private nonisolated static func parseAssignedPolicyName(_ value: Any?) -> String? {
        switch value {
        case let name as String:
            return isIPPolicyName(name) ? name : nil
        case let dict as [String: Any]:
            if let nested = stringValue(dict["name"]) ?? stringValue(dict["policy"]),
               isIPPolicyName(nested) {
                return nested
            }
            if let keyedName = dict.keys.first(where: isIPPolicyName) {
                return keyedName
            }
            return nil
        default:
            return nil
        }
    }

    private nonisolated static func isIPPolicyName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered == "permit" || lowered == "deny" { return false }
        return isPolicyTableKey(name)
    }

    private nonisolated static func hostFromDictionary(_ dict: [String: Any], fallbackMAC: String? = nil) -> NetworkDevice? {
        let mac = (stringValue(dict["mac"]) ?? fallbackMAC)?.uppercased()
        guard let mac, mac.contains(":") else { return nil }

        let interface = dict["interface"] as? [String: Any]
        return NetworkDevice(
            mac: mac,
            name: stringValue(dict["name"]) ?? stringValue(dict["hostname"]),
            ip: stringValue(dict["ip"]),
            interfaceName: interface.flatMap { stringValue($0["name"]) },
            isOnline: boolValue(dict["active"]) ?? false,
            currentPolicy: hostPolicyName(from: dict)
        )
    }

    private nonisolated static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "yes", "true", "1", "on", "up":
                return true
            case "no", "false", "0", "off", "down":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private nonisolated static func routerInfo(fromVersion version: [String: Any]) -> RouterInfo {
        let model = stringValue(version["device"])
            ?? stringValue(version["model"])
            ?? "Keenetic"
        return RouterInfo(
            hostname: nil,
            model: model,
            hardwareID: stringValue(version["hw_id"]),
            firmwareRelease: stringValue(version["release"]),
            firmwareTitle: stringValue(version["title"]),
            vendor: stringValue(version["vendor"]) ?? stringValue(version["manufacturer"]),
            description: stringValue(version["description"])
        )
    }

    private nonisolated static func findVersionNode(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if dict["device"] != nil || dict["release"] != nil {
                return dict
            }
            if let version = dict["version"] as? [String: Any] {
                return version
            }
            if let show = dict["show"] as? [String: Any],
               let version = show["version"] as? [String: Any] {
                return version
            }
            for value in dict.values {
                if let found = findVersionNode(in: value) {
                    return found
                }
            }
        } else if let array = json as? [Any] {
            for item in array {
                if let found = findVersionNode(in: item) {
                    return found
                }
            }
        }
        return nil
    }

    private nonisolated static func findSystemNode(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if dict["hostname"] != nil {
                return dict
            }
            if let system = dict["system"] as? [String: Any] {
                return system
            }
            if let show = dict["show"] as? [String: Any],
               let system = show["system"] as? [String: Any] {
                return system
            }
            for value in dict.values {
                if let found = findSystemNode(in: value) {
                    return found
                }
            }
        } else if let array = json as? [Any] {
            for item in array {
                if let found = findSystemNode(in: item) {
                    return found
                }
            }
        }
        return nil
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
