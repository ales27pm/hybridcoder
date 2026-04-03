import Foundation

/// Shared embedding artifact names used by download and runtime resolution.
/// Bundle lookup is intentionally unsupported; assets must be downloaded into Documents.
nonisolated enum BundledEmbeddingAssets: Sendable {
    static let embeddingModelsFolder = "EmbeddingModels"
    static let modelDirectoryName = "codebert-base-coreml"
    static let tokenizerDirectoryName = "codebert-base-tokenizer"
}
