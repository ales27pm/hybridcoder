import Foundation

nonisolated enum RetryPolicyEngine {
    static func classifyFailure(
        report: AgentRuntimeReport,
        attempt: Int,
        maxAttempts: Int
    ) -> FailureClassification {
        if report.patchResult.updatedPlan.pendingCount > 0 {
            return FailureClassification(
                category: .patchApply,
                isRetryable: attempt < maxAttempts,
                reason: "Pending patch operations remain after attempt \(attempt).",
                suggestedDelay: nil
            )
        }

        if !report.blockedActions.isEmpty {
            return FailureClassification(
                category: .toolRuntime,
                isRetryable: attempt < maxAttempts,
                reason: "Workspace actions were blocked during execution.",
                suggestedDelay: nil
            )
        }

        if report.validationOutcome.status == .blocked {
            return FailureClassification(
                category: .validation,
                isRetryable: attempt < maxAttempts,
                reason: "Validation gate blocked progression.",
                suggestedDelay: nil
            )
        }

        if !report.patchResult.failures.isEmpty || !report.preflightFailures.isEmpty {
            return FailureClassification(
                category: .dependency,
                isRetryable: attempt < maxAttempts,
                reason: "Patch validation/apply failures detected.",
                suggestedDelay: nil
            )
        }

        FailureClassification(
            category: .unknown,
            isRetryable: false,
            reason: "No retryable runtime failures detected.",
            suggestedDelay: nil
        )
    }

    static func shouldRetry(
        classification: FailureClassification
    ) -> RetryDecision {
        let strategy: RetryDecision.Strategy
        if classification.isRetryable {
            switch classification.category {
            case .validation:
                strategy = .replan
            case .patchApply:
                strategy = .replan
            case .toolRuntime, .dependency, .timeout, .unknown:
                strategy = .retrySamePlan
            }
        } else {
            strategy = .doNotRetry
        }

        RetryDecision(
            shouldRetry: classification.isRetryable,
            strategy: strategy,
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
