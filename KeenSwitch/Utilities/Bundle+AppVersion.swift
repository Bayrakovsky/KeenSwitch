import Foundation

extension Bundle {
    /// Версия приложения из CFBundleShortVersionString, «0.0.0» если не задана.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
