import CryptoKit
import Foundation
import os

// MARK: - KeeneticRCIClient
//
// Низкоуровневый HTTP-клиент RCI Keenetic:
// 1) GET /auth → challenge; POST /auth с SHA256(MD5(login:realm:password)+challenge)
// 2) GET show/ip/policy, show/ip/hotspot — чтение
// 3) POST ip/hotspot/host — назначение политики; configuration/save — запись в NVRAM
//
// Несколько вариантов одной операции (fallback) — прошивки KeeneticOS отличаются.

final class KeeneticRCIClient: @unchecked Sendable {
    private nonisolated static let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "RCI")

    private let settings: RouterSettings
    private let password: String
    private let session: URLSession

    nonisolated init(settings: RouterSettings, password: String) {
        self.settings = settings
        self.password = password

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    nonisolated func testConnection() async throws -> RouterInfo {
        try await fetchRouterInfo()
    }

    nonisolated func fetchRouterInfo() async throws -> RouterInfo {
        try await authenticate()
        let (_, versionData) = try await request(path: "rci/show/version", method: "GET")
        logPreview(label: "GET show/version", data: versionData)
        guard !versionData.isEmpty else { throw KeeneticError.emptyResponse }

        var info = try RCIJSONParser.routerInfo(from: versionData)

        if let (_, systemData) = try? await request(path: "rci/show/system", method: "GET"),
           let hostname = RCIJSONParser.systemHostname(in: systemData),
           !hostname.isEmpty {
            logPreview(label: "GET show/system", data: systemData)
            info = info.withHostname(hostname)
        }

        return info
    }

    nonisolated func fetchPolicies() async throws -> [AccessPolicy] {
        try await authenticate()

        let (_, hotspotData) = try await request(path: "rci/show/ip/hotspot", method: "GET")

        var collected: [[AccessPolicy]] = []
        collected.append(contentsOf: await loadPoliciesFromGETPaths())
        collected.append(contentsOf: await loadPoliciesByProbingSlots())
        var policies = RCIJSONParser.mergePolicies(collected)

        // POST show — не на всех прошивках; не роняем обновление при 405.
        if policies.count < 2 {
            collected.append(contentsOf: await loadPoliciesFromShowPOST())
            policies = RCIJSONParser.mergePolicies(collected)
        }

        if policies.isEmpty {
            let devices = try RCIJSONParser.devices(from: hotspotData)
            policies = RCIJSONParser.policiesInferredFromDevices(devices)
            logPreview(label: "hotspot fallback", data: hotspotData)
        }

        policies = KeeneticPolicyCatalog.assignablePolicies(discovered: policies)

        guard !policies.isEmpty else {
            throw KeeneticError.apiError(L10n.tr("Policies Not Found In RCI"))
        }
        return policies
    }

    nonisolated func fetchDevices() async throws -> [NetworkDevice] {
        try await authenticate()
        let (_, data) = try await request(path: "rci/show/ip/hotspot", method: "GET")
        var devices = try RCIJSONParser.devices(from: data)

        let policyMap = await loadHostPolicyMap()
        if !policyMap.isEmpty {
            devices = RCIJSONParser.applyingHostPolicies(policyMap, to: devices)
        }

        return devices
    }

    /// Политики назначены в конфигурации, а не в live `show ip hotspot`.
    private nonisolated func loadHostPolicyMap() async -> [String: String] {
        let paths = [
            "rci/show/rc/ip/hotspot",
            "rci/ip/hotspot/host",
        ]

        for path in paths {
            do {
                let (_, data) = try await request(path: path, method: "GET")
                let map = try RCIJSONParser.hostPolicies(from: data)
                if !map.isEmpty {
                    logPreview(label: "GET \(path)", data: data)
                    return map
                }
            } catch {
                continue
            }
        }
        return [:]
    }

    nonisolated func fetchHostPolicyMap() async throws -> [String: String] {
        try await authenticate()
        return await loadHostPolicyMap()
    }

    nonisolated func setPolicy(mac: String, policyName: String, saveConfiguration: Bool) async throws {
        try await authenticate()
        let apiMAC = Self.apiMAC(mac)

        if KeeneticPolicyCatalog.isBuiltIn(policyName) {
            try await setBuiltInPolicy(apiMAC: apiMAC, policyName: policyName)
        } else {
            try await runFirstSuccessful([
                { try await self.setIPPolicyViaHostEndpoint(apiMAC: apiMAC, policyName: policyName) },
                { try await self.setPolicyViaPolicyEndpoint(apiMAC: apiMAC, policyName: policyName) },
            ], failureMessage: String(format: L10n.tr("Failed To Assign Policy"), policyName))
        }

        if saveConfiguration {
            try await persistRouterConfiguration()
        }
    }

    private nonisolated func setBuiltInPolicy(apiMAC: String, policyName: String) async throws {
        switch policyName {
        case KeeneticPolicyCatalog.builtInPermit:
            try await clearHostIPPolicy(apiMAC: apiMAC)
            try await setHostAccess(apiMAC: apiMAC, access: "permit")
        case KeeneticPolicyCatalog.builtInDeny:
            try await clearHostIPPolicy(apiMAC: apiMAC)
            try await setHostAccess(apiMAC: apiMAC, access: "deny")
        case KeeneticPolicyCatalog.builtInSegment:
            try await clearHostIPPolicy(apiMAC: apiMAC)
        default:
            throw KeeneticError.apiError(String(format: L10n.tr("Unknown Policy Mode"), policyName))
        }
    }

    private nonisolated func setHostAccess(apiMAC: String, access: String) async throws {
        let body: [String: Any] = [
            "mac": apiMAC,
            "access": access,
        ]
        let (_, data) = try await request(path: "rci/ip/hotspot/host", method: "POST", json: body)
        try RCIJSONParser.validateCommandResponse(data)
    }

    private nonisolated func clearHostIPPolicy(apiMAC: String) async throws {
        let body: [String: Any] = [
            "mac": apiMAC,
            "no": true,
        ]
        let (_, data) = try await request(path: "rci/ip/hotspot/host/policy", method: "POST", json: body)
        try RCIJSONParser.validateCommandResponse(data)
    }

    private nonisolated func runFirstSuccessful(
        _ operations: [() async throws -> Void],
        failureMessage: String
    ) async throws {
        var lastError: Error = KeeneticError.apiError(failureMessage)
        for operation in operations {
            do {
                try await operation()
                return
            } catch {
                lastError = error
                logPreview(label: "RCI attempt failed", data: Data(error.localizedDescription.utf8))
            }
        }
        throw lastError
    }

    private nonisolated func setIPPolicyViaHostEndpoint(apiMAC: String, policyName: String) async throws {
        let body: [String: Any] = [
            "mac": apiMAC,
            "permit": true,
            "policy": policyName,
        ]
        let (_, data) = try await request(path: "rci/ip/hotspot/host", method: "POST", json: body)
        try RCIJSONParser.validateCommandResponse(data)
    }

    private nonisolated func setPolicyViaPolicyEndpoint(apiMAC: String, policyName: String) async throws {
        let body: [String: Any] = [
            "mac": apiMAC,
            "policy": policyName,
        ]
        let (_, data) = try await request(path: "rci/ip/hotspot/host/policy", method: "POST", json: body)
        try RCIJSONParser.validateCommandResponse(data)
    }

    private nonisolated func persistRouterConfiguration() async throws {
        let (_, data) = try await request(path: "rci/system/configuration/save", method: "POST", json: [:] as [String: Any])
        try RCIJSONParser.validateCommandResponse(data)
    }

    private nonisolated static func apiMAC(_ mac: String) -> String {
        mac.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Загрузка политик

    /// Live-состояние и сохранённая конфигурация (как в веб-интерфейсе «Применение политик»).
    /// Сначала сохранённая конфигурация (`show rc ip policy` в telnet).
    private nonisolated static let policyGETPaths = [
        "rci/show/rc/ip/policy",
        "rci/show/ip/policy",
    ]

    private nonisolated func loadPoliciesFromGETPaths() async -> [[AccessPolicy]] {
        var lists: [[AccessPolicy]] = []
        for path in Self.policyGETPaths {
            do {
                let (_, data) = try await request(path: path, method: "GET")
                logPreview(label: "GET \(path)", data: data)
                let policies = try RCIJSONParser.policies(from: data)
                if !policies.isEmpty {
                    lists.append(policies)
                }
            } catch {
                Self.logger.debug("GET \(path, privacy: .public) policies: \(error.localizedDescription, privacy: .public)")
            }
        }
        return lists
    }

    /// На части прошивок в общем `show ip policy` видна только активная PolicyN.
    private nonisolated func loadPoliciesByProbingSlots() async -> [[AccessPolicy]] {
        var lists: [[AccessPolicy]] = []
        for index in KeeneticPolicyCatalog.policySlotRange {
            let name = KeeneticPolicyCatalog.policySlotName(index)
            let path = "rci/show/ip/policy/\(name)"
            do {
                let (_, data) = try await request(path: path, method: "GET")
                let policies = try RCIJSONParser.policies(from: data)
                if !policies.isEmpty {
                    lists.append(policies)
                    logPreview(label: "GET \(path)", data: data)
                }
            } catch {
                Self.logger.debug("GET \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return lists
    }

    private nonisolated func loadPoliciesFromShowPOST() async -> [[AccessPolicy]] {
        let batches: [[[String: Any]]] = [
            [["show": ["ip": ["policy": [:] as [String: Any]] as [String: Any]] as [String: Any]]],
            [["show": ["rc": ["ip": ["policy": [:] as [String: Any]] as [String: Any]] as [String: Any]] as [String: Any]]],
        ]

        var lists: [[AccessPolicy]] = []
        for (index, batch) in batches.enumerated() {
            let label = index == 0 ? "POST show ip policy" : "POST show rc ip policy"
            do {
                let (_, data) = try await request(path: "rci", method: "POST", jsonArray: batch)
                logPreview(label: label, data: data)

                var policies = try RCIJSONParser.policies(from: data)
                if policies.isEmpty {
                    policies = try policiesFromBatchFirstElement(data)
                }
                if !policies.isEmpty {
                    lists.append(policies)
                }
            } catch {
                Self.logger.debug("\(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return lists
    }

    private nonisolated func policiesFromBatchFirstElement(_ data: Data) throws -> [AccessPolicy] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let first = array.first else { return [] }
        let wrapped = try JSONSerialization.data(withJSONObject: first)
        return try RCIJSONParser.policies(from: wrapped)
    }

    // MARK: - Аутентификация

    private nonisolated func authenticate() async throws {
        let (status, _, headers) = try await rawRequest(path: "auth", method: "GET")
        if status == 200 { return }

        guard status == 401 else {
            throw KeeneticError.httpError(status: status, message: L10n.tr("Unexpected Auth Response"))
        }

        guard let challenge = header("X-NDM-Challenge", in: headers), !challenge.isEmpty,
              let realm = header("X-NDM-Realm", in: headers), !realm.isEmpty else {
            throw KeeneticError.authenticationFailed
        }

        let hashed = Self.hashPassword(
            login: settings.username,
            realm: realm,
            password: password,
            challenge: challenge
        )

        let (postStatus, _) = try await request(
            path: "auth",
            method: "POST",
            json: ["login": settings.username, "password": hashed]
        )

        guard (200...299).contains(postStatus) else {
            throw KeeneticError.authenticationFailed
        }
    }

    nonisolated static func hashPassword(login: String, realm: String, password: String, challenge: String) -> String {
        let md5Input = "\(login):\(realm):\(password)"
        let md5 = Insecure.MD5.hash(data: Data(md5Input.utf8))
        let md5Hex = md5.map { String(format: "%02x", $0) }.joined()
        let shaInput = challenge + md5Hex
        let sha = SHA256.hash(data: Data(shaInput.utf8))
        return sha.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - HTTP-запросы

    private nonisolated func request(
        path: String,
        method: String,
        json: [String: Any]? = nil,
        jsonArray: [[String: Any]]? = nil
    ) async throws -> (Int, Data) {
        let (status, data, _) = try await rawRequest(path: path, method: method, json: json, jsonArray: jsonArray)
        guard (200...299).contains(status) else {
            let message = RCIJSONParser.apiErrorMessage(in: data)
                ?? String(data: data, encoding: .utf8)
                ?? L10n.tr("Request Error")
            throw KeeneticError.httpError(status: status, message: message)
        }
        return (status, data)
    }

    private nonisolated func rawRequest(
        path: String,
        method: String,
        json: [String: Any]? = nil,
        jsonArray: [[String: Any]]? = nil
    ) async throws -> (Int, Data, [String: String]) {
        guard let url = makeURL(path: path) else { throw KeeneticError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let jsonArray {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonArray)
        } else if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if method == "POST" {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw KeeneticError.connectionFailed(Self.describe(urlError: error, url: url))
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let headers = http?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        } ?? [:]

        return (status, data, headers)
    }

    private nonisolated static func describe(urlError: URLError, url: URL) -> String {
        // Общая таблица переводов URLError — см. URLErrorLocalization.
        URLErrorLocalization.message(for: urlError, url: url)
    }

    private nonisolated func makeURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = settings.useHTTPS ? "https" : "http"
        components.host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)

        let defaultPort = settings.useHTTPS ? 443 : 80
        if settings.port != defaultPort {
            components.port = settings.port
        }

        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.path = "/" + cleanPath
        return components.url
    }

    private nonisolated func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private nonisolated func logPreview(label: String, data: Data) {
        let text = String(data: data, encoding: .utf8) ?? "<binary>"
        Self.logger.debug("[\(label)] \(text.prefix(800), privacy: .public)")
    }
}
