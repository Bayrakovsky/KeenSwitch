import AppKit

// MARK: - AppDelegate
//
// Тихий старт → только menu bar. Обычный → menu bar + главное окно.
// Закрытие окна / Dock «Завершить» → скрыть окно и убрать иконку из Dock; menu bar остаётся.
// Полный выход — ПКМ по иконке в строке меню.

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

#if os(macOS)
        StatusBarQuitMenuAttacher.install()
#endif

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
        if AppTermination.userRequestedQuit {
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
