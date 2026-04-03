import Foundation

@Observable
@MainActor
final class ModelDownloadService {

    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadError: String?
    private(set) var isModelReady: Bool = false

    private static let embeddingModelsDir = BundledEmbeddingAssets.embeddingModelsFolder
    private static let modelDirName = BundledEmbeddingAssets.modelDirectoryName
    private static let tokenizerDirName = BundledEmbeddingAssets.tokenizerDirectoryName
    private static let canonicalModelID = "microsoft/codebert-base"
    private static let canonicalModelLabel = "CodeBERT (microsoft/codebert-base)"

    private static let modelFiles: [(remote: String, local: String)] = [
        ("model.mlmodelc/model.mil", "model.mlmodelc/model.mil"),
        ("model.mlmodelc/coremldata.bin", "model.mlmodelc/coremldata.bin"),
        ("model.mlmodelc/metadata.json", "model.mlmodelc/metadata.json"),
        ("model.mlmodelc/analytics/coremldata.bin", "model.mlmodelc/analytics/coremldata.bin")
    ]

    private static let tokenizerFiles: [(remote: String, local: String)] = [
        ("tokenizer.json", "tokenizer.json"),
        ("tokenizer_config.json", "tokenizer_config.json"),
        ("special_tokens_map.json", "special_tokens_map.json"),
        ("vocab.json", "vocab.json"),
        ("merges.txt", "merges.txt")
    ]

    private static let huggingFaceBaseURL = "https://huggingface.co/nickmuchi/codebert-base-coreml/resolve/main"

    nonisolated static var downloadedModelsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(embeddingModelsDir)
    }

    nonisolated static var downloadedModelDir: URL {
        downloadedModelsRoot.appendingPathComponent(modelDirName)
    }

    nonisolated static var downloadedTokenizerDir: URL {
        downloadedModelsRoot.appendingPathComponent(tokenizerDirName)
    }

    init() {
        isModelReady = Self.validateDownloadedAssets()
    }

    func downloadIfNeeded() async {
        if Self.validateDownloadedAssets() {
            isModelReady = true
            return
        }
        await download()
    }

    func download() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: Self.downloadedModelDir.appendingPathComponent("model.mlmodelc/analytics"), withIntermediateDirectories: true)
            try fm.createDirectory(at: Self.downloadedTokenizerDir, withIntermediateDirectories: true)

            let allFiles = Self.modelFiles.map { (Self.downloadedModelDir, $0) }
                + Self.tokenizerFiles.map { (Self.downloadedTokenizerDir, $0) }
            let totalCount = Double(allFiles.count)
            var completed = 0.0

            for (baseDir, filePair) in allFiles {
                try Task.checkCancellation()

                let remoteURL = URL(string: "\(Self.huggingFaceBaseURL)/\(filePair.remote)")!
                let localURL = baseDir.appendingPathComponent(filePair.local)

                if fm.fileExists(atPath: localURL.path) {
                    completed += 1
                    downloadProgress = completed / totalCount
                    continue
                }

                let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw DownloadError.httpError(code, filePair.remote)
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
                downloadProgress = completed / totalCount
            }

            try Self.validateDownloadedAssetsOrThrow()
            isModelReady = true
        } catch is CancellationError {
            downloadError = "Download was cancelled."
        } catch let error as DownloadError {
            downloadError = error.localizedDescription
            isModelReady = false
        } catch {
            downloadError = "Download failed: \(error.localizedDescription)"
            isModelReady = false
        }

        isDownloading = false
    }

    func deleteDownloadedModels() {
        let fm = FileManager.default
        try? fm.removeItem(at: Self.downloadedModelsRoot)
        isModelReady = false
        downloadProgress = 0
        downloadError = nil
    }

    nonisolated static func validateDownloadedAssets() -> Bool {
        (try? validateDownloadedAssetsOrThrow()) != nil
    }

    nonisolated static func canonicalEmbeddingModelLabel() -> String {
        canonicalModelLabel
    }

    nonisolated static func canonicalEmbeddingModelID() -> String {
        canonicalModelID
    }

    nonisolated private static func validateDownloadedAssetsOrThrow() throws {
        let fm = FileManager.default

        let modelDir = downloadedModelDir
        let compiledModel = modelDir.appendingPathComponent("model.mlmodelc")
        guard fm.fileExists(atPath: compiledModel.path) else {
            throw DownloadError.fileCorrupt("model.mlmodelc")
        }

        let tokenizerDir = downloadedTokenizerDir
        for expectedFile in tokenizerFiles.map(\.local) {
            let path = tokenizerDir.appendingPathComponent(expectedFile).path
            guard fm.fileExists(atPath: path) else {
                throw DownloadError.fileCorrupt(expectedFile)
            }
        }

        try validateArtifactMetadata(modelDir: modelDir, tokenizerDir: tokenizerDir)
    }

    nonisolated private static func validateArtifactMetadata(modelDir: URL, tokenizerDir: URL) throws {
        let tokenizerConfigURL = tokenizerDir.appendingPathComponent("tokenizer_config.json")
        let tokenizerConfig = try loadJSONDictionary(from: tokenizerConfigURL, source: "tokenizer_config.json")

        let tokenizerIDCandidates = collectStringValues(
            from: tokenizerConfig,
            keys: ["name_or_path", "_name_or_path", "model_id", "tokenizer_name", "tokenizer_id"]
        )
        guard tokenizerIDCandidates.contains(where: matchesCanonicalModelIdentifier(_:)) else {
            throw DownloadError.metadataMismatch(
                file: "tokenizer_config.json",
                expected: canonicalModelID,
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
        guard modelIDCandidates.contains(where: matchesCanonicalModelIdentifier(_:)) else {
            throw DownloadError.metadataMismatch(
                file: "model.mlmodelc/metadata.json",
                expected: canonicalModelID,
                found: modelIDCandidates.joined(separator: ", ")
            )
        }
    }

    nonisolated private static func matchesCanonicalModelIdentifier(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized == canonicalModelID.lowercased()
            || normalized.contains("codebert")
            || normalized.contains("microsoft/codebert-base")
    }

    nonisolated private static func loadJSONDictionary(from url: URL, source: String) throws -> [String: Any] {
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

    nonisolated private static func collectStringValues(
        from dictionary: [String: Any],
        keys: [String]
    ) -> [String] {
        var values: [String] = []
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                values.append(value)
            }
        }
        return values
    }

    nonisolated static func locateModelAsset() throws -> URL {
        let fm = FileManager.default

        let downloadedModel = downloadedModelDir.appendingPathComponent("model.mlmodelc")
        if fm.fileExists(atPath: downloadedModel.path) {
            return downloadedModel
        }

        throw DownloadError.modelNotDownloaded(
            "Embedding model not found at \(downloadedModel.path). Download \(canonicalModelLabel) from Model Manager before using semantic search."
        )
    }

    nonisolated static func locateTokenizerAsset() throws -> URL {
        let fm = FileManager.default

        let downloadedTokenizer = downloadedTokenizerDir
        let tokenizerJSON = downloadedTokenizer.appendingPathComponent("tokenizer.json")
        if fm.fileExists(atPath: tokenizerJSON.path) {
            return downloadedTokenizer
        }

        throw DownloadError.modelNotDownloaded(
            "Tokenizer assets not found at \(downloadedTokenizer.path). Download \(canonicalModelLabel) from Model Manager before using semantic search."
        )
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
