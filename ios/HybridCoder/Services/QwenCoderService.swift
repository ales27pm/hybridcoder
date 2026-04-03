import Foundation

@available(*, deprecated, message: "MLX runtime removed. HybridCoder now uses Foundation Models + CoreML only.")
@Observable
@MainActor
final class QwenCoderService {
    var isLoaded: Bool = false
    var isLoading: Bool = false
    var isGenerating: Bool = false
    var loadError: String? = "MLX runtime is no longer supported in this build."
    var tokensPerSecond: Double = 0
    var loadProgress: Double = 0

    func warmUp(progressHandler: ((Double) -> Void)? = nil) async {
        progressHandler?(0)
        isLoading = false
        isLoaded = false
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.2
    ) async throws -> GenerationResult {
        throw QwenError.modelNotLoaded
    }

    func generateStreaming(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.2,
        onChunk: @escaping (String) -> Void
    ) async throws -> GenerationResult {
        throw QwenError.modelNotLoaded
    }

    func generateCode(prompt: String, context: String) async throws -> String {
        throw QwenError.modelNotLoaded
    }

    func generateCodeStreaming(
        prompt: String,
        context: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> GenerationResult {
        throw QwenError.modelNotLoaded
    }

    func generatePatchStreaming(
        prompt: String,
        context: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> GenerationResult {
        throw QwenError.modelNotLoaded
    }

    func generateExplanation(prompt: String, context: String) async throws -> String {
        throw QwenError.modelNotLoaded
    }

    func unload() {
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
                return "MLX runtime is not available in this iOS 26+ Foundation Models build."
            case .alreadyGenerating:
                return "A generation is already in progress."
            }
        }
    }
}
