import AppKit
import SwiftUI

// MARK: - ContentView
//
// Главное окно: боковая колонка + список устройств (DevicesView).

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var selection: SidebarItem? = .devices

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(L10n.tr("Keenetic")) {
                    NavigationLink(value: SidebarItem.devices) {
                        Label(L10n.tr("Devices"), systemImage: "desktopcomputer")
                    }
                }

                Section {
                    if let message = viewModel.statusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selection {
            case .devices, .none:
                DevicesView()
            }
        }
        .background {
            MainWindowTagger()
            OpenWindowRegistrar()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        // Fix 7 — автообновление при восстановлении сетевого соединения.
        .onChange(of: viewModel.networkMonitor.isConnected) { wasConnected, isNowConnected in
            guard !wasConnected && isNowConnected else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }
}

#if os(macOS)
private struct MainWindowTagger: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MainWindowTagNSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        MainWindowVisibility.configureMainWindow(nsView.window)
    }
}

// Конфигурирует окно синхронно в viewWillMove(toWindow:) — до того как SwiftUI
// успевает вывести окно на экран, устраняя кратковременную вспышку иконки в Dock.
private final class MainWindowTagNSView: NSView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        MainWindowVisibility.configureMainWindow(newWindow)
    }
}
#endif

private enum SidebarItem: Hashable {
    case devices
}

