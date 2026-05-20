// MARK: - AppConfiguration
//
// Константы, которые нужно изменить при форке репозитория.
// Все значения здесь — единственное место, где требуется правка.

enum AppConfiguration {
    // GitHub-репозиторий в формате «owner/repo».
    // Используется UpdateChecker для поиска релизов через GitHub Releases API.
    // При форке замените на свой: «yourname/KeenSwitch».
    static let githubRepoSlug = "Bayrakovsky/KeenSwitch"
}
