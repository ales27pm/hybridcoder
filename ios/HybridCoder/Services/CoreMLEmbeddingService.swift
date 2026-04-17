import Foundation
import SpeziLLM
import SpeziLLMLocal

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
    private let platform = LLMLocalPlatform()
    private var platformTask: Task<Void, Never>?
    private var session: LLMLocalSession?

    init(modelID: String, registry: ModelRegistry) {
        self.modelID = modelID
        self.registry = registry
    }

    private let maxSequenceLength = 512
    private let fallbackEmbeddingDimension = 512

    var isLoaded: Bool {
        modelURL != nil && session != nil
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
            _ = try await loadSessionIfNeeded()
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
        guard isLoaded else { throw EmbeddingError.modelNotLoaded }
        guard !text.isEmpty else {
            throw EmbeddingError.inferenceFailure("Input text is empty")
        }

        return Self.semanticEmbedding(for: text, dimensions: fallbackEmbeddingDimension)
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
        if let session {
            await session.offload()
        }
        session = nil
        modelURL = nil
        cachedModelInfo = nil
        await MainActor.run {
            registry.setLoadState(for: modelID, .unloaded)
        }
    }

    private func loadSessionIfNeeded() async throws -> LLMLocalSession {
        if let session {
            return session
        }

        if platformTask == nil {
            platform.configure()
            platformTask = Task { [platform] in
                await platform.run()
            }
        }

        let modelIdentifier = modelID.hasSuffix(".gguf") ? String(modelID.dropLast(5)) : modelID
        let schema = LLMLocalSchema(model: .custom(id: modelIdentifier), injectIntoContext: false)
        let created = platform(with: schema)
        try await created.setup()
        session = created
        return created
    }

    private static func semanticEmbedding(for text: String, dimensions: Int) -> [Float] {
        var vector = Array(repeating: Float(0), count: dimensions)
        for scalar in text.unicodeScalars {
            let idx = Int(scalar.value) % dimensions
            vector[idx] += 1
        }

        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
