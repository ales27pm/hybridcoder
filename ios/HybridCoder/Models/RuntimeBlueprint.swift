import Foundation

nonisolated struct RuntimeBlueprint: Sendable {
    let id: UUID
    let goal: String
    let workspace: AgentWorkspaceContext
    let rootPath: String
    let files: [BlueprintFileReference]
    let rules: [BlueprintRule]
    let validationPlan: BlueprintValidationPlan
    let createdAt: Date

    init(
        id: UUID = UUID(),
        goal: String,
        workspace: AgentWorkspaceContext,
        rootPath: String,
        files: [BlueprintFileReference],
        rules: [BlueprintRule],
        validationPlan: BlueprintValidationPlan,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.goal = goal
        self.workspace = workspace
        self.rootPath = rootPath
        self.files = files
        self.rules = rules
        self.validationPlan = validationPlan
        self.createdAt = createdAt
    }
}

nonisolated struct BlueprintFileReference: Hashable, Sendable {
    let path: String
    let reason: String
    let role: Role

    nonisolated enum Role: String, Sendable {
        case entrypoint
        case route
        case screen
        case component
        case service
        case model
        case config
        case test
        case unknown
    }
}

nonisolated struct BlueprintRule: Hashable, Sendable {
    let id: String
    let description: String
    let severity: Severity
    let scopePaths: [String]

    nonisolated enum Severity: String, Sendable {
        case info
        case warning
        case required
    }
}

nonisolated struct BlueprintValidationPlan: Sendable {
    let scenarios: [ValidationScenario]
    let requiredPaths: [String]

    nonisolated struct ValidationScenario: Hashable, Sendable {
        let id: String
        let title: String
        let targetPaths: [String]
    }
}
