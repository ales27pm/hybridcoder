import Foundation

@Observable
@MainActor
final class ModelDownloadService {

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

            let modelFiles = entry.files.filter { $0.localPath.contains("model.mlmodelc") || $0.localPath.contains("model.mlpackage") }
            let tokenizerFiles = entry.files.filter { !$0.localPath.contains("model.mlmodelc") && !$0.localPath.contains("model.mlpackage") }
            let allFiles = modelFiles.map { (modelDir, $0) } + tokenizerFiles.map { (tokenizerDir, $0) }

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
                    completed += 1
                    updateProgress(completed: completed, total: totalCount, modelID: modelID)
                    continue
                }

                let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)

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

            try Self.validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry)
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
        (try? validateDownloadedAssetsOrThrow(modelID: modelID, registry: registry)) != nil
    }

    private static func validateDownloadedAssetsOrThrow(modelID: String, registry: ModelRegistry) throws {
        let fm = FileManager.default

        let modelDir = registry.downloadedModelDirectory(for: modelID)
        let compiledModel = modelDir.appendingPathComponent("model.mlmodelc")
        let packageModel = modelDir.appendingPathComponent("model.mlpackage")
        guard fm.fileExists(atPath: compiledModel.path) || fm.fileExists(atPath: packageModel.path) else {
            throw DownloadError.fileCorrupt("model.mlmodelc or model.mlpackage")
        }

        let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)
        let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "special_tokens_map.json"]
        for expectedFile in tokenizerFiles {
            let path = tokenizerDir.appendingPathComponent(expectedFile).path
            guard fm.fileExists(atPath: path) else {
                throw DownloadError.fileCorrupt(expectedFile)
            }
        }
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
                return "HTTP \(code) downloading \(file). Check your network connection and try again."
            case .fileCorrupt(let file):
                return "Downloaded file '\(file)' appears corrupt. Delete and re-download."
            }
        }
    }
}
