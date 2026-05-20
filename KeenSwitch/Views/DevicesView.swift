import SwiftUI

// MARK: - DevicesView
//
// Список устройств в главном окне: закреплённые / в сети / офлайн, выбор маршрутизации.

struct DevicesView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Group {
            if viewModel.devices.isEmpty {
                ContentUnavailableView {
                    Label(L10n.tr("No Devices"), systemImage: "desktopcomputer")
                } description: {
                    Text(L10n.tr("Refresh Hint"))
                } actions: {
                    Button(L10n.tr("Refresh")) {
                        Task { await viewModel.refreshAll() }
                    }
                    .disabled(!viewModel.isConfigured)
                }
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedDeviceMAC },
                    set: { viewModel.selectDevice($0) }
                )) {
                    if !viewModel.pinnedDevices.isEmpty {
                        Section {
                            ForEach(viewModel.pinnedDevices) { device in
                                deviceRow(device)
                            }
                        } header: {
                            Label(L10n.tr("Pinned"), systemImage: "pin.fill")
                        }
                    }

                    if !viewModel.unpinnedDevices.isEmpty {
                        Section {
                            ForEach(viewModel.unpinnedDevices) { device in
                                deviceRow(device)
                            }
                        } header: {
                            if viewModel.pinnedDevices.isEmpty {
                                Text(L10n.tr("Devices"))
                            } else {
                                Text(L10n.tr("Others"))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("Devices"))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await viewModel.refreshAll() }
                } label: {
                    Label(L10n.tr("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(!viewModel.isConfigured || viewModel.isBusy)

                if viewModel.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: NetworkDevice) -> some View {
        DeviceRow(
            device: device,
            isPinned: viewModel.isPinned(mac: device.mac),
            policies: viewModel.policies,
            activePolicy: viewModel.activePolicy(for: device),
            onTogglePin: { viewModel.togglePin(mac: device.mac) }
        ) { policy in
            viewModel.selectDevice(device.mac)
            Task { await viewModel.applyPolicy(policy, for: device.mac) }
        }
        .tag(device.mac)
    }
}

private struct DeviceRow: View {
    let device: NetworkDevice
    let isPinned: Bool
    let policies: [AccessPolicy]
    let activePolicy: AccessPolicy?
    let onTogglePin: () -> Void
    let onSelectPolicy: (AccessPolicy) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DeviceIconView(isOnline: device.isOnline)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.headline)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(L10n.tr("Pinned Help"))
                    }
                    if !device.isOnline {
                        Text(L10n.tr("Offline"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let ip = device.ip {
                        Text(ip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(device.mac)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Label(device.routingSummary(policies: policies), systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let iface = device.interfaceName {
                    Label(L10n.tr("Network Interface") + ": \(iface)", systemImage: "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"))
                .accessibilityLabel(isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"))

                Menu {
                    ForEach(policies) { policy in
                        Button {
                            onSelectPolicy(policy)
                        } label: {
                            if activePolicy?.name == policy.name {
                                Label(policy.localizedDisplayTitle, systemImage: "checkmark")
                            } else {
                                Text(policy.localizedDisplayTitle)
                            }
                        }
                        .accessibilityLabel(policy.localizedDisplayTitle)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .disabled(policies.isEmpty)
                .accessibilityLabel(L10n.tr("Select Policy"))
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(
                    isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"),
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
        }
    }
}
