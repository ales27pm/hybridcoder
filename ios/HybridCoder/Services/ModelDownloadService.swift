import Foundation

@Observable
@MainActor
final class ModelDownloadService {

    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadError: String?
    private(set) var isModelReady: Bool = false

    private static let embeddingModelsDir = "EmbeddingModels"
    private static let modelDirName = "codebert-base-coreml"
    private static let tokenizerDirName = "codebert-base-tokenizer"

    private static let modelFiles: [(remote: String, local: String)] = [
        ("model.mlmodelc/model.mil", "model.mlmodelc/model.mil"),
        ("model.mlmodelc/coremldata.bin", "model.mlmodelc/coremldata.bin"),
        ("model.mlmodelc/metadata.json", "model.mlmodelc/metadata.json"),
        ("model.mlmodelc/analytics/coremldata.bin", "model.mlmodelc/analytics/coremldata.bin")
    ]

    private static let tokenizerFiles: [(remote: String, local: String)] = [
        ("tokenizer.json", "tokenizer.json"),
        ("tokenizer_config.json", "tokenizer_config.json")
    ]

    private static let huggingFaceBaseURL = "https://huggingface.co/nickmuchi/distilbert-base-coreml/resolve/main"

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

            isModelReady = Self.validateDownloadedAssets()
            if !isModelReady {
                downloadError = "Download completed but model validation failed. Some files may be corrupt."
            }
        } catch is CancellationError {
            downloadError = "Download was cancelled."
        } catch let error as DownloadError {
            downloadError = error.localizedDescription
        } catch {
            downloadError = "Download failed: \(error.localizedDescription)"
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
        let fm = FileManager.default

        let modelDir = downloadedModelDir
        let compiledModel = modelDir.appendingPathComponent("model.mlmodelc")
        guard fm.fileExists(atPath: compiledModel.path) else { return false }

        let tokenizerDir = downloadedTokenizerDir
        let tokenizerJSON = tokenizerDir.appendingPathComponent("tokenizer.json")
        let tokenizerConfig = tokenizerDir.appendingPathComponent("tokenizer_config.json")
        guard fm.fileExists(atPath: tokenizerJSON.path),
              fm.fileExists(atPath: tokenizerConfig.path) else { return false }

        return true
    }

    nonisolated static func locateModelAsset() throws -> URL {
        let fm = FileManager.default

        let downloadedModel = downloadedModelDir.appendingPathComponent("model.mlmodelc")
        if fm.fileExists(atPath: downloadedModel.path) {
            return downloadedModel
        }

        return try BundledEmbeddingAssets.locateModelAsset()
    }

    nonisolated static func locateTokenizerAsset() throws -> URL {
        let fm = FileManager.default

        let downloadedTokenizer = downloadedTokenizerDir
        let tokenizerJSON = downloadedTokenizer.appendingPathComponent("tokenizer.json")
        if fm.fileExists(atPath: tokenizerJSON.path) {
            return downloadedTokenizer
        }

        return try BundledEmbeddingAssets.locateTokenizerAssets()
    }

    nonisolated enum DownloadError: Error, LocalizedError, Sendable {
        case httpError(Int, String)
        case fileCorrupt(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .httpError(let code, let file):
                return "HTTP \(code) downloading \(file). Check your network connection and try again."
            case .fileCorrupt(let file):
                return "Downloaded file '\(file)' appears corrupt. Delete and re-download."
            }
        }
    }
}
