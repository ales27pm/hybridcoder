import Foundation
import FoundationModels
import OSLog

@available(iOS 26.0, *)
@Generable
nonisolated struct GenerablePatchOperation: Sendable {
    @Guide(description: "Relative file path within the repository")
    var filePath: String

    @Guide(description: "The exact text to find in the file — must match verbatim including whitespace")
    var searchText: String

    @Guide(description: "The replacement text that will replace the search text")
    var replaceText: String

    @Guide(description: "One-line description of what this change does")
    var description: String
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GenerablePatchPlan: Sendable {
    @Guide(description: "A concise summary of what this patch set accomplishes")
    var summary: String

    @Guide(description: "Ordered list of exact-match search-and-replace operations", .minimumCount(1))
    var operations: [GenerablePatchOperation]
}

nonisolated struct ToolProviders: Sendable {
    let readFile: @Sendable (String) async -> String?
    let searchCode: @Sendable (String, Int) async -> [(filePath: String, startLine: Int, endLine: Int, content: String, score: Float)]
    let listFiles: @Sendable (String?) async -> [String]
}

@available(iOS 26.0, *)
@Observable
@MainActor
final class FoundationModelService {
    private let registry: ModelRegistry
    private let modelID: String
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "FoundationModelService")

    var statusText: String = "Checking…"
    var isAvailable: Bool = false
    var isGenerating: Bool = false

    private var routeClassifierSession: LanguageModelSession?
    private var routeClassifierTurnCount: Int = 0

    private var explanationSession: LanguageModelSession?
    private var explanationTurnCount: Int = 0

    private var patchSession: LanguageModelSession?
    private var patchTurnCount: Int = 0

    private var compactionSession: LanguageModelSession?

    private var toolProviders: ToolProviders?

    private var sessionManager: LanguageModelSessionManager?
    private let routeSessionID = "fm-route-classifier"
    private let explanationSessionID = "fm-explanation"
    private let patchSessionID = "fm-patch-planning"
    private let compactionSessionID = "fm-compaction"

    private let maxRouteClassifierTurns = 20
    private let maxExplanationTurns = 12
    private let maxPatchTurns = 8

    init(registry: ModelRegistry, modelID: String) {
        self.registry = registry
        self.modelID = modelID
        refreshStatus()
    }

    func configure(toolProviders: ToolProviders?, sessionManager: LanguageModelSessionManager?) {
        self.toolProviders = toolProviders
        self.sessionManager = sessionManager
    }

    func refreshStatus() {
        switch SystemLanguageModel.default.availability {
        case .available:
            statusText = "Ready"
            isAvailable = true
            registry.setAvailability(for: modelID, isAvailable: true)
            registry.setLoadState(for: modelID, .loaded)
        case .unavailable(.appleIntelligenceNotEnabled):
            statusText = "Enable Apple Intelligence in Settings"
            isAvailable = false
            registry.setAvailability(for: modelID, isAvailable: false)
            registry.setLoadState(for: modelID, .unloaded)
        case .unavailable(.modelNotReady):
            statusText = "Model downloading…"
            isAvailable = false
            registry.setAvailability(for: modelID, isAvailable: false)
            registry.setLoadState(for: modelID, .loading)
        case .unavailable(.deviceNotEligible):
            statusText = "Device not supported"
            isAvailable = false
            registry.setAvailability(for: modelID, isAvailable: false)
            registry.setLoadState(for: modelID, .unloaded)
        default:
            statusText = "Unavailable"
            isAvailable = false
            registry.setAvailability(for: modelID, isAvailable: false)
            registry.setLoadState(for: modelID, .unloaded)
        }
    }

    func invalidateSessions() {
        routeClassifierSession = nil
        routeClassifierTurnCount = 0
        explanationSession = nil
        explanationTurnCount = 0
        patchSession = nil
        patchTurnCount = 0
        compactionSession = nil

        sessionManager?.removeSession(id: routeSessionID)
        sessionManager?.removeSession(id: explanationSessionID)
        sessionManager?.removeSession(id: patchSessionID)
        sessionManager?.removeSession(id: compactionSessionID)
    }

    func classifyRoute(query: String, fileList: [String]) async throws -> RouteDecision {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let promptEnvelope = PromptBuilder.routeClassifierPrompt(
            query: query,
            fileList: Array(fileList.prefix(60))
        )

        let session = obtainRouteClassifierSession(systemPrompt: promptEnvelope.system)

        let prompt = Prompt {
            promptEnvelope.user
        }

        let response = try await session.respond(
            to: prompt,
            generating: RouteDecision.self,
            options: GenerationOptions(sampling: .greedy)
        )

        routeClassifierTurnCount += 1
        recordTurn(sessionID: routeSessionID, estimatedTokens: estimateTokens(promptEnvelope.user) + estimateTokens(response.content.route))

        return response.content
    }

    func generateAnswer(query: String, context: String, route: Route) async throws -> String {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let promptEnvelope = PromptBuilder.foundationPrompt(route: route, query: query, repoContext: context)
        let session = obtainToolSession(for: route, systemPrompt: promptEnvelope.system)

        let response = try await session.respond(to: promptEnvelope.user)
        explanationTurnCount += 1
        recordTurn(sessionID: explanationSessionID, estimatedTokens: estimateTokens(promptEnvelope.user) + estimateTokens(response.content))

        return response.content
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
                let session = self.obtainToolSession(for: route, systemPrompt: promptEnvelope.system)

                do {
                    let stream = session.streamResponse(to: promptEnvelope.user)
                    var lastContent = ""
                    for try await partial in stream {
                        lastContent = partial.content
                        continuation.yield(partial.content)
                    }
                    self.explanationTurnCount += 1
                    self.recordTurn(sessionID: self.explanationSessionID, estimatedTokens: self.estimateTokens(promptEnvelope.user) + self.estimateTokens(lastContent))
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
        let extendedSystem = """
        \(promptEnvelope.system)
        Each operation's searchText MUST be an exact verbatim substring found in the file — including all whitespace, indentation, and newlines.
        The replaceText is the new text that will replace it. DO NOT paraphrase or approximate the search text.
        NEVER produce an operation where searchText equals replaceText — that is a no-op and will be rejected.
        To CREATE a new file, set searchText to an empty string and replaceText to the full file content.
        """

        let session = obtainPatchSession(systemPrompt: extendedSystem)

        let prompt = Prompt {
            promptEnvelope.user
        }

        let response = try await session.respond(
            to: prompt,
            generating: GenerablePatchPlan.self,
            options: GenerationOptions(sampling: .greedy)
        )

        patchTurnCount += 1
        recordTurn(sessionID: patchSessionID, estimatedTokens: estimateTokens(promptEnvelope.user) + 200)

        let plan = response.content
        let operations = plan.operations.compactMap { op -> PatchOperation? in
            if !op.searchText.isEmpty && op.searchText == op.replaceText { return nil }
            return PatchOperation(
                filePath: op.filePath,
                searchText: op.searchText,
                replaceText: op.replaceText,
                description: op.description
            )
        }

        return PatchPlan(summary: plan.summary, operations: operations)
    }

    func summarizeConversationMemory(
        priorSummary: String,
        turns: String,
        fileOperationSummaries: String
    ) async throws -> String {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        if compactionSession == nil {
            compactionSession = LanguageModelSession {
                """
                You compress coding-chat memory. Keep critical constraints, decisions, and unresolved tasks.
                Preserve file operation outcomes and avoid repeating obvious details.
                """
            }
            sessionManager?.registerSession(id: compactionSessionID, purpose: .conversationSummary)
        }

        let clippedSummary = String(priorSummary.prefix(1_200))
        let clippedOperations = String(fileOperationSummaries.prefix(1_200))
        let clippedTurns = String(turns.prefix(4_000))

        let prompt = Prompt {
            """
            Existing summary:
            \(clippedSummary)

            File operation summaries:
            \(clippedOperations)

            Older turns to compact:
            \(clippedTurns)

            Return a compact, actionable memory block in under 220 words.
            """
        }

        let response = try await compactionSession!.respond(to: prompt)
        recordTurn(sessionID: compactionSessionID, estimatedTokens: estimateTokens(clippedTurns) + estimateTokens(response.content))
        return response.content
    }

    private func obtainRouteClassifierSession(systemPrompt: String) -> LanguageModelSession {
        if let existing = routeClassifierSession, routeClassifierTurnCount < maxRouteClassifierTurns {
            return existing
        }

        routeClassifierTurnCount = 0
        sessionManager?.removeSession(id: routeSessionID)
        let session = LanguageModelSession {
            systemPrompt
        }
        routeClassifierSession = session
        sessionManager?.registerSession(id: routeSessionID, purpose: .routeClassification)
        return session
    }

    private func obtainToolSession(for route: Route, systemPrompt: String) -> LanguageModelSession {
        if let existing = explanationSession, explanationTurnCount < maxExplanationTurns {
            return existing
        }

        explanationTurnCount = 0
        sessionManager?.removeSession(id: explanationSessionID)

        let tools = buildTools()
        let session: LanguageModelSession
        if !tools.isEmpty {
            session = LanguageModelSession(tools: tools) {
                systemPrompt
                "You have access to tools to read files, search code, and list workspace files. Use them when the provided context is insufficient to answer accurately."
            }
        } else {
            session = LanguageModelSession {
                systemPrompt
            }
        }

        explanationSession = session
        sessionManager?.registerSession(id: explanationSessionID, purpose: .explanation)
        return session
    }

    private func obtainPatchSession(systemPrompt: String) -> LanguageModelSession {
        if let existing = patchSession, patchTurnCount < maxPatchTurns {
            return existing
        }

        patchTurnCount = 0
        sessionManager?.removeSession(id: patchSessionID)

        let tools = buildTools()
        let session: LanguageModelSession
        if !tools.isEmpty {
            session = LanguageModelSession(tools: tools) {
                systemPrompt
                "You have access to tools to read files and search code. Use the read_file tool to get exact file contents before producing patch operations."
            }
        } else {
            session = LanguageModelSession {
                systemPrompt
            }
        }

        patchSession = session
        sessionManager?.registerSession(id: patchSessionID, purpose: .patchPlanning)
        return session
    }

    private func buildTools() -> [any Tool] {
        guard let providers = toolProviders else { return [] }

        let readTool = ReadFileTool(fileProvider: providers.readFile)
        let searchTool = SearchCodeTool(searchProvider: providers.searchCode)
        let listTool = ListFilesTool(filesProvider: providers.listFiles)
        return [readTool, searchTool, listTool]
    }

    private func recordTurn(sessionID: String, estimatedTokens: Int) {
        sessionManager?.recordTurn(sessionID: sessionID, estimatedTokens: estimatedTokens)
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    nonisolated enum ServiceError: Error, LocalizedError, Sendable {
        case unavailable
        case generationFailed(String)

        nonisolated var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Intelligence is not available on this device."
            case .generationFailed(let reason):
                return "Generation failed: \(reason)"
            }
        }
    }
}
