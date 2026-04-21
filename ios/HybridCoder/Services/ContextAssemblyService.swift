import Foundation

/// Pure prompt-context assembly — no workspace I/O beyond what a
/// `WorkspaceLifecycleServicing` instance exposes.
///
/// The real implementations of the static helpers (`buildPromptContext`,
/// `matchRelevantFiles`, `buildRetrievalQuery`) still live on
/// `AIOrchestrator` today and are re-exported here so callers can
/// depend on the service name rather than the orchestrator.
nonisolated enum ContextAssemblyService {
    static func buildPromptContext(
        rawPolicyText: String,
        conversationMemoryBlock: String,
        codeParts: [String],
        totalLimit: Int,
        minCodeBudget: Int,
        maxPolicyBudget: Int,
        maxConversationBudget: Int
    ) -> String {
        AIOrchestrator.buildPromptContext(
            rawPolicyText: rawPolicyText,
            conversationMemoryBlock: conversationMemoryBlock,
            codeParts: codeParts,
            totalLimit: totalLimit,
            minCodeBudget: minCodeBudget,
            maxPolicyBudget: maxPolicyBudget,
            maxConversationBudget: maxConversationBudget
        )
    }

    static func buildRetrievalQuery(baseQuery: String, searchTerms: [String]) -> String {
        AIOrchestrator.buildRetrievalQuery(baseQuery: baseQuery, searchTerms: searchTerms)
    }

    static func matchRelevantFiles(_ hints: [String], within repoFiles: [RepoFile], limit: Int = 2) -> [RepoFile] {
        AIOrchestrator.matchRelevantFiles(hints, within: repoFiles, limit: limit)
    }
}
