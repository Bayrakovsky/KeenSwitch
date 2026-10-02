import Foundation

nonisolated extension String {
    /// Сравнивает версии вида «1.2.3» с учётом числовых компонент.
    func isNewerVersionThan(_ other: String) -> Bool {
        compare(other, options: .numeric) == .orderedDescending
    }
}
