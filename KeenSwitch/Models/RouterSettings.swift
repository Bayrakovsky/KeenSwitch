import Foundation

/// Параметры HTTP-подключения к роутеру (RCI).
struct RouterSettings: Codable, Sendable, Equatable {
    var host: String
    var port: Int
    var useHTTPS: Bool
    var username: String
    var saveConfigurationAfterChange: Bool

    enum CodingKeys: String, CodingKey {
        case host, port, useHTTPS, username, saveConfigurationAfterChange
    }

    init(
        host: String,
        port: Int,
        useHTTPS: Bool,
        username: String,
        saveConfigurationAfterChange: Bool
    ) {
        self.host = host
        self.port = port
        self.useHTTPS = useHTTPS
        self.username = username
        self.saveConfigurationAfterChange = saveConfigurationAfterChange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        useHTTPS = try container.decodeIfPresent(Bool.self, forKey: .useHTTPS) ?? false
        username = try container.decode(String.self, forKey: .username)
        saveConfigurationAfterChange = try container.decodeIfPresent(
            Bool.self,
            forKey: .saveConfigurationAfterChange
        ) ?? true
    }

    static let httpPort = 80
    static let httpsPort = 443

    static let `default` = RouterSettings(
        host: "192.168.1.1",
        port: httpPort,
        useHTTPS: false,
        username: "admin",
        saveConfigurationAfterChange: true
    )

    /// Порт отличается от стандартных 80/443 — переключатель HTTP/HTTPS не подставляет порт автоматически.
    var hasCustomPort: Bool {
        port != Self.httpPort && port != Self.httpsPort
    }

    /// Старые сохранённые настройки могли указывать порт 23 — заменяем на HTTP (80).
    mutating func migrateLegacyPortIfNeeded() {
        if port == 23 { port = Self.httpPort }
    }
}
