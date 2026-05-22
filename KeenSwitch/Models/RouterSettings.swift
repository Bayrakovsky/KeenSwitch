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

    /// Приводит поле «адрес роутера» к чистому host'у. Пользователи часто вставляют адрес
    /// прямо из браузера: «http://192.168.1.1», «192.168.1.1/», «192.168.1.1:8080», «[::1]».
    /// Без нормализации такой ввод ломает URLComponents → invalidURL.
    ///
    /// Что делает:
    ///   • снимает схему http:// / https:// (и выставляет useHTTPS по ней);
    ///   • отбрасывает путь, query и хвостовой «/»;
    ///   • вытаскивает встроенный «:порт» в поле port;
    ///   • нормализует порт: ≤0 → порт по умолчанию для текущей схемы.
    mutating func normalize() {
        var raw = host.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Схема.
        if let schemeRange = raw.range(of: "://") {
            let scheme = raw[raw.startIndex..<schemeRange.lowerBound].lowercased()
            if scheme == "https" {
                useHTTPS = true
            } else if scheme == "http" {
                useHTTPS = false
            }
            raw = String(raw[schemeRange.upperBound...])
        }

        // 2. Путь / query / fragment — всё после первого «/», «?» или «#».
        if let cut = raw.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            raw = String(raw[raw.startIndex..<cut])
        }

        // 3. Встроенный порт. Аккуратно с IPv6 в скобках: «[::1]:8080».
        if raw.hasPrefix("["), let close = raw.firstIndex(of: "]") {
            let hostPart = String(raw[raw.startIndex...close])
            let afterClose = raw.index(after: close)
            if afterClose < raw.endIndex, raw[afterClose] == ":" {
                let portString = String(raw[raw.index(after: afterClose)...])
                if let parsed = Int(portString), parsed > 0 { port = parsed }
            }
            raw = hostPart
        } else if let colon = raw.lastIndex(of: ":"),
                  // ровно одно двоеточие → это host:port, а не «голый» IPv6
                  raw.filter({ $0 == ":" }).count == 1 {
            let portString = String(raw[raw.index(after: colon)...])
            if let parsed = Int(portString), parsed > 0 {
                port = parsed
                raw = String(raw[raw.startIndex..<colon])
            }
        }

        host = raw

        // 4. Нормализация порта: ≤0 → порт по умолчанию для текущей схемы.
        if port <= 0 {
            port = useHTTPS ? Self.httpsPort : Self.httpPort
        }
    }
}
