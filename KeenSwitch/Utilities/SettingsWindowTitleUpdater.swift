#if os(macOS)
import AppKit
import SwiftUI

// MARK: - SettingsWindowTitleUpdater
//
// Заголовок окна Settings в SwiftUI по умолчанию системный («App Settings» / «Настройки приложения»)
// и не следует выбранному языку в приложении — задаём title окна явно.

struct SettingsWindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyTitle(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyTitle(from: nsView)
    }

    private func applyTitle(from view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}

extension View {
    func settingsWindowTitle(_ title: String) -> some View {
        background(SettingsWindowTitleUpdater(title: title))
    }
}
#endif
