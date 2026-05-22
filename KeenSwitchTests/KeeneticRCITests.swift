import Foundation
import Testing
@testable import KeenSwitch

struct KeeneticRCITests {
    @Test func parsesKeeneticOSPolicyArrayWithNameInPolicyKey() throws {
        let json = """
        {
          "policy": [
            {
              "policy": "Policy0",
              "description": "Доступ через VPN",
              "mark": "ffffaaa",
              "table4": 10
            }
          ]
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies.count == 1)
        #expect(policies[0].name == "Policy0")
        #expect(policies[0].description == "Доступ через VPN")
    }

    @Test func parsesShowWrappedPolicy() throws {
        let json = """
        {
          "show": {
            "ip": {
              "policy": {
                "Policy0": {
                  "description": "Доступ через VPN",
                  "mark": "ffffaaa"
                }
              }
            }
          }
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies.count == 1)
        #expect(policies[0].name == "Policy0")
    }

    @Test func parsesPoliciesKeyedFormat() throws {
        let json = """
        {
          "Policy0": { "description": "Доступ через VPN" }
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies.count == 1)
    }

    @Test func mergesHostPoliciesFromConfiguration() throws {
        let liveJSON = """
        {
          "host": [
            {
              "mac": "aa:bb:cc:dd:ee:ff",
              "name": "MacBook",
              "ip": "192.168.2.50",
              "active": true,
              "interface": { "name": "Bridge0" }
            }
          ]
        }
        """.data(using: .utf8)!

        let configJSON = """
        {
          "show": {
            "rc": {
              "ip": {
                "hotspot": {
                  "host": [
                    {
                      "mac": "aa:bb:cc:dd:ee:ff",
                      "permit": true,
                      "policy": "Policy0"
                    }
                  ]
                }
              }
            }
          }
        }
        """.data(using: .utf8)!

        var devices = try RCIJSONParser.devices(from: liveJSON)
        #expect(devices[0].currentPolicy == nil)

        let policies = try RCIJSONParser.hostPolicies(from: configJSON)
        #expect(policies["AA:BB:CC:DD:EE:FF"] == "Policy0")

        devices = RCIJSONParser.applyingHostPolicies(policies, to: devices)
        #expect(devices[0].currentPolicy == "Policy0")
    }

    @Test func deduplicateKeepsPolicyWhenMergingOnlineHost() throws {
        let json = """
        {
          "host": [
            {
              "mac": "aa:bb:cc:dd:ee:ff",
              "active": false,
              "policy": "Policy0"
            },
            {
              "mac": "aa:bb:cc:dd:ee:ff",
              "active": true,
              "ip": "192.168.2.50"
            }
          ]
        }
        """.data(using: .utf8)!

        let devices = try RCIJSONParser.devices(from: json)
        #expect(devices.count == 1)
        #expect(devices[0].isOnline)
        #expect(devices[0].currentPolicy == "Policy0")
    }

    @Test func parsesRouterInfoFromShowVersion() throws {
        let json = """
        {
          "show": {
            "version": {
              "release": "4.03.C.6.3-9",
              "title": "KeeneticOS 4.03",
              "device": "Hero 4G+",
              "hw_id": "KN-2311",
              "vendor": "Keenetic",
              "description": "Keenetic Hero 4G+ (KN-2311)"
            }
          }
        }
        """.data(using: .utf8)!
        let info = try RCIJSONParser.routerInfo(from: json)
        #expect(info.model == "Hero 4G+")
        #expect(info.hardwareID == "KN-2311")
        #expect(info.displayName == "Keenetic Hero 4G+ (KN-2311)")
        #expect(info.modelLine == "Hero 4G+ · KN-2311")
        #expect(info.firmwareLine == "KeeneticOS 4.03 (4.03.C.6.3-9)")
    }

    @Test func routerInfoPrefersHostnameOverDescription() throws {
        let json = """
        {
          "release": "4.03.C.6.3-9",
          "device": "Hero 4G+",
          "description": "Keenetic Hero 4G+"
        }
        """.data(using: .utf8)!
        var info = try RCIJSONParser.routerInfo(from: json)
        info = info.withHostname("Домашний роутер")
        #expect(info.displayName == "Домашний роутер")
    }

    @Test func parsesSystemHostname() throws {
        let json = """
        {
          "show": {
            "system": {
              "hostname": "Keenetic-3584",
              "domainname": "WORKGROUP"
            }
          }
        }
        """.data(using: .utf8)!
        #expect(RCIJSONParser.systemHostname(in: json) == "Keenetic-3584")
    }

    @Test func assignablePoliciesIncludeBuiltInModes() {
        let discovered = [
            AccessPolicy(name: "Policy0", description: "Доступ через VPN", routingInterface: "Proxy0"),
        ]
        let list = KeeneticPolicyCatalog.assignablePolicies(discovered: discovered)
        #expect(list.count == 4)
        #expect(list.map(\.name) == ["permit", "segment", "deny", "Policy0"])
        #expect(list.first { $0.name == "Policy0" }?.description == "Доступ через VPN")
    }

    @Test func hostPolicyNameRecognizesPermitAndDeny() throws {
        let json = """
        {
          "host": [
            { "mac": "aa:bb:cc:dd:ee:ff", "access": "permit" },
            { "mac": "11:22:33:44:55:66", "permit": false }
          ]
        }
        """.data(using: .utf8)!
        let map = try RCIJSONParser.hostPolicies(from: json)
        #expect(map["AA:BB:CC:DD:EE:FF"] == "permit")
        #expect(map["11:22:33:44:55:66"] == "deny")
    }

    @Test func applyingHostPoliciesClearsMissingAssignments() {
        let devices = [
            NetworkDevice(
                mac: "AA:BB:CC:DD:EE:FF",
                name: "Mac",
                ip: "192.168.2.1",
                interfaceName: "Bridge0",
                isOnline: true,
                currentPolicy: "Policy0"
            ),
        ]
        let merged = RCIJSONParser.applyingHostPolicies([:], to: devices)
        #expect(merged[0].currentPolicy == nil)
    }

    @Test func validateCommandResponseDetectsErrorStatus() {
        let json = """
        {
          "status": [
            {
              "status": "error",
              "message": "host not registered"
            }
          ]
        }
        """.data(using: .utf8)!

        #expect(throws: KeeneticError.self) {
            try RCIJSONParser.validateCommandResponse(json)
        }
    }

    @Test func sortsPinnedDevicesFirst() {
        let devices = [
            NetworkDevice(mac: "11:11:11:11:11:11", name: "B", ip: nil, interfaceName: nil, isOnline: true, currentPolicy: nil),
            NetworkDevice(mac: "AA:BB:CC:DD:EE:FF", name: "A", ip: nil, interfaceName: nil, isOnline: false, currentPolicy: nil),
            NetworkDevice(mac: "22:22:22:22:22:22", name: "C", ip: nil, interfaceName: nil, isOnline: true, currentPolicy: nil),
        ]
        let sorted = NetworkDevice.sortedForDisplay(devices, pinnedMACs: ["AA:BB:CC:DD:EE:FF"])
        #expect(sorted.map(\.mac) == ["AA:BB:CC:DD:EE:FF", "11:11:11:11:11:11", "22:22:22:22:22:22"])
    }

    @Test func parsesHostActiveFlag() throws {
        let json = """
        {
          "host": [
            {
              "mac": "aa:bb:cc:dd:ee:ff",
              "name": "MacBook",
              "ip": "192.168.2.50",
              "active": true,
              "interface": { "name": "Bridge0" }
            },
            {
              "mac": "11:22:33:44:55:66",
              "name": "Old Phone",
              "active": false
            }
          ]
        }
        """.data(using: .utf8)!
        let devices = try RCIJSONParser.devices(from: json)
        #expect(devices.count == 2)
        #expect(devices[0].mac == "AA:BB:CC:DD:EE:FF")
        #expect(devices[0].isOnline)
        #expect(devices[1].mac == "11:22:33:44:55:66")
        #expect(!devices[1].isOnline)
        #expect(devices[0].isOnline && !devices[1].isOnline)
    }

    @Test func parsesRcConfigPolicySectionsFromTelnetShape() throws {
        let json = """
        {
          "show": {
            "rc": {
              "ip": {
                "policy": [
                  { "name": "policy", "policy": { "name": "Policy0" } },
                  { "name": "description", "description": "Доступ через VPN" },
                  { "name": "permit", "enabled": true, "interface": "Proxy0" },
                  { "name": "permit", "no": true, "enabled": false, "interface": "UsbDsl0" },
                  { "name": "permit", "no": true, "enabled": false, "interface": "GigabitEthernet0/Vlan4" }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies.count == 1)
        #expect(policies[0].name == "Policy0")
        #expect(policies[0].description == "Доступ через VPN")
        #expect(policies[0].routingInterface == "Proxy0")
    }

    @Test func parsesRcConfigAtRootWithoutShowWrapper() throws {
        let json = """
        {
          "rc": {
            "ip": {
              "policy": [
                { "policy": { "name": "Policy0" } },
                { "description": "Доступ через VPN" },
                { "permit": { "enabled": true, "interface": "Proxy0" } }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies.count == 1)
        #expect(policies[0].routingInterface == "Proxy0")
    }

    @Test func parsesAllPoliciesWhenKeyedTableHasRouteSibling() throws {
        let json = """
        {
          "show": {
            "rc": {
              "ip": {
                "policy": {
                  "Policy0": { "description": "Политика по умолчанию" },
                  "Policy1": { "description": "Политика по умолчанию сегмента" },
                  "Policy2": { "description": "Доступ через VPN" },
                  "Policy3": { "description": "Без доступа в интернет" },
                  "route": [
                    { "destination": "0.0.0.0/0", "interface": "ISP" }
                  ]
                }
              }
            }
          }
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies.count == 4)
        #expect(policies.map(\.name).sorted() == ["Policy0", "Policy1", "Policy2", "Policy3"])
        #expect(policies.first { $0.name == "Policy2" }?.description == "Доступ через VPN")
    }

    @Test func mergePoliciesCombinesListsFromDifferentEndpoints() {
        let live = [
            AccessPolicy(name: "Policy2", description: "Доступ через VPN", routingInterface: nil),
        ]
        let saved = [
            AccessPolicy(name: "Policy0", description: "Политика по умолчанию", routingInterface: nil),
            AccessPolicy(name: "Policy1", description: "Политика по умолчанию сегмента", routingInterface: nil),
            AccessPolicy(name: "Policy2", description: "Доступ через VPN", routingInterface: "OpenVPN0"),
            AccessPolicy(name: "Policy3", description: "Без доступа в интернет", routingInterface: nil),
        ]
        let merged = RCIJSONParser.mergePolicies([live, saved])
        #expect(merged.count == 4)
        #expect(merged.first { $0.name == "Policy2" }?.routingInterface == "OpenVPN0")
        #expect(merged.first { $0.name == "Policy2" }?.description == "Доступ через VPN")
    }

    @Test func parsesRoutingInterfaceFromRoute4() throws {
        let json = """
        {
          "Policy0": {
            "description": "Доступ через VPN",
            "route4": {
              "route": [
                { "destination": "0.0.0.0/0", "interface": "OpenVPN0" }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let policies = try RCIJSONParser.policies(from: json)
        #expect(policies[0].routingInterface == "OpenVPN0")
    }

    @Test func routerSettingsDetectsCustomPort() {
        var settings = RouterSettings.default
        #expect(!settings.hasCustomPort)

        settings.port = 8080
        #expect(settings.hasCustomPort)

        settings.port = RouterSettings.httpsPort
        #expect(!settings.hasCustomPort)
    }

    // MARK: - RouterSettings.normalize (адрес из браузера)

    @Test func normalizeStripsHTTPScheme() {
        var s = RouterSettings.default
        s.host = "http://192.168.1.1"
        s.useHTTPS = true
        s.normalize()
        #expect(s.host == "192.168.1.1")
        #expect(s.useHTTPS == false) // схема http:// перекрывает флаг
    }

    @Test func normalizeStripsHTTPSSchemeAndSetsFlag() {
        var s = RouterSettings.default
        s.host = "https://my.keenetic.net"
        s.useHTTPS = false
        s.normalize()
        #expect(s.host == "my.keenetic.net")
        #expect(s.useHTTPS == true)
    }

    @Test func normalizeStripsTrailingSlashAndPath() {
        var s = RouterSettings.default
        s.host = "192.168.1.1/admin/index.html"
        s.normalize()
        #expect(s.host == "192.168.1.1")
    }

    @Test func normalizeExtractsInlinePort() {
        var s = RouterSettings.default
        s.host = "192.168.1.1:8080"
        s.normalize()
        #expect(s.host == "192.168.1.1")
        #expect(s.port == 8080)
    }

    @Test func normalizeExtractsPortFromFullURL() {
        var s = RouterSettings.default
        s.host = "https://192.168.1.1:8443/"
        s.normalize()
        #expect(s.host == "192.168.1.1")
        #expect(s.port == 8443)
        #expect(s.useHTTPS == true)
    }

    @Test func normalizeZeroPortFallsBackToDefault() {
        var s = RouterSettings.default
        s.host = "192.168.1.1"
        s.port = 0
        s.useHTTPS = false
        s.normalize()
        #expect(s.port == RouterSettings.httpPort)

        var https = RouterSettings.default
        https.host = "192.168.1.1"
        https.port = 0
        https.useHTTPS = true
        https.normalize()
        #expect(https.port == RouterSettings.httpsPort)
    }

    @Test func normalizeTrimsWhitespace() {
        var s = RouterSettings.default
        s.host = "  192.168.1.1  "
        s.normalize()
        #expect(s.host == "192.168.1.1")
    }

    @Test func normalizeKeepsPlainHostUnchanged() {
        var s = RouterSettings.default
        s.host = "192.168.1.1"
        s.port = 80
        s.normalize()
        #expect(s.host == "192.168.1.1")
        #expect(s.port == 80)
    }

    @Test func normalizeHandlesIPv6WithPort() {
        var s = RouterSettings.default
        s.host = "[fe80::1]:8080"
        s.normalize()
        #expect(s.host == "[fe80::1]")
        #expect(s.port == 8080)
    }

    @Test func normalizeKeepsBareIPv6() {
        var s = RouterSettings.default
        s.host = "[fe80::1]"
        s.port = 80
        s.normalize()
        #expect(s.host == "[fe80::1]")
        #expect(s.port == 80)
    }
}
