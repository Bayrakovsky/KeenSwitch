import SwiftUI

// MARK: - MenuBarContentView
//
// Всплывающее меню из иконки в строке меню: выбор устройства и смена маршрутизации.

struct MenuBarContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            deviceSection
            Divider()
            policiesSection
            Divider()
            footer
        }
        .frame(width: 340)
        .task {
            await viewModel.refreshIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("KeenSwitch")
                    .font(.headline)

                RouterConnectionToolbarSummary(
                    connectionState: viewModel.connectionState,
                    routerInfo: viewModel.routerInfo,
                    endpointLabel: viewModel.connectionEndpointLabel(),
                    statusMessage: viewModel.statusMessage
                )
            }

            Spacer()

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Device"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            if viewModel.devices.isEmpty {
                Text(L10n.tr("No Devices"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                Picker(L10n.tr("Device"), selection: Binding(
                    get: { viewModel.selectedDeviceMAC ?? "" },
                    set: { viewModel.selectDevice($0.isEmpty ? nil : $0) }
                )) {
                    if !viewModel.pinnedDevices.isEmpty {
                        Section(L10n.tr("Pinned")) {
                            ForEach(viewModel.pinnedDevices) { device in
                                Text(deviceRowTitle(device))
                                    .tag(device.mac)
                            }
                        }
                    }
                    let unpinnedOnline = viewModel.unpinnedDevices.filter(\.isOnline)
                    let unpinnedOffline = viewModel.unpinnedDevices.filter { !$0.isOnline }
                    if !unpinnedOnline.isEmpty {
                        Section(L10n.tr("Online")) {
                            ForEach(unpinnedOnline) { device in
                                Text(deviceRowTitle(device))
                                    .tag(device.mac)
                            }
                        }
                    }
                    if !unpinnedOffline.isEmpty {
                        Section(L10n.tr("Offline")) {
                            ForEach(unpinnedOffline) { device in
                                Text(deviceRowTitle(device))
                                    .tag(device.mac)
                            }
                        }
                    }
                }
                .labelsHidden()
                .padding(.horizontal, 12)

                if let device = viewModel.selectedDevice {
                    HStack(spacing: 8) {
                        DeviceIconView(isOnline: device.isOnline, size: .body)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "network")
                                    .foregroundStyle(.secondary)
                                Text("\(L10n.tr("Network Interface")): \(device.interfaceName ?? "—")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(.secondary)
                                Text(device.routingSummary(policies: viewModel.policies))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var policiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Routing"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            if viewModel.selectedDevice == nil {
                Text(L10n.tr("Select Device Above"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else if viewModel.policies.isEmpty {
                Text(L10n.tr("Policies Not Loaded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.policies) { policy in
                        policyButton(policy)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
    }

    private func policyButton(_ policy: AccessPolicy) -> some View {
        let isActive = viewModel.activePolicy(for: viewModel.selectedDevice)?.name == policy.name

        return Button {
            Task { await viewModel.applyPolicy(policy) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.localizedDisplayTitle)
                        .font(.body)
                    if !policy.displaySubtitle.isEmpty {
                        Text(policy.displaySubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let route = policy.routingInterface {
                        Text("\(policy.name) · \(route)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .disabled(viewModel.selectedDeviceMAC == nil || viewModel.isBusy)
        .accessibilityLabel(policy.localizedDisplayTitle)
        .accessibilityHint(isActive ? L10n.tr("Active Policy Hint") : "")
    }

    private var footer: some View {
        HStack {
            Button(L10n.tr("Refresh")) {
                Task { await viewModel.refreshAll() }
            }
            .disabled(!viewModel.isConfigured || viewModel.isBusy)

            Spacer()

            Button(L10n.tr("Open")) {
                dismiss()
                MainWindowVisibility.show()
            }

            Button(L10n.tr("Settings")) {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
        .padding(12)
    }

    private func deviceRowTitle(_ device: NetworkDevice) -> String {
        let status = device.isOnline ? "" : " · \(L10n.tr("Offline").lowercased())"
        if let ip = device.ip {
            return "\(device.displayName) · \(ip)\(status)"
        }
        return "\(device.displayName)\(status)"
    }
}
