import Foundation
import SpeziLLM
import SpeziLLMLocal

actor QwenCoderService {
    let modelName: String
    private let bookmarkService: BookmarkService

    private(set) var isLoaded: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isGenerating: Bool = false
    private(set) var loadError: String?
    private(set) var tokensPerSecond: Double = 0
    private(set) var loadProgress: Double = 0

    private let platform = LLMLocalPlatform()
    private var platformTask: Task<Void, Never>?
    private var session: LLMLocalSession?
    private var shouldUnloadAfterGeneration: Bool = false

    init(
        modelName: String = ModelRegistry.defaultCodeGenerationModelID,
        bookmarkService: BookmarkService = BookmarkService()
    ) {
        self.modelName = modelName
        self.bookmarkService = bookmarkService
    }

    func warmUp(progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        isLoading = true
        isLoaded = false
        loadError = nil
        loadProgress = 0.1
        progressHandler?(0.1)

        defer {
            isLoading = false
        }

        let modelURL = try await resolveModelURL()
        guard FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) else {
            throw QwenError.pipelineUnavailable("Missing model file at \(modelURL.path(percentEncoded: false)).")
        }


        _ = try await loadSessionIfNeeded()
        loadProgress = 1.0
        progressHandler?(1.0)
        isLoaded = true
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024
    ) async throws -> GenerationResult {
        return try await generateInternal(
            messages: Self.messages(systemPrompt: systemPrompt, userPrompt: userPrompt),
            maxTokens: maxTokens,
            onChunk: nil
        )
    }

    func generateStreaming(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> GenerationResult {
        return try await generateInternal(
            messages: Self.messages(systemPrompt: systemPrompt, userPrompt: userPrompt),
            maxTokens: maxTokens,
            onChunk: onChunk
        )
    }

    func generateCode(prompt: String, context: String) async throws -> String {
        let promptEnvelope = PromptBuilder.qwenCodeGenerationPrompt(query: prompt, repoContext: context)
        let result = try await generate(
            systemPrompt: promptEnvelope.system,
            userPrompt: promptEnvelope.user
        )
        return result.text
    }

    func generateCodeExplanation(prompt: String, context: String) async throws -> String {
        let promptEnvelope = PromptBuilder.qwenCodeExplanationPrompt(query: prompt, repoContext: context)
        let result = try await generate(
            systemPrompt: promptEnvelope.system,
            userPrompt: promptEnvelope.user
        )
        return result.text
    }

    func generateCodeStreaming(
        prompt: String,
        context: String,
        onChunk: @MainActor @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        let promptEnvelope = PromptBuilder.qwenCodeGenerationPrompt(query: prompt, repoContext: context)
        return try await generateStreaming(
            systemPrompt: promptEnvelope.system,
            userPrompt: promptEnvelope.user,
            onChunk: onChunk
        )
    }

    func generateCodeExplanationStreaming(
        prompt: String,
        context: String,
        onChunk: @MainActor @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        let promptEnvelope = PromptBuilder.qwenCodeExplanationPrompt(query: prompt, repoContext: context)
        return try await generateStreaming(
            systemPrompt: promptEnvelope.system,
            userPrompt: promptEnvelope.user,
            onChunk: onChunk
        )
    }

    func unload() async throws {
        if isGenerating {
            shouldUnloadAfterGeneration = true
            throw QwenError.generationInProgress
        }
        if let session {
            await session.offload()
        }
        performUnload()
    }

    private static let maxInputTokens = 2048

    private static func truncateMessages(_ messages: [[String: String]], maxEstimatedTokens: Int) -> [[String: String]] {
        let totalChars = messages.reduce(0) { $0 + ($1["content"]?.count ?? 0) }
        let estimatedTokens = Int(ceil(Double(totalChars) / 3.5))
        guard estimatedTokens > maxEstimatedTokens, messages.count >= 2 else { return messages }

        var result = messages
        let systemChars = result[0]["content"]?.count ?? 0
        let overheadTokens = Int(ceil(Double(systemChars) / 3.5)) + 20
        let userBudgetTokens = max(maxEstimatedTokens - overheadTokens, 200)
        let userBudgetChars = Int(Double(userBudgetTokens) * 3.5)

        if let userContent = result.last?["content"], userContent.count > userBudgetChars {
            let lastIndex = result.count - 1
            result[lastIndex]["content"] = String(userContent.prefix(userBudgetChars))
        }
        return result
    }

    private func generateInternal(
        messages: [[String: String]],
        maxTokens: Int,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> GenerationResult {
        guard !isGenerating else {
            throw QwenError.alreadyGenerating
        }

        if !isLoaded {
            try await warmUp()
        }

        isGenerating = true
        let startedAt = Date()
        var fullText = ""

        defer {
            isGenerating = false
            if shouldUnloadAfterGeneration {
                shouldUnloadAfterGeneration = false
                Task { [weak self] in
                    guard let self else { return }
                    _ = try? await self.unload()
                }
            }
        }

        do {
            let session = try await loadSessionIfNeeded()
            let truncatedMessages = Self.truncateMessages(messages, maxEstimatedTokens: Self.maxInputTokens)

            await MainActor.run {
                session.customContext = truncatedMessages
            }

            let stream = try await session.generate()
            for try await chunk in stream {
                try Task.checkCancellation()
                fullText += chunk
                if let onChunk {
                    await MainActor.run {
                        onChunk(chunk)
                    }
                }
                if Self.estimateTokenCount(in: fullText) >= maxTokens {
                    session.cancel()
                    break
                }
            }

            let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
            let tokenCount = Self.estimateTokenCount(in: fullText)
            let tps = Double(tokenCount) / elapsed
            tokensPerSecond = tps

            return GenerationResult(
                text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                tokenCount: tokenCount,
                tokensPerSecond: tps,
                elapsedSeconds: elapsed
            )
        } catch is CancellationError {
            throw QwenError.cancelled
        } catch {
            throw QwenError.generationFailed(error.localizedDescription)
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

        let modelIdentifier = modelName.hasSuffix(".gguf") ? String(modelName.dropLast(5)) : modelName
        let schema = LLMLocalSchema(model: .custom(id: modelIdentifier), injectIntoContext: false)
        let created = platform(with: schema)
        try await created.setup()
        session = created
        return created
    }

    private func resolveModelURL() async throws -> URL {
        guard let modelsRoot = await bookmarkService.resolveModelsFolderBookmark() else {
            throw QwenError.pipelineUnavailable("Models folder bookmark is missing. Please select On My iPhone > HybridCoder > Models.")
        }
        return modelsRoot.appendingPathComponent(modelName, isDirectory: false)
    }

    private func performUnload() {
        session = nil
        isLoaded = false
        isLoading = false
        tokensPerSecond = 0
        loadProgress = 0
        loadError = nil
    }

    private static func messages(systemPrompt: String, userPrompt: String) -> [[String: String]] {
        [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
    }

    private static func estimateTokenCount(in text: String) -> Int {
        max(Int(ceil(Double(text.count) / 4.0)), 1)
    }

    struct GenerationResult: Sendable {
        let text: String
        let tokenCount: Int
        let tokensPerSecond: Double
        let elapsedSeconds: Double
    }

    enum QwenError: Error, LocalizedError, Sendable {
        case pipelineUnavailable(String)
        case alreadyGenerating
        case generationInProgress
        case cancelled
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .pipelineUnavailable(let reason):
                return "llama.cpp model is unavailable: \(reason)"
            case .alreadyGenerating:
                return "A Qwen generation is already in progress."
            case .generationInProgress:
                return "Cannot unload Qwen while generation is in progress."
            case .cancelled:
                return "Qwen generation was cancelled."
            case .generationFailed(let reason):
                return "Qwen generation failed: \(reason)"
            }
        }
    }
}
