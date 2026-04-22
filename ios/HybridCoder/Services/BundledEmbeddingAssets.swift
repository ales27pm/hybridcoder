import Foundation

nonisolated enum BundledEmbeddingAssets: Sendable {
    static let modelDirectoryName = "jina-embeddings-v3-gguf"
    static let tokenizerDirectoryName = "jina-embeddings-v3-tokenizer"

    static var modelsRootURL: URL {
        ModelPaths.root
    }

    static func ensureModelsDirectoryExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: modelsRootURL, withIntermediateDirectories: true)
    }

    static func migrateFromDocumentsIfNeeded() {
        ensureModelsDirectoryExists()
    }
}
