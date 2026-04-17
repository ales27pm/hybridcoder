import Foundation

nonisolated enum RuntimeBlueprintBuilder {
    static func build(
        goal: String,
        workspace: AgentWorkspaceContext,
        repoAccess _: RepoAccessService,
        workspaceRoot: URL
    ) async -> RuntimeBlueprint {
        // TODO: Incorporate repo-aware blueprint construction.
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
