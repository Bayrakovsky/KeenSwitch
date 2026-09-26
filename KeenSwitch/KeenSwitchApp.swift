// KeenSwitchApp.swift
//
// Точка входа: главное окно (список устройств), окно настроек (Settings),
// иконка в строке меню (MenuBarExtra). Общий AppViewModel пробрасывается во все сцены.

import SwiftUI

struct KeenSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        // Window первым: при обычном запуске окно создаётся сразу (тихий старт скрывает его в AppDelegate).
        Window("KeenSwitch", id: MainWindowVisibility.windowID) {
            ContentView()
                .environment(viewModel)
                .environment(\.locale, LocalizationManager.locale)
                .id(viewModel.localeRevision)
        }
        .defaultSize(width: 720, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) { }
            // Свой пункт вместо стандартного Quit: он идёт через AppTermination.quit(),
            // которое выставляет userRequestedQuit и разрешает настоящее завершение в
            // applicationShouldTerminate. Dock → «Завершить» этот флаг не выставляет,
            // поэтому по-прежнему просто прячет приложение в строку меню.
            CommandGroup(replacing: .appTermination) {
                Button(L10n.tr("Quit KeenSwitch")) {
                    AppTermination.quit()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

#if os(macOS)
        MenuBarExtra("KeenSwitch", systemImage: "arrow.triangle.branch") {
            MenuBarContentView()
                .environment(viewModel)
                .environment(\.locale, LocalizationManager.locale)
                .id(viewModel.localeRevision)
        }
        .menuBarExtraStyle(.window)
#endif

#if os(macOS)
        Settings {
            SettingsView()
                .environment(viewModel)
                .environment(\.locale, LocalizationManager.locale)
                .id(viewModel.localeRevision)
        }
#endif
    }
}
