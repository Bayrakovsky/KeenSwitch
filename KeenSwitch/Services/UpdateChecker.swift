import AppKit
import Foundation
import OSLog

// MARK: - UpdateChecker
//
// Проверяет GitHub Releases API и устанавливает обновление автоматически:
// скачивает .zip ассет, распаковывает во временную папку, заменяет текущий
// .app через shell-скрипт и перезапускает приложение.
//
// GitHub Release должен содержать ассет вида KeenSwitch.zip с файлом KeenSwitch.app внутри.

@Observable
@MainActor
final class UpdateChecker {

    enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case available(current: String, latest: String, assetId: Int)
        case downloading(progress: Double)
        case installing
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.installing, .installing): true
            case (.upToDate(let a), .upToDate(let b)): a == b
            case (.available(let a, let b, let c), .available(let d, let e, let f)): a == d && b == e && c == f
            case (.downloading(let a), .downloading(let b)): a == b
            case (.failed(let a), .failed(let b)): a == b
            default: false
            }
        }
    }

    private(set) var state: State = .idle

    private let repoSlug = AppConfiguration.githubRepoSlug
    private let logger = Logger(subsystem: "com.bayrakovskiy.KeenSwitch", category: "Updater")
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Public API

    func checkForUpdates() async {
        logger.info("Проверка обновлений…")
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            let current = Bundle.main.appVersion
            let latest = release.tagName.trimmingPrefix("v")

            guard String(latest).isNewerVersionThan(current) else {
                logger.info("Версия актуальна: \(current)")
                state = .upToDate(version: current)
                return
            }

            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                logger.warning("Релиз \(String(latest)) не содержит .zip ассета")
                if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                state = .failed(L10n.tr("No Download Asset"))
                return
            }

            logger.info("Доступна новая версия: \(String(latest)) (текущая: \(current)), assetId: \(asset.id)")
            state = .available(current: current, latest: String(latest), assetId: asset.id)
        } catch {
            logger.error("Ошибка проверки обновлений: \(error.localizedDescription)")
            state = .failed(error.userFacingMessage)
        }
    }

    func downloadAndInstall(assetId: Int) async {
        logger.info("Начало загрузки обновления, assetId: \(assetId)")
        state = .downloading(progress: 0)
        do {
            let zipURL = try await download(assetId: assetId)
            logger.info("Архив загружен: \(zipURL.path)")
            state = .installing
            try await install(zipURL: zipURL)
        } catch {
            logger.error("Ошибка установки обновления: \(error.localizedDescription)")
            state = .failed(error.userFacingMessage)
        }
    }

    // MARK: - Private: network

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // Авторизация по токену GitHub — нужна была пока репозиторий был приватным.
        // После публикации не требуется: публичный Releases API доступен анонимно.
        // Оставлено закомментированным на случай возврата к приватному режиму.
        // if let token = try? KeychainStore.loadPassword(account: KeychainStore.githubTokenAccount),
        //    !token.isEmpty {
        //     request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func download(assetId: Int) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeenSwitch-update.zip")
        try? FileManager.default.removeItem(at: destination)

        // GitHub API asset download: возвращает 302 на S3, URLSession следует редиректу.
        // Accept: application/octet-stream обязателен — без него вернётся JSON.
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repoSlug)/releases/assets/\(assetId)")!)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // Авторизация по токену GitHub — см. комментарий в fetchLatestRelease().
        // Для публичного репозитория не требуется.
        // if let token = try? KeychainStore.loadPassword(account: KeychainStore.githubTokenAccount),
        //    !token.isEmpty {
        //     request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // }

        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: request) { localURL, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let localURL else {
                    continuation.resume(throwing: UpdateError.downloadFailed)
                    return
                }
                do {
                    try FileManager.default.moveItem(at: localURL, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    self?.state = .downloading(progress: fraction)
                }
            }
            downloadTask = task
            task.resume()
        }
    }

    // MARK: - Private: install

    private func install(zipURL: URL) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeenSwitch-update-extracted")
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Распаковываем через ditto — сохраняет extended attributes и структуру .app
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", "--sequesterRsrc", zipURL.path, tempDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw UpdateError.unzipFailed
        }

        // Ищем .app внутри (рекурсивно — может лежать в подпапке)
        let enumerator = FileManager.default.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var newAppURL: URL?
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "app" {
                newAppURL = url
                break
            }
        }
        guard let newAppURL else { throw UpdateError.noAppBundle }

        // Проверяем code signature нового бандла перед установкой.
        // Это защищает от повреждённых или подменённых архивов.
        try verifyCodeSignature(appURL: newAppURL)

        let currentAppPath = Bundle.main.bundleURL.path
        let newAppPath = newAppURL.path
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("keenswitch-update.log").path
        let pid = ProcessInfo.processInfo.processIdentifier

        // Установка через shell-скрипт: приложение не может заменить себя пока работает.
        // Скрипт запускается отдельным процессом и:
        //   1. Ждёт завершения текущего процесса (по PID, с таймаутом 10с).
        //   2. Заменяет .app через ditto (сохраняет extended attributes и структуру бандла).
        //   3. Перезапускает новую версию и убирает временные файлы.
        let script = """
        #!/bin/bash
        exec > '\(logPath)' 2>&1
        set -e

        # Ожидаем завершения текущего процесса (максимум 10 секунд).
        DEADLINE=$(( $(date +%s) + 10 ))
        while kill -0 \(pid) 2>/dev/null; do
            [ $(date +%s) -ge $DEADLINE ] && break
            sleep 0.3
        done

        rm -rf '\(currentAppPath)'
        /usr/bin/ditto '\(newAppPath)' '\(currentAppPath)'
        xattr -cr '\(currentAppPath)'
        open '\(currentAppPath)'
        rm -rf '\(tempDir.path)'
        rm -f '\(zipURL.path)'
        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keenswitch-updater.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptURL.path]
        try chmod.run()
        chmod.waitUntilExit()

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        launcher.standardOutput = nil
        launcher.standardError = nil
        try launcher.run()
        logger.info("Скрипт установки запущен (PID \(pid)), завершаем приложение…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppTermination.quit()
        }
    }

    /// Проверяет code signature бандла через codesign --verify.
    /// Выбрасывает UpdateError.invalidSignature если подпись отсутствует или повреждена.
    private func verifyCodeSignature(appURL: URL) throws {
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", appURL.path]
        verify.standardOutput = nil
        verify.standardError = nil
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else {
            logger.warning("Проверка подписи не прошла для \(appURL.lastPathComponent)")
            throw UpdateError.invalidSignature
        }
        logger.info("Подпись бандла \(appURL.lastPathComponent) корректна")
    }
}

// MARK: - Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

// MARK: - Helpers

private enum UpdateError: LocalizedError {
    case httpError(Int)
    case downloadFailed
    case unzipFailed
    case noAppBundle
    case invalidSignature

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "HTTP \(code)"
        case .downloadFailed: L10n.tr("Update Check Failed")
        case .unzipFailed: L10n.tr("Unzip Failed")
        case .noAppBundle: L10n.tr("No Download Asset")
        case .invalidSignature: L10n.tr("Invalid Signature")
        }
    }
}

private extension Substring {
    func trimmingPrefix(_ prefix: Character) -> Substring {
        hasPrefix(String(prefix)) ? dropFirst() : self
    }
}
