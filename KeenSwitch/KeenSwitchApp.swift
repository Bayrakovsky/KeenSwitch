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
            // Полный выход — ПКМ по иконке в строке меню (StatusBarQuitMenuAttacher).
            CommandGroup(replacing: .appTermination) { }
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
