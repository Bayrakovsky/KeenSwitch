import AppKit
import SwiftUI

// MARK: - KeenSwitchMain
//
// Activation policy и SwiftUI Window-сцена: окно, созданное в .accessory, не получает glass.
// LSUIElement убран из Info.plist — политика задаётся здесь до KeenSwitchApp.main().

@main
enum KeenSwitchMain {
    static func main() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            AppLaunchMode.configureActivationPolicyAtLaunchIfNeeded()
        }
        KeenSwitchApp.main()
    }
}
