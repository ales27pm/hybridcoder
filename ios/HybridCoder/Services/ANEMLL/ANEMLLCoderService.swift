import Foundation
@preconcurrency import CoreML

actor ANEMLLCoderService {
    struct GenerationResult: Sendable {
        let text: String
        let tokenCount: Int
        let tokensPerSecond: Double
        let elapsedSeconds: Double
    }

    enum ANEMLLError: Error, LocalizedError {
        case noImportedBundle
        case missingMetaYAML(URL)
        case bundleLoadFailed(String)
        case generationFailed(String)
        case alreadyGenerating
        case generationInProgress

        var errorDescription: String? {
            switch self {
            case .noImportedBundle:
                return "No imported ANEMLL model bundle is available. Import a local ANEMLL package first."
            case .missingMetaYAML(let url):
                return "The ANEMLL bundle at \(url.lastPathComponent) does not contain meta.yaml."
            case .bundleLoadFailed(let detail):
                return "Failed to load the ANEMLL bundle: \(detail)"
            case .generationFailed(let detail):
                return "ANEMLL generation failed: \(detail)"
            case .alreadyGenerating:
                return "An ANEMLL generation is already in progress."
            case .generationInProgress:
                return "Cannot unload ANEMLL while generation is in progress."
            }
        }
    }

    let modelName: String
    private let bundleImportService: ANEMLLBundleImportService

    private(set) var isLoaded: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isGenerating: Bool = false
    private(set) var loadError: String?
    private(set) var tokensPerSecond: Double = 0
    private(set) var loadProgress: Double = 0

    private var config: YAMLConfig?
    private var tokenizer: Tokenizer?
    private var inferenceManager: InferenceManager?
    private var loadedModels: LoadedModels?
    private var shouldUnloadAfterGeneration: Bool = false

    init(
        modelName: String = "anemll/imported-bundle",
        bundleImportService: ANEMLLBundleImportService = .shared
    ) {
        self.modelName = modelName
        self.bundleImportService = bundleImportService
    }

    func warmUp(progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        if isLoaded { return }
        isLoading = true
        loadError = nil
        loadProgress = 0.05
        progressHandler?(0.05)
        defer { isLoading = false }

        guard let bundle = bundleImportService.importedBundles().first else {
            loadError = ANEMLLError.noImportedBundle.localizedDescription
            throw ANEMLLError.noImportedBundle
        }

        let metaYAML = bundle.modelRoot.appendingPathComponent("meta.yaml")
        guard FileManager.default.fileExists(atPath: metaYAML.path(percentEncoded: false)) else {
            loadError = ANEMLLError.missingMetaYAML(bundle.modelRoot).localizedDescription
            throw ANEMLLError.missingMetaYAML(bundle.modelRoot)
        }

        do {
            let loadedConfig = try YAMLConfig.load(from: metaYAML.path(percentEncoded: false))
            config = loadedConfig
            loadProgress = 0.2
            progressHandler?(0.2)

            tokenizer = try await Tokenizer(
                modelPath: bundle.modelRoot.path(percentEncoded: false),
                template: detectTemplate(from: loadedConfig),
                debugLevel: 0
            )
            loadProgress = 0.45
            progressHandler?(0.45)

            let loader = ModelLoader(progressDelegate: nil)
            let models = try await loader.loadModel(from: loadedConfig)
            loadedModels = models
            loadProgress = 0.75
            progressHandler?(0.75)

            inferenceManager = try InferenceManager(
                models: models,
                contextLength: loadedConfig.contextLength,
                batchSize: loadedConfig.batchSize,
                splitLMHead: loadedConfig.splitLMHead,
                debugLevel: 0,
                v110: loadedConfig.configVersion == "0.1.1",
                argmaxInModel: loadedConfig.argmaxInModel,
                slidingWindow: loadedConfig.slidingWindow,
                updateMaskPrefill: loadedConfig.updateMaskPrefill,
                prefillDynamicSlice: loadedConfig.prefillDynamicSlice,
                modelPrefix: loadedConfig.modelPrefix,
                vocabSize: loadedConfig.vocabSize,
                lmHeadChunkSizes: loadedConfig.lmHeadChunkSizes
            )

            isLoaded = true
            loadProgress = 1.0
            progressHandler?(1.0)
        } catch {
            performUnload()
            loadError = error.localizedDescription
            throw ANEMLLError.bundleLoadFailed(error.localizedDescription)
        }
    }

    func generateCode(prompt: String, context: String) async throws -> String {
        let envelope = PromptBuilder.qwenCodeGenerationPrompt(query: prompt, repoContext: context)
        let result = try await generate(
            systemPrompt: envelope.system,
            userPrompt: envelope.user,
            maxTokens: 1024,
            onChunk: nil
        )
        return result.text
    }

    func generateCodeExplanation(prompt: String, context: String) async throws -> String {
        let envelope = PromptBuilder.qwenCodeExplanationPrompt(query: prompt, repoContext: context)
        let result = try await generate(
            systemPrompt: envelope.system,
            userPrompt: envelope.user,
            maxTokens: 1024,
            onChunk: nil
        )
        return result.text
    }

    func generateCodeStreaming(
        prompt: String,
        context: String,
        onChunk: @MainActor @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        let envelope = PromptBuilder.qwenCodeGenerationPrompt(query: prompt, repoContext: context)
        return try await generate(
            systemPrompt: envelope.system,
            userPrompt: envelope.user,
            maxTokens: 1024,
            onChunk: onChunk
        )
    }

    func generateCodeExplanationStreaming(
        prompt: String,
        context: String,
        onChunk: @MainActor @escaping @Sendable (String) -> Void
    ) async throws -> GenerationResult {
        let envelope = PromptBuilder.qwenCodeExplanationPrompt(query: prompt, repoContext: context)
        return try await generate(
            systemPrompt: envelope.system,
            userPrompt: envelope.user,
            maxTokens: 1024,
            onChunk: onChunk
        )
    }

    func unload() async throws {
        if isGenerating {
            shouldUnloadAfterGeneration = true
            throw ANEMLLError.generationInProgress
        }
        performUnload()
    }

    private func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        onChunk: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> GenerationResult {
        guard !isGenerating else {
            throw ANEMLLError.alreadyGenerating
        }
        if !isLoaded {
            try await warmUp(progressHandler: nil)
        }
        guard let tokenizer, let inferenceManager else {
            throw ANEMLLError.bundleLoadFailed("Tokenizer or inference manager is unavailable after warm-up.")
        }

        isGenerating = true
        var streamedText = ""
        var streamedTokenCount = 0
        let startedAt = Date()

        defer {
            isGenerating = false
            if shouldUnloadAfterGeneration {
                shouldUnloadAfterGeneration = false
                performUnload()
            }
        }

        let messages: [Tokenizer.ChatMessage] = {
            var resolved: [Tokenizer.ChatMessage] = []
            let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSystem.isEmpty {
                resolved.append(.system(trimmedSystem))
            }
            resolved.append(.user(userPrompt))
            return resolved
        }()

        let inputTokens = tokenizer.applyChatTemplate(input: messages, addGenerationPrompt: true)

        do {
            let result = try await inferenceManager.generateResponse(
                initialTokens: inputTokens,
                temperature: 0.0,
                maxTokens: maxTokens,
                eosTokens: tokenizer.eosTokenIds,
                tokenizer: tokenizer,
                onToken: { token in
                    streamedTokenCount += 1
                    let piece = tokenizer.decode(tokens: [token])
                    if !piece.isEmpty {
                        streamedText += piece
                        if let onChunk {
                            Task { @MainActor in
                                onChunk(streamedText)
                            }
                        }
                    }
                },
                onWindowShift: nil
            )

            let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
            let generatedTokens = result.0
            let decoded = tokenizer.decode(tokens: generatedTokens).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenCount = max(generatedTokens.count, streamedTokenCount)
            let computedTPS = Double(max(tokenCount, 1)) / elapsed
            tokensPerSecond = computedTPS

            return GenerationResult(
                text: decoded.isEmpty ? streamedText.trimmingCharacters(in: .whitespacesAndNewlines) : decoded,
                tokenCount: tokenCount,
                tokensPerSecond: computedTPS,
                elapsedSeconds: elapsed
            )
        } catch {
            throw ANEMLLError.generationFailed(error.localizedDescription)
        }
    }

    private func performUnload() {
        inferenceManager?.unload()
        inferenceManager = nil
        loadedModels = nil
        tokenizer = nil
        config = nil
        isLoaded = false
        isLoading = false
        loadProgress = 0
        loadError = nil
        tokensPerSecond = 0
    }

    private func detectTemplate(from config: YAMLConfig) -> String {
        let prefix = config.modelPrefix.lowercased()
        if prefix.contains("qwen") { return "qwen" }
        if prefix.contains("gemma") { return "gemma" }
        if prefix.contains("llama") { return "llama" }
        return "default"
    }
}
