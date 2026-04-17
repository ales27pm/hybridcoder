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
                embeddingDimension: 0,
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

        let modelFileName = modelURL?.lastPathComponent ?? modelID
        let modelIdentifier = modelFileName.hasSuffix(".gguf") ? String(modelFileName.dropLast(5)) : modelFileName
        let schema = LLMLocalSchema(model: .custom(id: modelIdentifier), injectIntoContext: false)
        let created = platform(with: schema)
        try await created.setup()
        session = created
        return created
    }

    private func requestEmbedding(for text: String, using session: LLMLocalSession) async throws -> [Float] {
        let systemPrompt = """
        You are an embedding endpoint. Return only valid JSON with this shape: {"embedding":[float,...]} and no additional text.
        """

        let userPrompt = """
        Produce an embedding for this input:
\(text)
        """

        await MainActor.run {
            session.customContext = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        }

        var response = ""
        let stream = try await session.generate()
        for try await chunk in stream {
            response += chunk
        }

        do {
            return try Self.parseEmbedding(from: response)
        } catch let error as EmbeddingError {
            throw error
        } catch {
            throw EmbeddingError.outputParseFailure(error.localizedDescription)
        }
    }

    private func validateAndCacheEmbeddingDimension(_ dimension: Int) throws {
        guard dimension > 0 else {
            throw EmbeddingError.inferenceFailure("Embedding vector is empty")
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
            maxSequenceLength: maxSequenceLength
        )
    }

    private static func parseEmbedding(from response: String) throws -> [Float] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EmbeddingError.outputParseFailure("Model returned an empty response")
        }

        if let vector = parseEmbeddingJSON(trimmed) {
            return vector
        }

        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end {
            let candidate = String(trimmed[start...end])
            if let vector = parseFloatArray(candidate) {
                return vector
            }
        }

        throw EmbeddingError.outputParseFailure("Unable to decode embedding JSON")
    }

    private static func parseEmbeddingJSON(_ jsonString: String) -> [Float]? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any],
           let raw = dictionary["embedding"] {
            return coerceFloatArray(raw)
        }

        return parseFloatArray(jsonString)
    }

    private static func parseFloatArray(_ jsonArrayString: String) -> [Float]? {
        guard let data = jsonArrayString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return coerceFloatArray(object)
    }

    private static func coerceFloatArray(_ raw: Any) -> [Float]? {
        guard let values = raw as? [Any], !values.isEmpty else {
            return nil
        }

        var floats: [Float] = []
        floats.reserveCapacity(values.count)
        for value in values {
            if let number = value as? NSNumber {
                floats.append(number.floatValue)
            } else if let string = value as? String, let parsed = Float(string) {
                floats.append(parsed)
            } else {
                return nil
            }
        }

        return floats
    }
}
