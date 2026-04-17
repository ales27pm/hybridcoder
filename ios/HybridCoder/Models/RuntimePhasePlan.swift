import Foundation

nonisolated struct RuntimePhasePlan: Sendable {
    let phases: [Phase]
    let fallback: FallbackMetadata?

    nonisolated struct Phase: Identifiable, Sendable {
        let id: UUID
        let order: Int
        let objective: String
        let actions: [Action]
        let checkpoint: Checkpoint
        let fallback: FallbackMetadata?

        init(
            id: UUID = UUID(),
            order: Int,
            objective: String,
            actions: [Action],
            checkpoint: Checkpoint,
            fallback: FallbackMetadata? = nil
        ) {
            self.id = id
            self.order = order
            self.objective = objective
            self.actions = actions
            self.checkpoint = checkpoint
            self.fallback = fallback
        }
    }

    nonisolated struct Action: Hashable, Sendable {
        let title: String
        let detail: String
        let targetPaths: [String]
    }

    nonisolated struct Checkpoint: Sendable {
        let title: String
        let requiredArtifacts: [String]
        let validationScenarios: [String]
    }

    nonisolated struct FallbackMetadata: Sendable {
        let strategy: Strategy
        let reason: String
        let retryHint: String?

        nonisolated enum Strategy: String, Sendable {
            case narrowScope
            case revertAndRetry
            case requestClarification
            case halt
        }
    }
}
