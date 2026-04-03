import Foundation

nonisolated struct RepoIndexStats: Sendable {
    let totalFiles: Int
    let indexedFiles: Int
    let totalChunks: Int
    let embeddedChunks: Int
    let lastIndexedAt: Date?
    let languageBreakdown: [String: Int]

    var indexingProgress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(indexedFiles) / Double(totalFiles)
    }

    var embeddingProgress: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(embeddedChunks) / Double(totalChunks)
    }

    var isFullyIndexed: Bool {
        totalFiles > 0 && indexedFiles == totalFiles
    }

    var isFullyEmbedded: Bool {
        totalChunks > 0 && embeddedChunks == totalChunks
    }

    static let empty = RepoIndexStats(
        totalFiles: 0,
        indexedFiles: 0,
        totalChunks: 0,
        embeddedChunks: 0,
        lastIndexedAt: nil,
        languageBreakdown: [:]
    )
}
