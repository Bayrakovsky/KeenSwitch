import SwiftUI

// MARK: - RouterConnectionToolbarSummary
//
// Одна строка в меню-баре: индикатор + адрес · модель · KN-xxxx · прошивка.

struct RouterConnectionToolbarSummary: View {
    let connectionState: ConnectionState
    let routerInfo: RouterInfo?
    let endpointLabel: String
    let statusMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            connectionIndicator

            Text(compactLine)
                .font(.caption)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var compactLine: String {
        var parts: [String] = []

        if let host = displayHost {
            parts.append(host)
        }

        switch connectionState {
        case .connected:
            if let routerInfo {
                parts.append(routerInfo.model)
                if let hardwareID = routerInfo.hardwareID, !hardwareID.isEmpty {
                    parts.append(hardwareID)
                }
                if let firmware = routerInfo.firmwareRelease, !firmware.isEmpty {
                    parts.append(firmware)
                }
            }
        case .connecting:
            parts.append(L10n.tr("Connecting"))
        case .error:
            parts.append(L10n.tr("Error"))
            if let statusMessage, !statusMessage.isEmpty {
                parts.append(statusMessage)
            }
        case .disconnected:
            if parts.isEmpty {
                parts.append(L10n.tr("Keenetic"))
            }
        }

        return parts.joined(separator: " · ")
    }

    private var displayHost: String? {
        guard !endpointLabel.isEmpty, !isBareScheme(endpointLabel) else { return nil }
        var host = stripScheme(from: endpointLabel)
        if host.hasSuffix(":443") {
            host.removeLast(4)
        } else if host.hasSuffix(":80") {
            host.removeLast(3)
        }
        return host.isEmpty ? nil : host
    }

    private var textColor: Color {
        switch connectionState {
        case .connected: .secondary
        case .connecting: .secondary
        case .error: .orange
        case .disconnected: .secondary
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(accessibilityStatusLabel)
    }

    private var indicatorColor: Color {
        switch connectionState {
        case .connected: .green
        case .connecting: Color.accentColor
        case .error: .orange
        case .disconnected: Color.secondary.opacity(0.45)
        }
    }

    private var accessibilityStatusLabel: String {
        switch connectionState {
        case .connected: L10n.tr("Connected")
        case .connecting: L10n.tr("Connecting")
        case .error: L10n.tr("Error")
        case .disconnected: L10n.tr("Not Connected")
        }
    }

    private func isBareScheme(_ label: String) -> Bool {
        label == "https://" || label == "http://"
    }

    private func stripScheme(from label: String) -> String {
        if let range = label.range(of: "://") {
            return String(label[range.upperBound...])
        }
        return label
    }
}

private extension ConnectionState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
