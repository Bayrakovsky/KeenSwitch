import AppKit

// MARK: - AppDelegate
//
// Тихий старт → только menu bar. Обычный → menu bar + главное окно.
// Закрытие окна / Dock «Завершить» → скрыть окно и убрать иконку из Dock; menu bar остаётся.
// Полный выход — ⌘Q в меню приложения или кнопка Quit в popup строки меню.

final class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        MainActor.assumeIsolated {
            AppLaunchMode.configureActivationPolicyAtLaunchIfNeeded()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppLaunchMode.configureActivationPolicyAtLaunchIfNeeded()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppTermination.resetQuitRequest()

        // Системный logout / restart / shutdown — разрешаем честное завершение,
        // иначе applicationShouldTerminate отменил бы выход из системы.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppTermination.markSystemPowerOff()
        }

        MainActor.assumeIsolated {
            if AppLaunchMode.shouldShowMainWindowAtLaunch {
                MainWindowVisibility.presentAtLaunchIfNeeded()
            } else {
                MainWindowVisibility.hide()
            }
        }

        reconcileLoginItemRegistration()
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { AppLaunchMode.shouldShowMainWindowAtLaunch }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            if !MainWindowVisibility.isMainWindowVisible {
                MainWindowVisibility.show()
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Явный выход пользователя ИЛИ системный logout/restart/shutdown → завершаемся.
        // Иначе (закрытие окна / Dock «Завершить») просто прячемся в menu bar.
        if AppTermination.allowsTermination {
            return .terminateNow
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                MainWindowVisibility.hideForDockQuit()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    MainWindowVisibility.hideForDockQuit()
                }
            }
        }
        return .terminateCancel
    }

    private func reconcileLoginItemRegistration() {
        let shouldEnable = AppSettings.preferences.launchAtLogin
        try? LaunchAtLoginManager.syncWithPreference(shouldEnable)
    }
}
