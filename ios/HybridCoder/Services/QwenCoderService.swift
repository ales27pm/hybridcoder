import Foundation
import MLX
import MLXLLM
import MLXLMCommon

@Observable
@MainActor
final class QwenCoderService {
    var isLoaded: Bool = false
    var isLoading: Bool = false
    var isGenerating: Bool = false
    var loadError: String?
    var tokensPerSecond: Double = 0
    var loadProgress: Double = 0

    private var modelContainer: ModelContainer?

    private static let modelID = "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit"

    private var modelConfiguration: ModelConfiguration {
        ModelConfiguration(id: Self.modelID)
    }

    func warmUp(progressHandler: ((Double) -> Void)? = nil) async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        loadError = nil
        loadProgress = 0

        do {
            GPU.set(cacheLimit: 20 * 1024 * 1024)

            let config = modelConfiguration
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    self?.loadProgress = fraction
                    progressHandler?(fraction)
                }
            }
            modelContainer = container
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.2
    ) async throws -> GenerationResult {
        guard let container = modelContainer else {
            throw QwenError.modelNotLoaded
        }
        guard !isGenerating else {
            throw QwenError.alreadyGenerating
        }

        isGenerating = true
        defer { isGenerating = false }

        let params = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: 0.95,
            repetitionPenalty: 1.1
        )

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        let response = try await session.respond(to: userPrompt)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let estimatedTokens = response.split(separator: " ").count * 2
        let tps = elapsed > 0 ? Double(estimatedTokens) / elapsed : 0
        tokensPerSecond = tps

        return GenerationResult(
            text: response,
            tokenCount: estimatedTokens,
            tokensPerSecond: tps,
            elapsedSeconds: elapsed
        )
    }

    func generateStreaming(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.2,
        onChunk: @escaping (String) -> Void
    ) async throws -> GenerationResult {
        guard let container = modelContainer else {
            throw QwenError.modelNotLoaded
        }
        guard !isGenerating else {
            throw QwenError.alreadyGenerating
        }

        isGenerating = true
        defer { isGenerating = false }

        let params = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: 0.95,
            repetitionPenalty: 1.1
        )

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: params
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        var fullText = ""
        var chunkCount = 0

        for try await chunk in session.streamResponse(to: userPrompt) {
            fullText = chunk
            chunkCount += 1
            onChunk(chunk)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let tps = elapsed > 0 ? Double(chunkCount) / elapsed : 0
        tokensPerSecond = tps

        return GenerationResult(
            text: fullText,
            tokenCount: chunkCount,
            tokensPerSecond: tps,
            elapsedSeconds: elapsed
        )
    }

    func generateCode(prompt: String, context: String) async throws -> String {
        let result = try await generate(
            systemPrompt: PromptBuilder.codeGenerationSystem(),
            userPrompt: PromptBuilder.codeGenerationUser(query: prompt, repoContext: context)
        )
        return result.text
    }

    func generateCodeStreaming(
        prompt: String,
        context: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> GenerationResult {
        try await generateStreaming(
            systemPrompt: PromptBuilder.codeGenerationSystem(),
            userPrompt: PromptBuilder.codeGenerationUser(query: prompt, repoContext: context),
            onChunk: onChunk
        )
    }

    func generatePatchStreaming(
        prompt: String,
        context: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> GenerationResult {
        try await generateStreaming(
            systemPrompt: PromptBuilder.patchPlanningSystem(),
            userPrompt: PromptBuilder.patchPlanningUser(query: prompt, repoContext: context),
            onChunk: onChunk
        )
    }

    func generateExplanation(prompt: String, context: String) async throws -> String {
        let result = try await generate(
            systemPrompt: PromptBuilder.explanationSystem(),
            userPrompt: PromptBuilder.explanationUser(query: prompt, repoContext: context)
        )
        return result.text
    }

    func unload() {
        modelContainer = nil
        isLoaded = false
        tokensPerSecond = 0
        loadProgress = 0
    }

    nonisolated struct GenerationResult: Sendable {
        let text: String
        let tokenCount: Int
        let tokensPerSecond: Double
        let elapsedSeconds: Double
    }

    nonisolated enum QwenError: Error, LocalizedError, Sendable {
        case modelNotLoaded
        case alreadyGenerating

        nonisolated var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Qwen model is not loaded. Please download and load the model first."
            case .alreadyGenerating:
                return "A generation is already in progress."
            }
        }
    }
}
