import SwiftUI

/// Иконка устройства: цветная, если в сети; серая, если офлайн.
struct DeviceIconView: View {
    let isOnline: Bool
    var size: Font = .title2

    var body: some View {
        Image(systemName: "desktopcomputer")
            .font(size)
            .foregroundStyle(isOnline ? Color.accentColor : Color.secondary)
            .symbolRenderingMode(isOnline ? .hierarchical : .monochrome)
    }
}
