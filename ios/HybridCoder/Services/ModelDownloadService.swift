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

            try fm.createDirectory(at: modelDir.appendingPathComponent("model.mlmodelc/analytics"), withIntermediateDirectories: true)
            try fm.createDirectory(at: tokenizerDir, withIntermediateDirectories: true)

            let modelFiles = entry.files.filter { $0.localPath.contains("model.mlmodelc") }
            let tokenizerFiles = entry.files.filter { !$0.localPath.contains("model.mlmodelc") }
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
        guard fm.fileExists(atPath: compiledModel.path) else {
            throw DownloadError.fileCorrupt("model.mlmodelc")
        }

        let tokenizerDir = registry.downloadedTokenizerDirectory(for: modelID)
        let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "vocab.json", "merges.txt"]
        for expectedFile in tokenizerFiles {
            let path = tokenizerDir.appendingPathComponent(expectedFile).path
            guard fm.fileExists(atPath: path) else {
                throw DownloadError.fileCorrupt(expectedFile)
            }
        }

        try validateArtifactMetadata(modelID: modelID, modelDir: modelDir, tokenizerDir: tokenizerDir)
    }

    private static func validateArtifactMetadata(modelID: String, modelDir: URL, tokenizerDir: URL) throws {
        let tokenizerConfigURL = tokenizerDir.appendingPathComponent("tokenizer_config.json")
        let tokenizerConfig = try loadJSONDictionary(from: tokenizerConfigURL, source: "tokenizer_config.json")

        let tokenizerIDCandidates = collectStringValues(
            from: tokenizerConfig,
            keys: ["name_or_path", "_name_or_path", "model_id", "tokenizer_name", "tokenizer_id"]
        )
        guard tokenizerIDCandidates.contains(where: { matchesModelIdentifier($0, expected: modelID) }) else {
            throw DownloadError.metadataMismatch(
                file: "tokenizer_config.json",
                expected: modelID,
                found: tokenizerIDCandidates.joined(separator: ", ")
            )
        }

        let modelMetadataURL = modelDir
            .appendingPathComponent("model.mlmodelc")
            .appendingPathComponent("metadata.json")
        let modelMetadata = try loadJSONDictionary(from: modelMetadataURL, source: "model.mlmodelc/metadata.json")

        let modelIDCandidates = collectStringValues(
            from: modelMetadata,
            keys: ["model_id", "source_model", "hf_model_id", "_name_or_path", "name_or_path"]
        )
        guard modelIDCandidates.contains(where: { matchesModelIdentifier($0, expected: modelID) }) else {
            throw DownloadError.metadataMismatch(
                file: "model.mlmodelc/metadata.json",
                expected: modelID,
                found: modelIDCandidates.joined(separator: ", ")
            )
        }
    }

    private static func matchesModelIdentifier(_ value: String, expected: String) -> Bool {
        let normalized = value.lowercased()
        let expectedNormalized = expected.lowercased()
        return normalized == expectedNormalized || normalized.contains(expectedNormalized) || normalized.contains("codebert")
    }

    private static func loadJSONDictionary(from url: URL, source: String) throws -> [String: Any] {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = json as? [String: Any] else {
                throw DownloadError.fileCorrupt(source)
            }
            return dictionary
        } catch let error as DownloadError {
            throw error
        } catch {
            throw DownloadError.metadataUnreadable(source, error.localizedDescription)
        }
    }

    private static func collectStringValues(from dictionary: [String: Any], keys: [String]) -> [String] {
        var values: [String] = []
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                values.append(value)
            }
        }
        return values
    }

    nonisolated enum DownloadError: Error, LocalizedError, Sendable {
        case modelNotDownloaded(String)
        case httpError(Int, String)
        case fileCorrupt(String)
        case metadataMismatch(file: String, expected: String, found: String)
        case metadataUnreadable(String, String)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotDownloaded(let details):
                return details
            case .httpError(let code, let file):
                return "HTTP \(code) downloading \(file). Check your network connection and try again."
            case .fileCorrupt(let file):
                return "Downloaded file '\(file)' appears corrupt. Delete and re-download."
            case .metadataMismatch(let file, let expected, let found):
                let foundText = found.isEmpty ? "missing model identifier fields" : found
                return "Metadata mismatch in '\(file)'. Expected '\(expected)', found '\(foundText)'."
            case .metadataUnreadable(let file, let reason):
                return "Unable to parse '\(file)' for validation: \(reason)"
            }
        }
    }
}
