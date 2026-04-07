import Foundation
import FoundationModels

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

@available(iOS 26.0, *)
@Observable
@MainActor
final class FoundationModelService {
    private let registry: ModelRegistry
    private let modelID: String

    var statusText: String = "Checking…"
    var isAvailable: Bool = false
    var isGenerating: Bool = false

    init(registry: ModelRegistry, modelID: String) {
        self.registry = registry
        self.modelID = modelID
        refreshStatus()
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

    func classifyRoute(query: String, fileList: [String]) async throws -> RouteDecision {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let promptEnvelope = PromptBuilder.routeClassifierPrompt(
            query: query,
            fileList: Array(fileList.prefix(60))
        )

        let session = LanguageModelSession {
            promptEnvelope.system
        }

        let prompt = Prompt {
            promptEnvelope.user
        }

        let response = try await session.respond(
            to: prompt,
            generating: RouteDecision.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content
    }

    func generateAnswer(query: String, context: String, route: Route) async throws -> String {
        guard isAvailable else { throw ServiceError.unavailable }
        isGenerating = true
        defer { isGenerating = false }

        let promptEnvelope = PromptBuilder.foundationPrompt(route: route, query: query, repoContext: context)

        let session = LanguageModelSession {
            promptEnvelope.system
        }

        let response = try await session.respond(to: promptEnvelope.user)
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

                let session = LanguageModelSession {
                    promptEnvelope.system
                }

                do {
                    let stream = session.streamResponse(to: promptEnvelope.user)
                    for try await partial in stream {
                        continuation.yield(partial.content)
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
        let session = LanguageModelSession {
            """
            \(promptEnvelope.system)
            Each operation's searchText MUST be an exact verbatim substring found in the file — including all whitespace, indentation, and newlines.
            The replaceText is the new text that will replace it. DO NOT paraphrase or approximate the search text.
            NEVER produce an operation where searchText equals replaceText — that is a no-op and will be rejected.
            To CREATE a new file, set searchText to an empty string and replaceText to the full file content.
            """
        }

        let prompt = Prompt {
            promptEnvelope.user
        }

        let response = try await session.respond(
            to: prompt,
            generating: GenerablePatchPlan.self,
            options: GenerationOptions(sampling: .greedy)
        )

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

        let session = LanguageModelSession {
            """
            You compress coding-chat memory. Keep critical constraints, decisions, and unresolved tasks.
            Preserve file operation outcomes and avoid repeating obvious details.
            """
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

        let response = try await session.respond(to: prompt)
        return response.content
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
