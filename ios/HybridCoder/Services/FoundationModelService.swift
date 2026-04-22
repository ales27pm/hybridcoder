import Foundation
import OSLog

nonisolated struct ToolProviders: Sendable {
    let readFile: @Sendable (String) async -> String?
    let searchCode: @Sendable (String, Int) async -> [(filePath: String, startLine: Int, endLine: Int, content: String, score: Float)]
    let listFiles: @Sendable (String?) async -> [String]
}

/// Local orchestration LLM.
///
/// Backed by the Qwen runtime (`QwenCoderService`); runs answer generation,
/// patch-plan generation, conversation summarization, and hosts the
/// route-classifier contract. Name deliberately does not reference Apple
/// FoundationModels — this is a local model. The canonical public alias
/// is `LocalOrchestrationModel`; this type name is retained for backward
/// compatibility with existing call sites.
@Observable
@MainActor
final class FoundationModelService {
    private let registry: ModelRegistry
    private let modelID: String
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "LocalOrchestrationModel")
    private let qwenService: QwenCoderService
    private let routeClassifier: RouteClassifier
    private let locationResolver: ModelLocationResolver
    private let bookmarkService: BookmarkService

    var statusText: String = "Checking…"
    var isAvailable: Bool = false
    var isGenerating: Bool = false

    private var toolProviders: ToolProviders?
    private var sessionManager: LanguageModelSessionManager?

    init(
        registry: ModelRegistry,
        modelID: String,
        bookmarkService: BookmarkService = BookmarkService(),
        routeClassifier: RouteClassifier = ScoredIntentRouteClassifier()
    ) {
        self.registry = registry
        self.modelID = modelID
        self.bookmarkService = bookmarkService
        self.qwenService = QwenCoderService(
            modelName: registry.resolvedLocalModelName(for: modelID),
            bookmarkService: bookmarkService
        )
        self.routeClassifier = routeClassifier
        self.locationResolver = ModelLocationResolver(registry: registry)
        refreshStatus()
    }

    func configure(toolProviders: ToolProviders?, sessionManager: LanguageModelSessionManager?) {
        self.toolProviders = toolProviders
        self.sessionManager = sessionManager
    }

    func refreshStatus() {
        let readiness = locationResolver.readiness(modelID: modelID)
        applyReadiness(readiness)
    }

    func refreshStatus(preferredRoot: URL?) {
        let readiness = locationResolver.readiness(modelID: modelID, preferredRoot: preferredRoot)
        applyReadiness(readiness)
    }

    func refreshStatusFromBookmark() async {
        let preferredRoot = await bookmarkService.resolveModelsFolderBookmark()
        refreshStatus(preferredRoot: preferredRoot)
    }

    private func applyReadiness(_ readiness: ModelReadinessCheck) {
        let installed = readiness.isReady
        isAvailable = installed

        if installed {
            statusText = "Ready"
            registry.setAvailability(for: modelID, isAvailable: true)
            registry.setInstallState(for: modelID, .installed)
            registry.setLoadState(for: modelID, .loaded)
        } else {
            statusText = readiness.failureReason ?? "Model not found in \(ModelRegistry.canonicalModelsFolderDisplayPath)"
            registry.setAvailability(for: modelID, isAvailable: false)
            registry.setInstallState(for: modelID, .notInstalled)
            registry.setLoadState(for: modelID, .unloaded)
        }
    }

    func invalidateSessions() {
        sessionManager?.removeSession(id: "local-orch-route-classifier")
        sessionManager?.removeSession(id: "local-orch-explanation")
        sessionManager?.removeSession(id: "local-orch-patch-planning")
        sessionManager?.removeSession(id: "local-orch-compaction")
    }

    func classifyRoute(query: String, fileList: [String]) async throws -> RouteDecision {
        try await routeClassifier.classify(query: query, fileList: fileList)
    }

    func generateAnswer(query: String, context: String, route: Route) async throws -> String {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let promptEnvelope = PromptBuilder.foundationPrompt(route: route, query: query, repoContext: context)
        let result = try await qwenService.generate(
            systemPrompt: promptEnvelope.system,
            userPrompt: promptEnvelope.user
        )
        return result.text
    }

    func streamAnswer(query: String, context: String, route: Route) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard self.isAvailable else {
                    continuation.finish(throwing: ServiceError.unavailable)
                    return
                }

                self.isGenerating = true
                let promptEnvelope = PromptBuilder.foundationPrompt(route: route, query: query, repoContext: context)
                var accumulated = ""

                do {
                    _ = try await self.qwenService.generateStreaming(
                        systemPrompt: promptEnvelope.system,
                        userPrompt: promptEnvelope.user
                    ) { delta in
                        accumulated += delta
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                self.isGenerating = false
            }
        }
    }

    func generatePatchPlan(query: String, codeContext: String) async throws -> PatchPlan {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let promptEnvelope = PromptBuilder.patchPlanningPrompt(query: query, repoContext: codeContext)
        let result = try await qwenService.generate(
            systemPrompt: promptEnvelope.system,
            userPrompt: promptEnvelope.user
        )

        let summary = "Patch plan generated with llama.cpp"
        let operations = Self.extractPatchOperations(from: result.text)
        if operations.isEmpty {
            logger.warning("Failed to parse patch plan output")
            throw ServiceError.generationFailed("No valid patch operations could be parsed from model output")
        }
        return PatchPlan(summary: summary, operations: operations)
    }

    func summarizeConversationMemory(
        priorSummary: String,
        turns: String,
        fileOperationSummaries: String
    ) async throws -> String {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        You compress coding-chat memory. Keep critical constraints, decisions, and unresolved tasks.
        Preserve file operation outcomes and avoid repeating obvious details.

        Existing summary:
        \(String(priorSummary.prefix(800)))

        File operation summaries:
        \(String(fileOperationSummaries.prefix(600)))

        Older turns to compact:
        \(String(turns.prefix(2_000)))

        Return a compact, actionable memory block in under 220 words.
        """

        let result = try await qwenService.generate(
            systemPrompt: "You are a concise engineering memory compactor.",
            userPrompt: prompt,
            maxTokens: 512
        )
        return result.text
    }

    private static func extractPatchOperations(from text: String) -> [PatchOperation] {
        let pattern = #"(?s)filePath:\s*(.+?)\nsearchText:\s*(.*?)\nreplaceText:\s*(.*?)\ndescription:\s*(.*?)(?:\n\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match in
            guard match.numberOfRanges == 5 else { return nil }
            let filePath = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let searchText = nsText.substring(with: match.range(at: 2))
            let replaceText = nsText.substring(with: match.range(at: 3))
            let description = nsText.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filePath.isEmpty else { return nil }
            if !searchText.isEmpty && searchText == replaceText { return nil }
            return PatchOperation(filePath: filePath, searchText: searchText, replaceText: replaceText, description: description)
        }
    }

    nonisolated enum ServiceError: Error, LocalizedError, Sendable {
        case unavailable
        case generationFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .unavailable:
                return "llama.cpp model is not available. Place the model inside \(ModelRegistry.canonicalModelsFolderDisplayPath)."
            case .generationFailed(let reason):
                return "Generation failed: \(reason)"
            }
        }
    }
}
