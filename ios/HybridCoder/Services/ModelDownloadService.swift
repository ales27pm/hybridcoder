import Foundation
import CoreML

@Observable
@MainActor
final class ModelDownloadService {
    private enum TokenStore {
        static let huggingFaceTokenKey = "models.huggingface.token"
    }

    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadError: String?

    private let registry: ModelRegistry

    init(registry: ModelRegistry) {
        self.registry = registry
        refreshInstallState(modelID: registry.activeEmbeddingModelID)
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
    }

    func refreshInstallState(modelID: String) {
        let isReady = Self.validateDownloadedAssets(modelID: modelID, registry: registry)
        registry.setInstallState(for: modelID, isReady ? .installed : .notInstalled)
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
        registry.setInstallState(for: modelID, .downloading(progress: 0))

        do {
            let fm = FileManager.default
            let modelDir = registry.downloadedModelDirectory(for: modelID)
            let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)

            try fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: tokenizerDir, withIntermediateDirectories: true)

            let modelPackageFiles = entry.files.filter { $0.localPath == "model.mlpackage" }
            let tokenizerFiles = entry.files.filter { !$0.localPath.contains("model.mlmodelc") && $0.localPath != "model.mlpackage" }
            let allFiles = modelPackageFiles.map { (modelDir, $0) } + tokenizerFiles.map { (tokenizerDir, $0) }

            let totalCount = Double(allFiles.count + 1) // +1 for compile step
            var completed = 0.0

            for (baseDir, file) in allFiles {
                try Task.checkCancellation()
                guard let remoteBaseURL = entry.remoteBaseURL else {
                    throw DownloadError.modelNotDownloaded("Model \(entry.displayName) does not support remote downloads.")
                }

                let remoteURL = URL(string: "\(remoteBaseURL)/\(file.remotePath)")!
                let localURL = baseDir.appendingPathComponent(file.localPath)

                if fm.fileExists(atPath: localURL.path) {
                    completed += 1
                    updateProgress(completed: completed, total: totalCount, modelID: modelID)
                    continue
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
                    throw DownloadError.httpError(code, file.remotePath)
                }

                let parentDir = localURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parentDir.path) {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }

                if fm.fileExists(atPath: localURL.path) {
                    try fm.removeItem(at: localURL)
                }
                try fm.moveItem(at: tempURL, to: localURL)

                completed += 1
                updateProgress(completed: completed, total: totalCount, modelID: modelID)
            }

            try Self.validateDownloadedAssetsPreCompileOrThrow(modelID: modelID, registry: registry)
            try Self.compileModelPackage(modelID: modelID, registry: registry)
            completed += 1
            updateProgress(completed: completed, total: totalCount, modelID: modelID)
            try Self.validateDownloadedAssetsPostCompileOrThrow(modelID: modelID, registry: registry)
            registry.setInstallState(for: modelID, .installed)
        } catch is CancellationError {
            downloadError = "Download was cancelled."
            registry.setInstallState(for: modelID, .notInstalled)
        } catch let error as DownloadError {
            downloadError = error.localizedDescription
            registry.setInstallState(for: modelID, .notInstalled)
        } catch {
            downloadError = "Download failed: \(error.localizedDescription)"
            registry.setInstallState(for: modelID, .notInstalled)
        }

        isDownloading = false
    }

    func deleteDownloadedModels(modelID: String? = nil) {
        let modelID = modelID ?? activeEmbeddingModelID
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

    static func validateDownloadedAssets(modelID: String, registry: ModelRegistry) -> Bool {
        (try? validateDownloadedAssetsPreCompileOrThrow(modelID: modelID, registry: registry)) != nil &&
        (try? validateDownloadedAssetsPostCompileOrThrow(modelID: modelID, registry: registry)) != nil
    }

    private static func validateDownloadedAssetsPreCompileOrThrow(modelID: String, registry: ModelRegistry) throws {
        let fm = FileManager.default
        guard let entry = registry.entry(for: modelID) else {
            throw DownloadError.fileCorrupt("Missing model registry entry for \(modelID)")
        }

        let modelDir = registry.downloadedModelDirectory(for: modelID)
        let packageModel = modelDir.appendingPathComponent("model.mlpackage")
        guard fm.fileExists(atPath: packageModel.path) else {
            throw DownloadError.fileCorrupt("model.mlpackage")
        }

        let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)
        let tokenizerFiles = entry.files
            .filter { !$0.localPath.contains("model.mlmodelc") && $0.localPath != "model.mlpackage" }
            .map(\.localPath)
        for expectedFile in tokenizerFiles {
            let path = tokenizerDir.appendingPathComponent(expectedFile).path
            guard fm.fileExists(atPath: path) else {
                throw DownloadError.fileCorrupt(expectedFile)
            }
        }
    }

    private static func validateDownloadedAssetsPostCompileOrThrow(modelID: String, registry: ModelRegistry) throws {
        let fm = FileManager.default
        let modelDir = registry.downloadedModelDirectory(for: modelID)
        let compiledModel = modelDir.appendingPathComponent("model.mlmodelc")

        guard fm.fileExists(atPath: compiledModel.path) else {
            throw DownloadError.fileCorrupt("model.mlmodelc")
        }

        do {
            _ = try MLModel(contentsOf: compiledModel)
        } catch {
            throw DownloadError.fileCorrupt("model.mlmodelc (unloadable)")
        }
    }

    private static func compileModelPackage(modelID: String, registry: ModelRegistry) throws {
        let fm = FileManager.default
        let modelDir = registry.downloadedModelDirectory(for: modelID)
        let packageModel = modelDir.appendingPathComponent("model.mlpackage")
        let compiledDestination = modelDir.appendingPathComponent("model.mlmodelc")

        let compiledOutput = try MLModel.compileModel(at: packageModel)

        if fm.fileExists(atPath: compiledDestination.path) {
            try fm.removeItem(at: compiledDestination)
        }
        try fm.moveItem(at: compiledOutput, to: compiledDestination)
    }

    nonisolated enum DownloadError: Error, LocalizedError, Sendable {
        case modelNotDownloaded(String)
        case httpError(Int, String)
        case fileCorrupt(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotDownloaded(let details):
                return details
            case .httpError(let code, let file):
                if code == 401 {
                    return "HTTP 401 downloading \(file). Add your Hugging Face token in the Models tab and retry."
                }
                return "HTTP \(code) downloading \(file). Check your network connection and try again."
            case .fileCorrupt(let file):
                return "Downloaded file '\(file)' appears corrupt. Delete and re-download."
            }
        }
    }
}
