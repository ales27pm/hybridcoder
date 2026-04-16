import Foundation
import NaturalLanguage

actor CoreMLEmbeddingService {

    private let modelID: String
    private let registry: ModelRegistry
    private let bookmarkService = BookmarkService()

    nonisolated enum EmbeddingError: Error, LocalizedError, Sendable {
        case modelNotLoaded
        case inferenceFailure(String)
        case modelArtifactsMissing(path: String)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Embedding model is not loaded."
            case .inferenceFailure(let detail):
                return "Embedding inference failed: \(detail)"
            case .modelArtifactsMissing(let path):
                return "Embedding model file not found at '\(path)'."
            }
        }
    }

    nonisolated struct ModelInfo: Sendable {
        let inputNames: [String]
        let outputNames: [String]
        let embeddingDimension: Int
        let maxSequenceLength: Int
    }

    private var modelURL: URL?
    private var cachedModelInfo: ModelInfo?

    init(modelID: String, registry: ModelRegistry) {
        self.modelID = modelID
        self.registry = registry
    }

    private let maxSequenceLength = 512
    private let fallbackEmbeddingDimension = 512

    var isLoaded: Bool {
        modelURL != nil
    }

    var modelInfo: ModelInfo? {
        cachedModelInfo
    }

    func load() async throws {
        await MainActor.run {
            registry.setLoadState(for: modelID, .loading)
        }

        do {
            let root = await bookmarkService.resolveModelsFolderBookmark() ?? ModelRegistry.externalModelsRoot
            let resolved = root.appendingPathComponent(modelID, isDirectory: false)

            guard FileManager.default.fileExists(atPath: resolved.path(percentEncoded: false)) else {
                throw EmbeddingError.modelArtifactsMissing(path: resolved.path)
            }

            self.modelURL = resolved
            cachedModelInfo = ModelInfo(
                inputNames: ["text"],
                outputNames: ["embedding"],
                embeddingDimension: fallbackEmbeddingDimension,
                maxSequenceLength: maxSequenceLength
            )

            await MainActor.run {
                registry.setLoadState(for: modelID, .loaded)
            }
        } catch {
            await MainActor.run {
                registry.setLoadState(for: modelID, .failed(error.localizedDescription))
            }
            throw error
        }
    }

    func embed(text: String) async throws -> [Float] {
        guard modelURL != nil else { throw EmbeddingError.modelNotLoaded }
        guard !text.isEmpty else {
            throw EmbeddingError.inferenceFailure("Input text is empty")
        }

        return try Self.semanticEmbedding(for: text)
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            try Task.checkCancellation()
            let vec = try await embed(text: text)
            results.append(vec)
        }
        return results
    }

    func trimTokenizerCache() async {
    }

    func unload() async {
        modelURL = nil
        cachedModelInfo = nil
        await MainActor.run {
            registry.setLoadState(for: modelID, .unloaded)
        }
    }

    private static func semanticEmbedding(for text: String) throws -> [Float] {
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english),
           let vector = sentenceEmbedding.vector(for: text),
           vector.isEmpty == false {
            return l2Normalize(vector)
        }

        if let wordEmbedding = NLEmbedding.wordEmbedding(for: .english),
           let vector = wordEmbedding.vector(for: text),
           vector.isEmpty == false {
            return l2Normalize(vector)
        }

        throw EmbeddingError.inferenceFailure("NaturalLanguage embedding lookup failed")
    }

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
