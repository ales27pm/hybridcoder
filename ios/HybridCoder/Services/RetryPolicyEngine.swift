import Foundation

nonisolated enum RetryPolicyEngine {
    static func classifyFailure(
        report: AgentRuntimeReport,
        attempt: Int,
        maxAttempts: Int
    ) -> FailureClassification {
        // TODO: Derive classification details from AgentRuntimeReport and align with AIOrchestrator.shouldRetryAgentRuntime(after:).
        let _ = report
        FailureClassification(
            category: .unknown,
            isRetryable: attempt < maxAttempts,
            reason: "TODO: derive reason from AgentRuntimeReport",
            suggestedDelay: nil
        )
    }

    static func shouldRetry(
        classification: FailureClassification,
        attempt _: Int,
        maxAttempts _: Int
    ) -> RetryDecision {
        RetryDecision(
            shouldRetry: classification.isRetryable,
            strategy: classification.isRetryable ? .retrySamePlan : .doNotRetry,
            reason: classification.reason
        )
    }
}

nonisolated struct FailureClassification: Sendable {
    let category: Category
    let isRetryable: Bool
    let reason: String
    let suggestedDelay: TimeInterval?

    nonisolated enum Category: String, Sendable {
        case validation
        case patchApply
        case toolRuntime
        case dependency
        case timeout
        case unknown
    }
}

nonisolated struct RetryDecision: Sendable {
    let shouldRetry: Bool
    let strategy: Strategy
    let reason: String

    nonisolated enum Strategy: String, Sendable {
        case retrySamePlan
        case replan
        case reduceScope
        case doNotRetry
    }
}
