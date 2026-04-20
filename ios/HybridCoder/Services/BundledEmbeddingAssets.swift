import Foundation

nonisolated enum BundledEmbeddingAssets: Sendable {
    static let embeddingModelsFolder = "Models"
    static let modelDirectoryName = "jina-embeddings-v3-gguf"
    static let tokenizerDirectoryName = "jina-embeddings-v3-tokenizer"

    static var documentsRootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static var modelsRootURL: URL {
        documentsRootURL.appendingPathComponent(embeddingModelsFolder, isDirectory: true)
    }

    static var legacyEmbeddingModelsRootURL: URL {
        documentsRootURL.appendingPathComponent("EmbeddingModels", isDirectory: true)
    }

    static var legacyApplicationSupportRootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("HybridCoder", isDirectory: true)
            .appendingPathComponent(embeddingModelsFolder, isDirectory: true)
    }

    static func ensureModelsDirectoryExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: modelsRootURL, withIntermediateDirectories: true)
    }

    static func migrateFromDocumentsIfNeeded() {
        let fm = FileManager.default
        ensureModelsDirectoryExists()
        migrateLegacyRoot(legacyEmbeddingModelsRootURL, fileManager: fm)
        migrateLegacyRoot(legacyApplicationSupportRootURL, fileManager: fm)
    }

    private static func migrateLegacyRoot(_ legacy: URL, fileManager fm: FileManager) {
        let legacyPath = legacy.path(percentEncoded: false)
        guard fm.fileExists(atPath: legacyPath) else { return }
        let modern = modelsRootURL
        let modernPath = modern.path(percentEncoded: false)

        if !fm.fileExists(atPath: modernPath) {
            do {
                try fm.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: legacy, to: modern)
                return
            } catch {
                try? fm.removeItem(at: legacy)
                return
            }
        }

        if let items = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            for item in items {
                let destination = modern.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: destination.path(percentEncoded: false)) { continue }
                try? fm.moveItem(at: item, to: destination)
            }
        }
        try? fm.removeItem(at: legacy)
    }
}
