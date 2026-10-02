import AppKit
import SwiftUI

// MARK: - SettingsView
//
// Окно настроек (⌘,): фиксированное меню слева + форма справа.

private enum SettingsPane: String, CaseIterable, Identifiable {
    case connection
    case routing
    case language
    case launch
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: L10n.tr("Connection")
        case .routing: L10n.tr("Routing")
        case .language: L10n.tr("Language")
        case .launch: L10n.tr("Launch")
        case .updates: L10n.tr("Updates")
        }
    }

    var symbol: String {
        switch self {
        case .connection: "network"
        case .routing: "arrow.triangle.branch"
        case .language: "globe"
        case .launch: "play.circle"
        case .updates: "arrow.down.circle"
        }
    }
}

struct SettingsView: View {
    // @AppStorage, а не @State: при смене языка KeenSwitchApp форсирует пересоздание
    // SettingsView через .id(localeRevision) — обычный @State сбрасывался бы на .connection.
    // Бонус: выбранная вкладка сохраняется между открытиями окна.
    @AppStorage("settingsSelectedPane") private var selection: SettingsPane = .connection

    var body: some View {
        // Нативный TabView в сцене Settings: хрому окна рисует сама macOS, поэтому
        // настройки бесплатно получают оформление текущей версии системы. Рукописный
        // сайдбар с непрозрачной заливкой не получал ни стекла, ни правок macOS 27
        // (сайдбар до края окна, semibold-выделение, стеклянные элементы над ним).
        TabView(selection: $selection) {
            ConnectionSettingsTab().settingsPane(.connection)
            RoutingSettingsTab().settingsPane(.routing)
            LanguageSettingsTab().settingsPane(.language)
            LaunchSettingsTab().settingsPane(.launch)
            UpdatesSettingsTab().settingsPane(.updates)
        }
        .frame(minWidth: 600, minHeight: 600)
        .settingsWindowTitle(L10n.tr("App Settings Window Title"))
    }
}

private extension View {
    /// Вкладка окна настроек: подпись с иконкой и тег для $selection.
    func settingsPane(_ pane: SettingsPane) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem { Label(pane.title, systemImage: pane.symbol) }
            .tag(pane)
    }
}

// MARK: - Подключение

private enum ConnectionFormMetrics {
    static let fieldWidth: CGFloat = 260
}

private struct ConnectionSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            connectionStatusSection

            Section {
                LabeledContent(L10n.tr("Router Address")) {
                    TextField("", text: $viewModel.settings.host, prompt: Text("192.168.1.1"))
                        .connectionFormField()
                        .onSubmit { Task { await viewModel.saveConnectionSettings() } }
                        .onChange(of: viewModel.settings.host) { _, _ in
                            viewModel.scheduleSaveConnectionSettings()
                        }
                        .accessibilityLabel(L10n.tr("Router Address"))
                }

                Toggle(L10n.tr("HTTPS"), isOn: $viewModel.settings.useHTTPS)
                    .disabled(viewModel.settings.hasCustomPort)
                    .onChange(of: viewModel.settings.useHTTPS) { _, useHTTPS in
                        guard !viewModel.settings.hasCustomPort else { return }
                        viewModel.settings.port = useHTTPS ? RouterSettings.httpsPort : RouterSettings.httpPort
                        Task { await viewModel.saveConnectionSettings() }
                    }
                    .help(
                        viewModel.settings.hasCustomPort
                            ? L10n.tr("HTTPS Toggle Disabled Help")
                            : ""
                    )

                LabeledContent(L10n.tr("Port")) {
                    TextField("", value: $viewModel.settings.port, format: .number, prompt: Text("80"))
                        .connectionFormField()
                        .onSubmit { Task { await viewModel.saveConnectionSettings() } }
                        .onChange(of: viewModel.settings.port) { _, _ in
                            viewModel.scheduleSaveConnectionSettings()
                        }
                }

                LabeledContent(L10n.tr("User")) {
                    TextField("", text: $viewModel.settings.username, prompt: Text("admin"))
                        .connectionFormField()
                        .onSubmit { Task { await viewModel.saveConnectionSettings() } }
                        .onChange(of: viewModel.settings.username) { _, _ in
                            viewModel.scheduleSaveConnectionSettings()
                        }
                }

                LabeledContent(L10n.tr("Password")) {
                    SecureField("", text: $viewModel.password, prompt: Text("••••••••"))
                        .connectionFormField()
                        .onSubmit { Task { await viewModel.saveConnectionSettings() } }
                        .onChange(of: viewModel.password) { _, _ in
                            viewModel.scheduleSaveConnectionSettings()
                        }
                        .accessibilityLabel(L10n.tr("Password"))
                }
            } header: {
                Text(L10n.tr("Keenetic Router"))
            } footer: {
                Text(L10n.tr("Router Info Footer"))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .settingsDetailHeader(L10n.tr("Connection"))
    }

    private var connectionStatusSection: some View {
        Section {
            RouterConnectionStatusCard(
                connectionState: viewModel.connectionState,
                routerInfo: viewModel.routerInfo,
                endpointLabel: viewModel.connectionEndpointLabel(),
                statusMessage: viewModel.statusMessage,
                isBusy: viewModel.isBusy,
                canTest: !viewModel.password.isEmpty,
                onTest: { Task { await viewModel.testConnection() } }
            )
        }
    }
}

// MARK: - Карточка подключения

private struct RouterConnectionStatusCard: View {
    let connectionState: ConnectionState
    let routerInfo: RouterInfo?
    let endpointLabel: String
    let statusMessage: String?
    let isBusy: Bool
    let canTest: Bool
    let onTest: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            routerIcon

            VStack(alignment: .leading, spacing: 6) {
                routerTitleBlock
                connectionStatusRow
                endpointCaption
            }

            Spacer(minLength: 8)

            Button(action: onTest) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Text(L10n.tr("Check"))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !canTest)
        }
        .padding(12)
        .background {
            if #available(macOS 26, *) {
                ConcentricRectangle(corners: .concentric(minimum: .fixed(10)))
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        }
        .overlay {
            if #available(macOS 26, *) {
                // ConcentricRectangle не InsettableShape, поэтому stroke, а не strokeBorder.
                ConcentricRectangle(corners: .concentric(minimum: .fixed(10)))
                    .stroke(borderColor.opacity(0.35), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var routerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconBackgroundColor)
                .frame(width: 44, height: 44)

            Image(systemName: "wifi.router.fill")
                .font(.system(size: 22))
                .foregroundStyle(iconForegroundColor)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var routerTitleBlock: some View {
        if let routerInfo, connectionState == .connected {
            Text(routerInfo.displayName)
                .font(.headline)
                .lineLimit(2)

            Text(routerInfo.modelLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let firmware = routerInfo.firmwareLine {
                Text(firmware)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        } else {
            Text(L10n.tr("Keenetic Router"))
                .font(.headline)
            if !endpointLabel.isEmpty, endpointLabel != "https://" && endpointLabel != "http://" {
                Text(endpointLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var connectionStatusRow: some View {
        HStack(spacing: 6) {
            connectionStatusLabel
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var endpointCaption: some View {
        if connectionState == .connected, routerInfo != nil {
            Text(endpointLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else if let statusMessage, connectionState == .connecting || connectionState.isError {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(connectionState.isError ? .orange : .secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch connectionState {
        case .disconnected:
            Label(L10n.tr("Not Connected"), systemImage: "circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .connecting:
            Label(L10n.tr("Connecting…"), systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline)
        case .connected:
            Label(L10n.tr("Connected"), systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .error:
            Label(L10n.tr("Error"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
    }

    private var borderColor: Color {
        switch connectionState {
        case .connected: .green
        case .error: .orange
        default: Color(nsColor: .separatorColor)
        }
    }

    private var iconBackgroundColor: Color {
        switch connectionState {
        case .connected: Color.green.opacity(0.14)
        case .error: Color.orange.opacity(0.14)
        case .connecting: Color.accentColor.opacity(0.12)
        default: Color.secondary.opacity(0.12)
        }
    }

    private var iconForegroundColor: Color {
        switch connectionState {
        case .connected: .green
        case .error: .orange
        case .connecting: Color.accentColor
        default: .secondary
        }
    }
}

private extension ConnectionState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

private extension View {
    /// Единая ширина полей на вкладке «Подключение».
    func connectionFormField() -> some View {
        textFieldStyle(.roundedBorder)
            .frame(width: ConnectionFormMetrics.fieldWidth)
    }
}

// MARK: - Маршрутизация

private struct RoutingSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle(isOn: $viewModel.settings.saveConfigurationAfterChange) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Save Configuration After Change"))
                        Text(L10n.tr("Save Configuration Footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.settings.saveConfigurationAfterChange) { _, _ in
                    viewModel.saveRouterBehaviorSettings()
                }
            } footer: {
                Text(L10n.tr("Save Configuration Footer"))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .settingsDetailHeader(L10n.tr("Routing"))
    }
}

// MARK: - Язык

private struct LanguageSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("Interface Language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.pickerTitle).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .leading)
            } footer: {
                Text(L10n.tr("Interface Language Footer"))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .settingsDetailHeader(L10n.tr("Language"))
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(languageCode: viewModel.appPreferences.languageCode) },
            set: { viewModel.setAppLanguage($0) }
        )
    }
}

// MARK: - Запуск

private struct LaunchSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle(isOn: $viewModel.appPreferences.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Open At Login"))
                        Text(L10n.tr("KeenSwitch will launch at login"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.appPreferences.launchAtLogin) { _, enabled in
                    if let message = viewModel.updateLaunchAtLogin(enabled: enabled) {
                        viewModel.statusMessage = message
                    }
                }

                Toggle(isOn: $viewModel.appPreferences.quietLaunchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Quiet Launch At Login"))
                        Text(L10n.tr("Quiet Launch Footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!viewModel.appPreferences.launchAtLogin)
                .onChange(of: viewModel.appPreferences.quietLaunchAtLogin) { _, _ in
                    viewModel.persistAppPreferences()
                }
            } footer: {
                Text(L10n.tr("Quiet Launch Footer"))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .settingsDetailHeader(L10n.tr("Launch"))
    }
}

// MARK: - Обновления

private struct UpdatesSettingsTab: View {
    @Environment(AppViewModel.self) private var viewModel
    // Поле GitHub Token нужно было пока репозиторий был приватным.
    // После публикации не требуется — публичный Releases API доступен анонимно.
    // Поле и связанные методы оставлены закомментированными на случай возврата
    // к приватному режиму.
    // @State private var githubToken: String = ""

    private var checker: UpdateChecker { viewModel.updateChecker }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Toggle(isOn: $viewModel.appPreferences.autoCheckForUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Auto Check For Updates"))
                        Text(L10n.tr("Auto Check Footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.appPreferences.autoCheckForUpdates) { _, _ in
                    viewModel.persistAppPreferences()
                }
            }

            Section {
                UpdateStatusCard(checker: checker)
            }

            // Секция ввода GitHub Token — закомментирована после публикации репозитория.
            // Section {
            //     LabeledContent(L10n.tr("GitHub Token")) {
            //         SecureField("", text: $githubToken)
            //             .textFieldStyle(.roundedBorder)
            //             .frame(width: 260)
            //             .onSubmit { saveToken() }
            //             .onChange(of: githubToken) { _, _ in saveToken() }
            //     }
            //     Text(L10n.tr("GitHub Token Footer"))
            //         .font(.caption)
            //         .foregroundStyle(.secondary)
            // }
        }
        .formStyle(.grouped)
        .padding(20)
        .settingsDetailHeader(L10n.tr("Updates"))
        // .onAppear { loadToken() }
    }

    // private func loadToken() {
    //     githubToken = (try? KeychainStore.loadPassword(account: KeychainStore.githubTokenAccount)) ?? ""
    // }
    //
    // private func saveToken() {
    //     if githubToken.isEmpty {
    //         try? KeychainStore.deletePassword(account: KeychainStore.githubTokenAccount)
    //     } else {
    //         try? KeychainStore.savePassword(githubToken, account: KeychainStore.githubTokenAccount)
    //     }
    // }
}

private struct UpdateStatusCard: View {
    let checker: UpdateChecker

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                statusTitle
            }
            Spacer()
            actionButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch checker.state {
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2).foregroundStyle(.tint)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundStyle(.orange)
        case .downloading, .installing:
            ProgressView().controlSize(.small)
        default:
            Image(systemName: "arrow.down.circle")
                .font(.title2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusTitle: some View {
        switch checker.state {
        case .idle:
            Text(L10n.tr("Check For Updates")).foregroundStyle(.primary)
        case .checking:
            Text(L10n.tr("Checking For Updates")).foregroundStyle(.secondary)
        case .upToDate(let version):
            Text(L10n.tr("Up To Date"))
            Text(L10n.tr("Version") + " \(version)").font(.caption).foregroundStyle(.secondary)
        case .available(_, let latest, _):
            Text(L10n.tr("Update Available"))
            Text(L10n.tr("Version") + " \(latest)").font(.caption).foregroundStyle(.tint)
        case .downloading(let progress):
            Text(L10n.tr("Downloading Update"))
            ProgressView(value: progress)
                .frame(maxWidth: 160)
                .padding(.top, 2)
        case .installing:
            Text(L10n.tr("Installing Update"))
            Text(L10n.tr("Restart Shortly")).font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(L10n.tr("Update Check Failed"))
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch checker.state {
        case .available(_, _, let assetId):
            Button(L10n.tr("Install Update")) {
                Task { await checker.downloadAndInstall(assetId: assetId) }
            }
            .buttonStyle(.borderedProminent)
        case .idle, .upToDate, .failed:
            Button(L10n.tr("Check For Updates")) {
                Task { await checker.checkForUpdates() }
            }
            .buttonStyle(.bordered)
        case .checking, .downloading, .installing:
            EmptyView()
        }
    }
}

private struct SettingsDetailHeaderModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)
            content
        }
    }
}

private extension View {
    func settingsDetailHeader(_ title: String) -> some View {
        modifier(SettingsDetailHeaderModifier(title: title))
    }
}
