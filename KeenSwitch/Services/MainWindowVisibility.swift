import AppKit
import OSLog
import SwiftUI

// MARK: - MainWindowVisibility
//
// Одно главное окно. Скрыто → `.accessory` (нет иконки в Dock, только menu bar).
// Показано → `.regular` (Dock + окно).
//
// Чистый static-фасад: тип хранит приватное static-состояние, без shared-инстанса
// и без публичного instance-API. Соответствует тому, как с ним работают AppDelegate /
// ContentView (одно глобальное окно на процесс) и делает вызовы короче —
// `MainWindowVisibility.show()` вместо `MainWindowVisibility.shared.show()`.
// Тесты сюда не лезут (логика управления окном проверяется UI smoke-тестами,
// а не юнитами), так что singleton-форма не мешает тестируемости.

@MainActor
enum MainWindowVisibility {

    // MARK: - Константы

    static let windowID = "main"
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("keenswitch.main")

    // MARK: - Приватное состояние

    private static let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "WindowLifecycle")

    /// Окно было создано в `.accessory` и нуждается в пересоздании для glass/vibrancy.
    private static var mainWindowNeedsVibrancyRecreate = false

    /// Callback, зарегистрированный из SwiftUI-среды (`openWindow`) — только дерево SwiftUI
    /// владеет действием `openWindow`, поэтому отдаём его static-фасаду.
    private static var openWindowHandler: (() -> Void)?

    /// Делегаты закрытия окон — один на окно; хранение по ObjectIdentifier для правильного lifetime.
    private static var closeDelegates: [ObjectIdentifier: MainWindowCloseDelegate] = [:]

    /// Слабая ссылка на главное окно — работает даже после orderOut(nil),
    /// когда canBecomeMain возвращает false и allMainWindows() его не видит.
    private static weak var _mainWindow: NSWindow?

    // MARK: - Публичный API

    static func registerOpenWindow(_ handler: @escaping () -> Void) {
        openWindowHandler = handler
    }

    static func configureMainWindow(_ window: NSWindow?) {
        guard let window, isMainAppWindow(window) else { return }
        if NSApp.activationPolicy() == .accessory, !AppLaunchMode.suppressMainWindow {
            mainWindowNeedsVibrancyRecreate = true
        }
        window.identifier = mainWindowIdentifier
        _mainWindow = window
        let key = ObjectIdentifier(window)
        if closeDelegates[key] == nil {
            let delegate = MainWindowCloseDelegate()
            closeDelegates[key] = delegate
            window.delegate = delegate
        }
        deduplicateMainWindows()
        if AppLaunchMode.suppressMainWindow {
            window.orderOut(nil)
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        } else if mainWindowNeedsVibrancyRecreate {
            scheduleMainWindowRecreateForVibrancy()
        }
    }

    static var isMainWindowVisible: Bool {
        primaryMainWindow()?.isVisible == true
    }

    /// Показать главное окно (создать если нет, поднять на передний план).
    static func show() {
        logger.info("show() — запрос на показ главного окна")
        AppLaunchMode.allowMainWindow()
        let wasAccessory = NSApp.activationPolicy() != .regular
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
        }
        orderOutAuxiliaryWindows()

        if wasAccessory {
            // macOS обрабатывает смену политики активации асинхронно: Dock-иконка
            // появляется, но makeKeyAndOrderFront в том же такте не срабатывает.
            // Откладываем показ окна, чтобы дать системе завершить переход.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainWindowVisibility.showWindowInternal()
            }
            return
        }
        showWindowInternal()
    }

    private static func showWindowInternal() {
        if mainWindowNeedsVibrancyRecreate {
            recreateMainWindowForVibrancy()
            return
        }

        if let existing = primaryMainWindow() {
            deduplicateMainWindows(keeping: existing)
            bringToFront(existing)
            return
        }

        if openWindowHandler == nil {
            logger.error("showWindowInternal — openWindowHandler == nil, окно создать нечем")
        }
        openWindowHandler?()
        waitForMainWindow(attempt: 0)
    }

    static func hide() {
        logger.info("hide() — переход в режим только menu bar")
        hideAllMainWindows()
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Синхронно при Dock «Завершить» / ⌘Q (без полного выхода).
    static func hideForDockQuit() {
        hide()
    }

    /// Обычный запуск: показать окно, повторять пока SwiftUI не создаст сцену.
    static func presentAtLaunchIfNeeded() {
        guard AppLaunchMode.shouldShowMainWindowAtLaunch else { return }
        presentAtLaunch(attempt: 0)
    }

    /// Скрыть главное окно и убрать приложение из Dock (остаётся иконка в menu bar).
    static func enterMenuBarOnlyMode() {
        logger.info("enterMenuBarOnlyMode() — переход в режим только menu bar")
        hideAllMainWindows()
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Реализация

    private static func presentAtLaunch(attempt: Int) {
        show()
        if primaryMainWindow()?.isVisible == true || attempt >= 30 { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            presentAtLaunch(attempt: attempt + 1)
        }
    }

    private static func waitForMainWindow(attempt: Int) {
        if let window = primaryMainWindow() {
            deduplicateMainWindows(keeping: window)
            bringToFront(window)
            return
        }
        guard attempt < 30 else {
            logger.error("waitForMainWindow — окно так и не появилось за 30 попыток")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForMainWindow(attempt: attempt + 1)
        }
    }

    private static func scheduleMainWindowRecreateForVibrancy() {
        DispatchQueue.main.async {
            guard mainWindowNeedsVibrancyRecreate else { return }
            recreateMainWindowForVibrancy()
        }
    }

    /// Закрывает окно, созданное в .accessory, и открывает новое уже в .regular.
    private static func recreateMainWindowForVibrancy() {
        guard mainWindowNeedsVibrancyRecreate else { return }
        logger.info("Recreating main window to restore vibrancy/glass")

        AppLaunchMode.allowMainWindow()
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        for window in allMainWindows() {
            let key = ObjectIdentifier(window)
            closeDelegates.removeValue(forKey: key)
            window.delegate = nil
            window.close()
        }
        _mainWindow = nil
        mainWindowNeedsVibrancyRecreate = false

        openWindowHandler?()
        waitForMainWindow(attempt: 0)
    }

    private static func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func hideAllMainWindows() {
        for window in allMainWindows() {
            window.orderOut(nil)
        }
    }

    private static func deduplicateMainWindows(keeping keeper: NSWindow? = nil) {
        let windows = allMainWindows()
        guard windows.count > 1 else { return }
        let preferred = keeper
            ?? windows.first(where: { $0.identifier == mainWindowIdentifier })
            ?? windows.first
        guard let preferred else { return }
        for window in windows where window !== preferred {
            window.close()
        }
    }

    private static func primaryMainWindow() -> NSWindow? {
        if let stored = _mainWindow { return stored }
        let windows = allMainWindows()
        return windows.first(where: { $0.identifier == mainWindowIdentifier }) ?? windows.first
    }

    private static func allMainWindows() -> [NSWindow] {
        NSApp.windows.filter(isMainAppWindow)
    }

    private static func orderOutAuxiliaryWindows() {
        for window in NSApp.windows where !isMainAppWindow(window) {
            if window is NSPanel || window.level == .popUpMenu || window.level == .statusBar {
                window.orderOut(nil)
            }
        }
    }

    private static func isMainAppWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else { return false }
        if window is NSPanel { return false }
        if window.level == .popUpMenu || window.level == .statusBar { return false }
        let className = window.className
        if className.contains("StatusBar") || className.contains("MenuBarExtra") { return false }
        return true
    }
}

// MARK: - Закрытие главного окна → скрыть, не завершать приложение

@MainActor
private final class MainWindowCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainWindowVisibility.enterMenuBarOnlyMode()
        return false
    }

    // Страховка: если SwiftUI показал окно во время тихого запуска — немедленно прячем.
    func windowDidBecomeMain(_ notification: Notification) {
        suppressIfNeeded(notification.object as? NSWindow)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        suppressIfNeeded(notification.object as? NSWindow)
    }

    private func suppressIfNeeded(_ window: NSWindow?) {
        guard AppLaunchMode.suppressMainWindow, let window else { return }
        window.orderOut(nil)
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - SwiftUI bridge

/// Пробрасывает `openWindow` в `MainWindowVisibility` для вызова из AppDelegate.
struct OpenWindowRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                MainWindowVisibility.registerOpenWindow {
                    openWindow(id: MainWindowVisibility.windowID)
                }
            }
    }
}
