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
    private(set) var shouldSuggestTokenInput: Bool = false

    private let registry: ModelRegistry
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hybridcoder",
        category: "ModelDownloadService"
    )

    init(registry: ModelRegistry) {
        self.registry = registry
        BundledEmbeddingAssets.migrateFromDocumentsIfNeeded()
        Task { [weak self] in
            guard let self else { return }
            await self.refreshInstallState(modelID: registry.activeEmbeddingModelID)
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
    }

    func refreshInstallState(modelID: String) async {
        if registry.entry(for: modelID)?.runtime == .llamaCppGGUF {
            let isReady = registry.isModelInstalledInExternalModelsFolder(modelID: modelID)
            registry.setInstallState(for: modelID, isReady ? .installed : .notInstalled)
            if isReady {
                downloadError = nil
                shouldSuggestTokenInput = false
            }
            return
        }

        let isReady = await Self.validateDownloadedAssets(modelID: modelID, registry: registry)
        registry.setInstallState(for: modelID, isReady ? .installed : .notInstalled)
        if isReady {
            downloadError = nil
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
        guard entry.runtime != .llamaCppGGUF else {
            downloadError = "llama.cpp models are loaded from Files > On My iPhone > HybridCoder > Models/."
            shouldSuggestTokenInput = false
            let isReady = registry.isModelInstalledInExternalModelsFolder(modelID: modelID)
            registry.setInstallState(for: modelID, isReady ? .installed : .notInstalled)
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        shouldSuggestTokenInput = false
        registry.setInstallState(for: modelID, .downloading(progress: 0))

        do {
            let fm = FileManager.default
            let modelDir = registry.downloadedModelDirectory(for: modelID)
            let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)

            try fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: tokenizerDir, withIntermediateDirectories: true)

            let allFiles = entry.files.map { file -> (URL, ModelRegistry.ModelFile) in
                let isModelFile = file.localPath.hasPrefix("model/")
                return (isModelFile ? modelDir : tokenizerDir, file)
            }

            let totalCount = Double(allFiles.count)
            var completed = 0.0

            for (baseDir, file) in allFiles {
                try Task.checkCancellation()
                guard let remoteBaseURL = entry.remoteBaseURL else {
                    throw DownloadError.modelNotDownloaded("Model \(entry.displayName) does not support remote downloads.")
                }

                let remoteURL = URL(string: "\(remoteBaseURL)/\(file.remotePath)")!
                let localURL = baseDir.appendingPathComponent(file.localPath)

                if fm.fileExists(atPath: localURL.path) {
                    let requiresValidation = Self.shouldRedownloadExistingFile(localURL: localURL, modelFile: file)
                    let hasInvalidJSON = requiresValidation
                        ? await Self.isInvalidTokenizerOrManifestJSON(at: localURL)
                        : false
                    let shouldRedownload = requiresValidation && hasInvalidJSON
                    if shouldRedownload {
                        do {
                            try fm.removeItem(at: localURL)
                            logger.warning("Removed invalid cached model artifact path=\(localURL.path, privacy: .private)")
                        } catch {
                            logger.error("Failed to remove invalid cached artifact path=\(localURL.path, privacy: .private) error=\(error.localizedDescription, privacy: .private)")
                            throw DownloadError.fileCorrupt("Failed to remove invalid cached file: \(file.localPath)")
                        }
                    } else {
                        completed += 1
                        updateProgress(completed: completed, total: totalCount, modelID: modelID)
                        continue
                    }
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
                        repoBaseURL: entry.remoteBaseURL
                    )
                }

                let parentDir = localURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parentDir.path) {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }

                if fm.fileExists(atPath: localURL.path) {
                    try fm.removeItem(at: localURL)
                }
                try fm.moveItem(at: tempURL, to: localURL)
                if Self.shouldValidateJSONArtifact(localPath: file.localPath),
                   await Self.isInvalidTokenizerOrManifestJSON(at: localURL) {
                    do {
                        try fm.removeItem(at: localURL)
                    } catch {
                        throw DownloadError.fileCorrupt("Downloaded invalid JSON artifact and failed cleanup: \(file.localPath)")
                    }
                    throw DownloadError.fileCorrupt("Downloaded invalid JSON artifact: \(file.localPath)")
                }

                completed += 1
                updateProgress(completed: completed, total: totalCount, modelID: modelID)
            }

            try await Self.validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry)
            registry.setInstallState(for: modelID, .installed)
        } catch is CancellationError {
            downloadError = "Download was cancelled."
            registry.setInstallState(for: modelID, .notInstalled)
        } catch let error as DownloadError {
            downloadError = error.localizedDescription
            shouldSuggestTokenInput = error.shouldSuggestHuggingFaceTokenInput
            logger.error("DownloadError modelID=\(modelID, privacy: .public) details=\(error.triageSummary, privacy: .private)")
            registry.setInstallState(for: modelID, .notInstalled)
        } catch {
            downloadError = "Download failed: \(error.localizedDescription)"
            logger.error("Unexpected download failure modelID=\(modelID, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            registry.setInstallState(for: modelID, .notInstalled)
        }

        isDownloading = false
    }

    func deleteDownloadedModels(modelID: String? = nil) {
        let modelID = modelID ?? activeEmbeddingModelID
        if registry.entry(for: modelID)?.runtime == .llamaCppGGUF {
            registry.deleteCodeGenerationModelAssets(modelID: modelID)
            registry.setInstallState(for: modelID, .notInstalled)
            registry.setLoadState(for: modelID, .unloaded)
            downloadProgress = 0
            downloadError = nil
            return
        }

        let fm = FileManager.default
        let modelDir = registry.downloadedModelDirectory(for: modelID)
        let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)
        try? fm.removeItem(at: modelDir)
        try? fm.removeItem(at: tokenizerDir)

        registry.setInstallState(for: modelID, .notInstalled)
        registry.setLoadState(for: modelID, .unloaded)
        downloadProgress = 0
        downloadError = nil
    }

    private func updateProgress(completed: Double, total: Double, modelID: String) {
        let progress = completed / max(total, 1)
        downloadProgress = progress
        registry.setInstallState(for: modelID, .downloading(progress: progress))
    }

    private static func shouldRedownloadExistingFile(localURL: URL, modelFile: ModelRegistry.ModelFile) -> Bool {
        // Guard against stale/corrupt cached tokenizer files (for example HTML error pages)
        // that can cause tokenizer decode failures while still passing existence checks.
        let name = localURL.lastPathComponent.lowercased()
        let jsonArtifactNames: Set<String> = [
            "tokenizer.json",
            "tokenizer_config.json",
            "special_tokens_map.json",
            "manifest.json",
            "metadata.json"
        ]

        if jsonArtifactNames.contains(name) { return true }

        // Fallback to model registry local path in case naming changes after move/rename.
        let registryPath = modelFile.localPath.lowercased()
        if registryPath.hasSuffix("tokenizer.json") ||
            registryPath.hasSuffix("tokenizer_config.json") ||
            registryPath.hasSuffix("special_tokens_map.json") ||
            registryPath.hasSuffix("manifest.json") ||
            registryPath.hasSuffix("metadata.json") { return true }

        return false
    }

    private static func shouldValidateJSONArtifact(localPath: String) -> Bool {
        let normalized = localPath.lowercased()
        return normalized.hasSuffix("tokenizer.json") ||
            normalized.hasSuffix("tokenizer_config.json") ||
            normalized.hasSuffix("special_tokens_map.json") ||
            normalized.hasSuffix("manifest.json") ||
            normalized.hasSuffix("metadata.json")
    }

    /// Validation tailored for tokenizer/manifest-style JSON artifacts:
    /// accepts only top-level JSON objects or arrays of objects.
    private static func isInvalidTokenizerOrManifestJSON(at url: URL) async -> Bool {
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

            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                return true
            }

            return !(json is [String: Any] || json is [[String: Any]])
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
        let fm = FileManager.default
        guard let entry = registry.entry(for: modelID) else {
            throw DownloadError.fileCorrupt("Missing model registry entry for \(modelID)")
        }

        if entry.runtime == .llamaCppGGUF {
            guard registry.isModelInstalledInExternalModelsFolder(modelID: modelID) else {
                throw DownloadError.fileCorrupt("Expected llama.cpp GGUF files in the external Models folder")
            }
            return
        }

        let modelDir = registry.downloadedModelDirectory(for: modelID)
        let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)
        for expectedFile in entry.files {
            let baseDir = expectedFile.localPath.hasPrefix("model/") ? modelDir : tokenizerDir
            let url = baseDir.appendingPathComponent(expectedFile.localPath)
            guard fm.fileExists(atPath: url.path) else {
                throw DownloadError.fileCorrupt(expectedFile.localPath)
            }
            if shouldValidateJSONArtifact(localPath: expectedFile.localPath),
               await isInvalidTokenizerOrManifestJSON(at: url) {
                try? fm.removeItem(at: url)
                throw DownloadError.fileCorrupt("Invalid JSON artifact: \(expectedFile.localPath)")
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
