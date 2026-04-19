import Foundation
import SpeziLLM
import SpeziLLMLocal

actor LlamaEmbeddingService {

    private let modelID: String
    private let registry: ModelRegistry
    private let bookmarkService: BookmarkService

    nonisolated enum EmbeddingError: Error, LocalizedError, Sendable {
        case modelNotLoaded
        case inferenceFailure(String)
        case modelArtifactsMissing(path: String)
        case outputParseFailure(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Embedding model is not loaded."
            case .inferenceFailure(let detail):
                return "Embedding inference failed: \(detail)"
            case .modelArtifactsMissing(let path):
                return "Embedding model file not found at '\(path)'."
            case .outputParseFailure(let detail):
                return "Embedding output parse failure: \(detail)"
            }
        }
    }

    nonisolated struct ModelInfo: Sendable {
        let inputNames: [String]
        let outputNames: [String]
        let embeddingDimension: Int
        let maxSequenceLength: Int
    }

    nonisolated struct EmbeddingModelMetadata: Sendable {
        let modelIDs: Set<String>
        let embeddingDimension: Int
        let maxSequenceLength: Int

        func matches(modelID: String) -> Bool {
            modelIDs.contains(modelID)
        }
    }

    nonisolated protocol EmbeddingBackend: Sendable {
        func requestEmbedding(for text: String, using session: LLMLocalSession) async throws -> [Float]
    }

    nonisolated struct SpeziLLMDeterministicEmbeddingBackend: EmbeddingBackend {
        private struct EmbeddingPayload: Decodable {
            let embedding: [Float]
        }

        func requestEmbedding(for text: String, using session: LLMLocalSession) async throws -> [Float] {
            await MainActor.run {
                session.customContext = [
                    ["role": "system", "content": "Return deterministic embedding payload as JSON object: {\"embedding\":[number,...]}"],
                    ["role": "user", "content": text]
                ]
            }

            var response = ""
            let stream = try await session.generate()
            for try await chunk in stream {
                response += chunk
            }

            return try Self.decodeEmbeddingPayload(response)
        }

        nonisolated static func decodeEmbeddingPayload(_ response: String) throws -> [Float] {
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw EmbeddingError.outputParseFailure("Model returned an empty response")
            }
            guard let data = trimmed.data(using: .utf8) else {
                throw EmbeddingError.outputParseFailure("Model response was not UTF-8")
            }

            do {
                let payload = try JSONDecoder().decode(EmbeddingPayload.self, from: data)
                guard !payload.embedding.isEmpty else {
                    throw EmbeddingError.outputParseFailure("Embedding array is empty")
                }
                return payload.embedding
            } catch let error as EmbeddingError {
                throw error
            } catch {
                throw EmbeddingError.outputParseFailure("Malformed embedding payload: \(error.localizedDescription)")
            }
        }
    }

    private var modelURL: URL?
    private var cachedModelInfo: ModelInfo?
    private var platform: LLMLocalPlatform?
    private var session: LLMLocalSession?
    private let embeddingBackend: any EmbeddingBackend

    private static let knownModelMetadata: [EmbeddingModelMetadata] = [
        EmbeddingModelMetadata(
            modelIDs: ["jina-embeddings-v3-Q4_K_M.gguf", "jina-embeddings-v3-Q4_K_M"],
            embeddingDimension: 1024,
            maxSequenceLength: 8192
        )
    ]

    init(
        modelID: String,
        registry: ModelRegistry,
        bookmarkService: BookmarkService,
        embeddingBackend: (any EmbeddingBackend)? = nil
    ) {
        self.modelID = modelID
        self.registry = registry
        self.bookmarkService = bookmarkService
        self.embeddingBackend = embeddingBackend ?? SpeziLLMDeterministicEmbeddingBackend()
    }

    private static let defaultMaxSequenceLength = 512

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

            let metadata = Self.metadata(for: modelID)
            cachedModelInfo = ModelInfo(
                inputNames: ["text"],
                outputNames: ["embedding"],
                embeddingDimension: metadata?.embeddingDimension ?? 0,
                maxSequenceLength: metadata?.maxSequenceLength ?? Self.defaultMaxSequenceLength
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
        guard !text.isEmpty else {
            throw EmbeddingError.inferenceFailure("Input text is empty")
        }
        guard isLoaded else { throw EmbeddingError.modelNotLoaded }

        let session = try await loadSessionIfNeeded()
        do {
            let vector = try await requestEmbedding(for: text, using: session)
            try validateAndCacheEmbeddingDimension(vector.count)
            return vector
        } catch let error as EmbeddingError {
            throw error
        } catch {
            throw EmbeddingError.inferenceFailure(error.localizedDescription)
        }
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
            session.cancel()
        }
        session = nil
        platform = nil
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

        if platform == nil {
            platform = LLMLocalPlatform()
            platform?.configure()
        }

        let modelFileName = modelURL?.lastPathComponent ?? modelID
        let modelIdentifier = modelFileName.hasSuffix(".gguf") ? String(modelFileName.dropLast(5)) : modelFileName
        let schema = LLMLocalSchema(model: .custom(id: modelIdentifier), injectIntoContext: false)
        guard let platform else {
            throw EmbeddingError.inferenceFailure("Failed to initialize llama.cpp platform.")
        }
        let created = platform(with: schema)
        try await created.setup()
        session = created
        return created
    }

    private func requestEmbedding(for text: String, using session: LLMLocalSession) async throws -> [Float] {
        do {
            return try await embeddingBackend.requestEmbedding(for: text, using: session)
        } catch let error as EmbeddingError {
            throw error
        } catch {
            throw EmbeddingError.inferenceFailure(error.localizedDescription)
        }
    }

    private func validateAndCacheEmbeddingDimension(_ dimension: Int) throws {
        guard dimension > 0 else {
            throw EmbeddingError.inferenceFailure("Embedding vector is empty")
        }

        if let metadata = Self.metadata(for: modelID) {
            guard dimension == metadata.embeddingDimension else {
                throw EmbeddingError.inferenceFailure(
                    "Embedding dimension mismatch for \(modelID). Expected \(metadata.embeddingDimension), got \(dimension)."
                )
            }
        }

        if let info = cachedModelInfo {
            if info.embeddingDimension == 0 {
                cachedModelInfo = ModelInfo(
                    inputNames: info.inputNames,
                    outputNames: info.outputNames,
                    embeddingDimension: dimension,
                    maxSequenceLength: info.maxSequenceLength
                )
                return
            }

            guard info.embeddingDimension == dimension else {
                throw EmbeddingError.inferenceFailure(
                    "Embedding dimension mismatch. Expected \(info.embeddingDimension), got \(dimension)."
                )
            }

            return
        }

        cachedModelInfo = ModelInfo(
            inputNames: ["text"],
            outputNames: ["embedding"],
            embeddingDimension: dimension,
            maxSequenceLength: Self.defaultMaxSequenceLength
        )
    }

    private static func metadata(for modelID: String) -> EmbeddingModelMetadata? {
        knownModelMetadata.first { metadata in
            metadata.matches(modelID: modelID)
        }
    }
}
