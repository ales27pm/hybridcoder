import Foundation

nonisolated enum BundledEmbeddingAssets: Sendable {
    static let embeddingModelsFolder = "Models"
    static let modelDirectoryName = "codebert-base-coreml"
    static let tokenizerDirectoryName = "codebert-base-tokenizer"

    static var modelsRootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent(embeddingModelsFolder, isDirectory: true)
    }

    static var legacyModelsRootURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EmbeddingModels", isDirectory: true)
    }

    static func migrateFromDocumentsIfNeeded() {
        let fm = FileManager.default
        let legacy = legacyModelsRootURL
        let modern = modelsRootURL

        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }
        guard !fm.fileExists(atPath: modern.path(percentEncoded: false)) else {
            try? fm.removeItem(at: legacy)
            return
        }

        do {
            try fm.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: modern)
        } catch {
            try? fm.removeItem(at: legacy)
        }
    }
}
