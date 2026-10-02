import Foundation

// MARK: - KeeneticPolicyCatalog
//
// В веб-интерфейсе «Применение политик» есть не только IP Policy (Policy0…),
// но и встроенные режимы hotspot: permit, deny и наследование с сегмента.

nonisolated enum KeeneticPolicyCatalog {
    static let builtInPermit = "permit"
    static let builtInDeny = "deny"
    static let builtInSegment = "segment"

    /// Режимы, которые Keenetic показывает в UI даже без записи в `show ip policy`.
    static let builtInPolicies: [AccessPolicy] = [
        AccessPolicy(
            name: builtInPermit,
            description: nil,
            routingInterface: nil
        ),
        AccessPolicy(
            name: builtInSegment,
            description: nil,
            routingInterface: nil
        ),
        AccessPolicy(
            name: builtInDeny,
            description: nil,
            routingInterface: nil
        ),
    ]

    static let policySlotRange = 0...15

    static func policySlotName(_ index: Int) -> String {
        "Policy\(index)"
    }

    static func isBuiltIn(_ name: String) -> Bool {
        name == builtInPermit || name == builtInDeny || name == builtInSegment
    }

    static func localizedTitle(for name: String) -> String? {
        switch name {
        case builtInPermit: return L10n.tr("Built-in Default Policy")
        case builtInSegment: return L10n.tr("Built-in Default Segment Policy")
        case builtInDeny: return L10n.tr("Built-in No Internet")
        default: return nil
        }
    }

    /// Встроенные режимы + IP Policy с роутера, без дубликатов.
    static func assignablePolicies(discovered: [AccessPolicy]) -> [AccessPolicy] {
        let merged = RCIJSONParser.mergePolicies([builtInPolicies, discovered])
        return merged.sorted { lhs, rhs in
            let lhsRank = sortRank(for: lhs.name)
            let rhsRank = sortRank(for: rhs.name)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func sortRank(for name: String) -> Int {
        switch name {
        case builtInPermit: return 0
        case builtInSegment: return 1
        case builtInDeny: return 2
        default:
            if name.range(of: #"^Policy\d+$"#, options: .regularExpression) != nil {
                return 10 + (Int(name.dropFirst(6)) ?? 99)
            }
            return 100
        }
    }
}
