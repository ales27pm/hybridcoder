import Foundation

nonisolated enum RuntimeBlueprintBuilder {
    static func build(
        goal: String,
        workspace: AgentWorkspaceContext,
        repoAccess: RepoAccessService,
        workspaceRoot: URL
    ) async -> RuntimeBlueprint {
        RuntimeBlueprint(
            goal: goal,
            workspace: workspace,
            rootPath: workspaceRoot.path(percentEncoded: false),
            files: [],
            rules: [],
            validationPlan: BlueprintValidationPlan(scenarios: [], requiredPaths: [])
        )
    }
}
