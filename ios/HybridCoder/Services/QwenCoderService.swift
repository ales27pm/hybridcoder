import Darwin
import Foundation
import CoreMLPipelines
@preconcurrency import Hub

extension TextGenerationPipeline: @unchecked @retroactive Sendable {}

actor QwenCoderService {
    let modelName: String
    private let hubDownloadBase: URL
    private let accessTokenProvider: () -> String?

    private(set) var isLoaded: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isGenerating: Bool = false
    private(set) var loadError: String?
    private(set) var tokensPerSecond: Double = 0
    private(set) var loadProgress: Double = 0

    private var pipeline: TextGenerationPipeline?
    private var loadingTask: Task<TextGenerationPipeline, Error>?
    private var shouldUnloadAfterGeneration: Bool = false

    init(
        modelName: String = "finnvoorhees/coreml-Qwen2.5-Coder-1.5B-Instruct-4bit",
        hubDownloadBase: URL = ModelRegistry.coreMLPipelinesDownloadRoot,
        accessTokenProvider: @escaping () -> String? = { nil }
    ) {
        self.modelName = modelName
        self.hubDownloadBase = hubDownloadBase
        self.accessTokenProvider = accessTokenProvider
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

        configureDownloadEnvironment()
        let pipeline = try await loadPipelineIfNeeded()
        loadProgress = 0.7
        progressHandler?(0.7)

        do {
            try await pipeline.prewarm()
        } catch {
            loadError = error.localizedDescription
            loadProgress = 0
            throw QwenError.pipelineUnavailable(error.localizedDescription)
        }

        isLoaded = true
        loadProgress = 1.0
        progressHandler?(1.0)
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

    func unload() async throws {
        if isGenerating {
            shouldUnloadAfterGeneration = true
            throw QwenError.generationInProgress
        }
        performUnload()
    }

    private func configureDownloadEnvironment() {
        guard let rawToken = accessTokenProvider() else {
            return
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }

        setenv("HF_TOKEN", token, 1)
        setenv("HUGGING_FACE_HUB_TOKEN", token, 1)
        setenv("HUGGINGFACE_HUB_TOKEN", token, 1)
    }

    private func loadPipelineIfNeeded() async throws -> TextGenerationPipeline {
        if let pipeline {
            isLoaded = true
            loadError = nil
            return pipeline
        }

        if let loadingTask {
            return try await loadingTask.value
        }

        isLoading = true
        loadProgress = max(loadProgress, 0.2)
        loadError = nil

        let token = accessTokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hubAPI = HubApi(
            downloadBase: hubDownloadBase,
            hfToken: token?.isEmpty == false ? token : nil
        )

        let task = Task {
            try await TextGenerationPipeline(modelName: modelName, prewarm: false, hubAPI: hubAPI)
        }
        loadingTask = task

        defer {
            loadingTask = nil
            isLoading = false
        }

        do {
            let loaded = try await task.value
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
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> GenerationResult {
        guard !isGenerating else {
            throw QwenError.alreadyGenerating
        }

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
        loadingTask = nil
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
                return "CoreMLPipelines model is unavailable: \(reason)"
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
