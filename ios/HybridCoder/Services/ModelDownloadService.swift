import Foundation
import OSLog

@Observable
@MainActor
final class ModelDownloadService {
    private enum TokenStore {
        static let huggingFaceTokenKey = "models.huggingface.token"
    }

    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadError: String?
    private(set) var downloadErrorModelID: String?
    private(set) var shouldSuggestTokenInput: Bool = false

    private let registry: ModelRegistry
    private let bookmarkService: BookmarkService
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hybridcoder",
        category: "ModelDownloadService"
    )

    init(registry: ModelRegistry, bookmarkService: BookmarkService = BookmarkService()) {
        self.registry = registry
        self.bookmarkService = bookmarkService
        BundledEmbeddingAssets.migrateFromDocumentsIfNeeded()
        Task { [weak self] in
            guard let self else { return }
            await self.refreshInstallState(modelID: registry.activeEmbeddingModelID)
            await self.refreshInstallState(modelID: registry.activeGenerationModelID)
            await self.refreshInstallState(modelID: registry.activeCodeGenerationModelID)
        }
    }

    var activeEmbeddingModelID: String {
        registry.activeEmbeddingModelID
    }

    var isModelReady: Bool {
        registry.entry(for: activeEmbeddingModelID)?.installState == .installed
    }

    var huggingFaceToken: String {
        UserDefaults.standard.string(forKey: TokenStore.huggingFaceTokenKey) ?? ""
    }

    func setHuggingFaceToken(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: TokenStore.huggingFaceTokenKey)
        } else {
            UserDefaults.standard.set(cleaned, forKey: TokenStore.huggingFaceTokenKey)
        }

        // User acted on auth guidance (save or clear), so hide stale token prompts/errors.
        shouldSuggestTokenInput = false
        downloadError = nil
        downloadErrorModelID = nil
    }

    func refreshInstallState(modelID: String) async {
        do {
            try registry.ensureExternalModelsDirectoryExists()
            try registry.migrateLegacyExternalModelsIfNeeded()
        } catch {
            logger.error("Failed to prepare local GGUF storage: \(error.localizedDescription, privacy: .private)")
            let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
            let fallbackReady = registry.isModelInstalledInExternalModelsFolder(
                modelID: modelID,
                preferredRoot: preferredRoot
            )
            registry.setInstallState(for: modelID, fallbackReady ? .installed : .notInstalled)
            if fallbackReady {
                downloadError = nil
                downloadErrorModelID = nil
            } else {
                downloadError = "Failed to prepare local Models folder. Verify Files > On My iPhone > Hybrid Coder > Models/ is accessible."
                downloadErrorModelID = modelID
            }
            shouldSuggestTokenInput = false
            return
        }
        let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
        let isReady = registry.isModelInstalledInExternalModelsFolder(
            modelID: modelID,
            preferredRoot: preferredRoot
        )
        registry.setInstallState(for: modelID, isReady ? .installed : .notInstalled)
        if isReady {
            downloadError = nil
            downloadErrorModelID = nil
            shouldSuggestTokenInput = false
        }
    }

    func downloadIfNeeded() async {
        if isModelReady {
            return
        }
        await download(modelID: activeEmbeddingModelID)
    }

    func download(modelID: String? = nil) async {
        let modelID = modelID ?? activeEmbeddingModelID
        guard !isDownloading else { return }
        guard let entry = registry.entry(for: modelID) else { return }
        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        downloadErrorModelID = nil
        shouldSuggestTokenInput = false
        registry.setInstallState(for: modelID, .downloading(progress: 0))

        defer {
            isDownloading = false
        }

        do {
            try registry.ensureExternalModelsDirectoryExists()
            try registry.migrateLegacyExternalModelsIfNeeded()
            let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
            let isReady = registry.isModelInstalledInExternalModelsFolder(
                modelID: modelID,
                preferredRoot: preferredRoot
            )
            if isReady {
                registry.setInstallState(for: modelID, .installed)
                downloadError = nil
                downloadErrorModelID = nil
                downloadProgress = 1.0
                return
            }

            if let remoteBaseURL = entry.remoteBaseURL {
                try await downloadExternalGGUFModel(
                    modelID: modelID,
                    entry: entry,
                    remoteBaseURL: remoteBaseURL,
                    preferredRoot: preferredRoot
                )
            } else {
                throw DownloadError.modelNotDownloaded(
                    "Local llama.cpp GGUF model not found. Place the file in Files > On My iPhone > Hybrid Coder > Models/, then tap Refresh to validate."
                )
            }

            try await Self.validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry)
            registry.setInstallState(for: modelID, .installed)
            downloadError = nil
            downloadErrorModelID = nil
            downloadProgress = 1.0
        } catch is CancellationError {
            downloadError = "Download was cancelled."
            downloadErrorModelID = modelID
            registry.setInstallState(for: modelID, .notInstalled)
        } catch let error as DownloadError {
            downloadError = error.localizedDescription
            downloadErrorModelID = modelID
            shouldSuggestTokenInput = error.shouldSuggestHuggingFaceTokenInput
            logger.error("DownloadError modelID=\(modelID, privacy: .public) details=\(error.triageSummary, privacy: .private)")
            registry.setInstallState(for: modelID, .notInstalled)
        } catch {
            logger.error("Failed to prepare/download local GGUF storage: \(error.localizedDescription, privacy: .private)")
            let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
            let fallbackReady = registry.isModelInstalledInExternalModelsFolder(
                modelID: modelID,
                preferredRoot: preferredRoot
            )
            registry.setInstallState(for: modelID, fallbackReady ? .installed : .notInstalled)
            if fallbackReady {
                downloadError = nil
                downloadErrorModelID = nil
            } else {
                downloadError = "Failed to prepare local Models folder. Verify Files > On My iPhone > Hybrid Coder > Models/ is accessible."
                downloadErrorModelID = modelID
            }
        }
    }

    private func downloadExternalGGUFModel(
        modelID: String,
        entry: ModelRegistry.Entry,
        remoteBaseURL: String,
        preferredRoot: URL?
    ) async throws {
        let fm = FileManager.default
        let targetRoot = registry.preferredExternalModelsRoot(preferredRoot: preferredRoot)
        try fm.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        let totalCount = Double(entry.files.count)
        var completed = 0.0
        for file in entry.files {
            try Task.checkCancellation()
            let localURL = targetRoot.appendingPathComponent(file.localPath, isDirectory: false)
            if fm.fileExists(atPath: localURL.path(percentEncoded: false)) {
                completed += 1
                updateProgress(completed: completed, total: totalCount, modelID: modelID)
                continue
            }

            guard let remoteURL = URL(string: "\(remoteBaseURL)/\(file.remotePath)") else {
                throw DownloadError.modelNotDownloaded("Invalid remote URL for \(file.remotePath)")
            }
            var request = URLRequest(url: remoteURL)
            if remoteURL.host?.contains("huggingface.co") == true {
                let token = huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw DownloadError.httpError(
                    statusCode: code,
                    remotePath: file.remotePath,
                    modelID: modelID,
                    repoBaseURL: remoteBaseURL
                )
            }

            let parentDir = localURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path(percentEncoded: false)) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: localURL.path(percentEncoded: false)) {
                try fm.removeItem(at: localURL)
            }
            try fm.moveItem(at: tempURL, to: localURL)

            completed += 1
            updateProgress(completed: completed, total: totalCount, modelID: modelID)
        }
    }

    func deleteDownloadedModels(modelID: String? = nil) async {
        let modelID = modelID ?? activeEmbeddingModelID
        let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
        registry.deleteCodeGenerationModelAssets(modelID: modelID, preferredRoot: preferredRoot)
        registry.setInstallState(for: modelID, .notInstalled)
        registry.setLoadState(for: modelID, .unloaded)
        downloadProgress = 0
        downloadError = nil
        downloadErrorModelID = nil
    }

    func downloadError(for modelID: String) -> String? {
        guard downloadErrorModelID == modelID else { return nil }
        return downloadError
    }

    private func updateProgress(completed: Double, total: Double, modelID: String) {
        let progress = completed / max(total, 1)
        downloadProgress = progress
        registry.setInstallState(for: modelID, .downloading(progress: progress))
    }

    private static func isInvalidGGUFPayload(at url: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), data.isEmpty == false else {
                return true
            }

            let htmlProbeLength = min(data.count, 1024)
            if htmlProbeLength > 0,
               let prefix = String(data: data.prefix(htmlProbeLength), encoding: .utf8)?.lowercased() {
                if prefix.contains("<html") || prefix.contains("<!doctype html") {
                    return true
                }
            }

            let ggufMagic = Data([0x47, 0x47, 0x55, 0x46]) // GGUF
            guard data.count >= ggufMagic.count else {
                return true
            }
            return !data.starts(with: ggufMagic)
        }.value
    }

    static func validateDownloadedAssets(modelID: String, registry: ModelRegistry) async -> Bool {
        do {
            try await validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry)
            return true
        } catch {
            return false
        }
    }

    private static func validateDownloadedAssetsOrThrow(modelID: String, registry: ModelRegistry) async throws {
        guard let entry = registry.entry(for: modelID) else {
            throw DownloadError.fileCorrupt("Missing model registry entry for \(modelID)")
        }
        let preferredRoot = registry.preferredExternalModelsRoot()
        let fm = FileManager.default
        for expectedFile in entry.files {
            let url = preferredRoot.appendingPathComponent(expectedFile.localPath, isDirectory: false)
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw DownloadError.fileCorrupt(expectedFile.localPath)
            }
            if await isInvalidGGUFPayload(at: url) {
                try? fm.removeItem(at: url)
                throw DownloadError.fileCorrupt("Invalid GGUF artifact: \(expectedFile.localPath)")
            }
        }
    }

    nonisolated enum DownloadError: Error, LocalizedError, Sendable {
        case modelNotDownloaded(String)
        case httpError(statusCode: Int, remotePath: String, modelID: String?, repoBaseURL: String?)
        case fileCorrupt(String)

        nonisolated var isAuthorizationError: Bool {
            if case .httpError(statusCode: let code, remotePath: _, modelID: _, repoBaseURL: _) = self {
                return code == 401 || code == 403
            }
            return false
        }

        nonisolated var shouldSuggestHuggingFaceTokenInput: Bool {
            isAuthorizationError && isHuggingFaceRepository
        }

        nonisolated var isHuggingFaceRepository: Bool {
            guard case .httpError(statusCode: _, remotePath: _, modelID: _, repoBaseURL: let repoBaseURL) = self,
                  let repoBaseURL,
                  let host = URL(string: repoBaseURL)?.host?.lowercased() else {
                return false
            }
            return host == "huggingface.co" || host.hasSuffix(".huggingface.co")
        }

        nonisolated var repoHostForDisplay: String? {
            guard case .httpError(statusCode: _, remotePath: _, modelID: _, repoBaseURL: let repoBaseURL) = self,
                  let repoBaseURL else {
                return nil
            }
            return URL(string: repoBaseURL)?.host
        }

        nonisolated var triageSummary: String {
            switch self {
            case .modelNotDownloaded(let details):
                return "modelNotDownloaded: \(details)"
            case .httpError(statusCode: let code, remotePath: let remotePath, modelID: let modelID, repoBaseURL: let repoBaseURL):
                return "httpError status=\(code) remotePath=\(remotePath) modelID=\(modelID ?? "nil") repoBaseURL=\(repoBaseURL ?? "nil")"
            case .fileCorrupt(let file):
                return "fileCorrupt: \(file)"
            }
        }

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotDownloaded(let details):
                return details
            case .httpError(statusCode: let code, remotePath: let file, modelID: _, repoBaseURL: _):
                if code == 404 {
                    return "HTTP 404 downloading \(file). The file, repository, or remote path could not be found."
                }
                if code == 401 || code == 403 {
                    if shouldSuggestHuggingFaceTokenInput {
                        return "HTTP \(code) downloading \(file). Authentication failed or access is denied. Add a valid Hugging Face token and retry."
                    }
                    if let repoHostForDisplay {
                        return "HTTP \(code) downloading \(file) from \(repoHostForDisplay). Authentication failed or access is denied."
                    }
                    return "HTTP \(code) downloading \(file). Authentication failed or access is denied."
                }
                if (500...599).contains(code) {
                    return "HTTP \(code) downloading \(file). The server reported a temporary error. Retry in a moment."
                }
                return "HTTP \(code) downloading \(file). The request failed."
            case .fileCorrupt(let file):
                return "Downloaded file '\(file)' appears corrupt. Delete and re-download."
            }
        }
    }
}
