#if os(macOS)
import AppKit
import ObjectiveC

// MARK: - StatusBarQuitMenuAttacher
//
// ПКМ по иконке MenuBarExtra → «Quit KeenSwitch», без замены панели на NSPanel.
// Тот же приём, что у классических NSStatusItem: sendAction на ЛКМ и ПКМ.

private enum StatusBarQuitAssociatedKeys {
    static var interceptorKey: UInt8 = 0
}

@MainActor
enum StatusBarQuitMenuAttacher {
    private static let statusItemTitle = "KeenSwitch"
    private static var installStarted = false
    private static weak var hookedButton: NSStatusBarButton?

    static func install() {
        guard !installStarted else { return }
        installStarted = true
        scheduleHookAttempt(retry: 0)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if hookedButton?.window == nil {
                    scheduleHookAttempt(retry: 0)
                }
            }
        }
    }

    private static func scheduleHookAttempt(retry: Int) {
        if attachToStatusBarButtonIfNeeded() { return }
        guard retry < 40 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scheduleHookAttempt(retry: retry + 1)
        }
    }

    @discardableResult
    private static func attachToStatusBarButtonIfNeeded() -> Bool {
        guard let button = findStatusBarButton() else { return false }
        if hookedButton === button,
           objc_getAssociatedObject(button, &StatusBarQuitAssociatedKeys.interceptorKey) != nil {
            return true
        }
        hookedButton = button

        let interceptor = StatusBarButtonInterceptor()
        objc_setAssociatedObject(
            button,
            &StatusBarQuitAssociatedKeys.interceptorKey,
            interceptor,
            .OBJC_ASSOCIATION_RETAIN
        )
        interceptor.install(on: button)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return true
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let className = window.className
            guard className.contains("StatusBar") || window.level == .statusBar else { continue }
            if let button = firstStatusBarButton(in: window.contentView), matchesOurItem(button) {
                return button
            }
        }
        return nil
    }

    private static func firstStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = firstStatusBarButton(in: subview) { return found }
        }
        return nil
    }

    private static func matchesOurItem(_ button: NSStatusBarButton) -> Bool {
        let title = button.accessibilityTitle()
            ?? button.accessibilityLabel()
            ?? button.toolTip
            ?? ""
        if title == statusItemTitle { return true }
        if let window = button.window,
           window.className.contains("StatusBar"),
           countStatusBarButtons(in: window.contentView) == 1 {
            return true
        }
        return false
    }

    private static func countStatusBarButtons(in view: NSView?) -> Int {
        guard let view else { return 0 }
        var count = view is NSStatusBarButton ? 1 : 0
        for subview in view.subviews {
            count += countStatusBarButtons(in: subview)
        }
        return count
    }

    static func showQuitMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: L10n.tr("Quit KeenSwitch"),
            action: #selector(QuitMenuTarget.quitApplication),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = QuitMenuTarget.shared
        menu.addItem(quitItem)
        let point = NSPoint(x: button.bounds.midX, y: button.bounds.minY)
        menu.popUp(positioning: quitItem, at: point, in: button)
    }
}

@MainActor
private final class StatusBarButtonInterceptor: NSObject {
    private weak var button: NSStatusBarButton?
    private weak var originalTarget: AnyObject?
    private var originalAction: Selector?

    func install(on button: NSStatusBarButton) {
        self.button = button
        originalTarget = button.target as AnyObject?
        originalAction = button.action
        button.target = self
        button.action = #selector(handleClick(_:))
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            performOriginalClick(on: sender)
            return
        }
        switch event.type {
        case .rightMouseUp, .rightMouseDown:
            StatusBarQuitMenuAttacher.showQuitMenu(for: sender)
        default:
            performOriginalClick(on: sender)
        }
    }

    private func performOriginalClick(on sender: NSStatusBarButton) {
        let savedTarget = sender.target
        let savedAction = sender.action
        sender.target = originalTarget
        sender.action = originalAction
        sender.performClick(nil)
        sender.target = savedTarget
        sender.action = savedAction
    }
}

@MainActor
private final class QuitMenuTarget: NSObject {
    static let shared = QuitMenuTarget()

    @objc func quitApplication() {
        AppTermination.quit()
    }
}
#endif
