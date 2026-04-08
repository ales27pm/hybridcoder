import Foundation

nonisolated struct EmbeddingPipelineDiagnostic: Sendable {
    let embeddingModelLoaded: Bool
    let indexExists: Bool
    let storedEmbeddings: Int
    let persistedEmbeddings: Int
    let searchable: Bool
    let workspaceFileCount: Int
    let indexStats: RepoIndexStats?
    let persistenceError: String?

    var isHealthy: Bool {
        embeddingModelLoaded && indexExists && storedEmbeddings > 0 && searchable && persistenceError == nil
    }

    var storeRetrieveMismatch: Bool {
        storedEmbeddings != persistedEmbeddings
    }

    var summary: String {
        var parts: [String] = []

        if !embeddingModelLoaded {
            parts.append("Embedding model not loaded")
        }
        if !indexExists {
            parts.append("No search index")
        } else if storedEmbeddings == 0 {
            parts.append("Index empty")
        }

        if storeRetrieveMismatch {
            parts.append("Store/retrieve mismatch: \(storedEmbeddings) in memory vs \(persistedEmbeddings) persisted")
        }

        if let error = persistenceError {
            parts.append("Persistence error: \(error)")
        }

        if parts.isEmpty {
            return "Healthy: \(storedEmbeddings) embeddings, \(workspaceFileCount) workspace files"
        }

        return parts.joined(separator: "; ")
    }
}
