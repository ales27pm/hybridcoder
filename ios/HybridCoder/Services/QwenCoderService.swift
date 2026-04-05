import Foundation
import CoreMLPipelines

actor QwenCoderService {
    let modelName: String

    private(set) var isLoaded: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isGenerating: Bool = false
    private(set) var loadError: String?
    private(set) var tokensPerSecond: Double = 0
    private(set) var loadProgress: Double = 0

    private var pipeline: TextGenerationPipeline?
    private var shouldUnloadAfterGeneration: Bool = false

    init(modelName: String = "finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit") {
        self.modelName = modelName
    }

    func warmUp(progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        progressHandler?(0.1)
        let pipeline = try await loadPipelineIfNeeded()
        loadProgress = 0.7
        progressHandler?(0.7)

        try await pipeline.prewarm()
        isLoaded = true
        loadProgress = 1.0
        progressHandler?(1.0)
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.2
    ) async throws -> GenerationResult {
        return try await generateInternal(
            messages: Self.messages(systemPrompt: systemPrompt, userPrompt: userPrompt),
            maxTokens: maxTokens,
            temperature: temperature,
            onChunk: nil
        )
    }

    func generateStreaming(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.2,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> GenerationResult {
        return try await generateInternal(
            messages: Self.messages(systemPrompt: systemPrompt, userPrompt: userPrompt),
            maxTokens: maxTokens,
            temperature: temperature,
            onChunk: onChunk
        )
    }

    func generateCode(prompt: String, context: String) async throws -> String {
        let result = try await generate(
            systemPrompt: PromptBuilder.qwenCodeGenerationSystem(),
            userPrompt: PromptBuilder.qwenCodeGenerationUser(query: prompt, repoContext: context)
        )
        return result.text
    }

    func generateCodeStreaming(
        prompt: String,
        context: String,
        onChunk: @MainActor @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        try await generateStreaming(
            systemPrompt: PromptBuilder.qwenCodeGenerationSystem(),
            userPrompt: PromptBuilder.qwenCodeGenerationUser(query: prompt, repoContext: context),
            onChunk: onChunk
        )
    }

    func unload() async throws {
        if isGenerating {
            shouldUnloadAfterGeneration = true
            throw QwenError.generationInProgress
        }
        performUnload()
    }

    private func loadPipelineIfNeeded() async throws -> TextGenerationPipeline {
        if let pipeline {
            isLoaded = true
            loadError = nil
            return pipeline
        }

        guard !isLoading else {
            throw QwenError.alreadyLoading
        }

        isLoading = true
        loadProgress = 0.2
        defer {
            isLoading = false
        }

        do {
            let loaded = try await TextGenerationPipeline(modelName: modelName, prewarm: false)
            pipeline = loaded
            isLoaded = true
            loadError = nil
            loadProgress = max(loadProgress, 0.6)
            return loaded
        } catch {
            isLoaded = false
            loadError = error.localizedDescription
            throw QwenError.pipelineUnavailable(error.localizedDescription)
        }
    }

    private func generateInternal(
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> GenerationResult {
        guard !isGenerating else {
            throw QwenError.alreadyGenerating
        }

        _ = temperature // Current CoreMLPipelines API uses greedy sampling.
        let pipeline = try await loadPipelineIfNeeded()
        isGenerating = true

        let startedAt = Date()
        var fullText = ""

        defer {
            isGenerating = false
            if shouldUnloadAfterGeneration {
                shouldUnloadAfterGeneration = false
                performUnload()
            }
        }

        do {
            let stream = pipeline.generate(messages: messages, maxNewTokens: maxTokens)
            for try await chunk in stream {
                try Task.checkCancellation()
                fullText += chunk
                if let onChunk {
                    await MainActor.run {
                        onChunk(chunk)
                    }
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

    private func performUnload() {
        pipeline = nil
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
        max(text.split(whereSeparator: \.isWhitespace).count, 1)
    }

    struct GenerationResult: Sendable {
        let text: String
        let tokenCount: Int
        let tokensPerSecond: Double
        let elapsedSeconds: Double
    }

    enum QwenError: Error, LocalizedError, Sendable {
        case pipelineUnavailable(String)
        case alreadyLoading
        case alreadyGenerating
        case generationInProgress
        case cancelled
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .pipelineUnavailable(let reason):
                return "CoreMLPipelines model is unavailable: \(reason)"
            case .alreadyLoading:
                return "Qwen coder model is already loading."
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
