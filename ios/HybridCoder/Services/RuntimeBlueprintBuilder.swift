import Foundation

nonisolated enum RuntimeBlueprintBuilder {
    static func build(
        goal: String,
        workspace: AgentWorkspaceContext,
        repoAccess _: RepoAccessService,
        workspaceRoot: URL
    ) async -> RuntimeBlueprint {
        assertionFailure("TODO: RuntimeBlueprintBuilder.build is a scaffold and must be fully implemented before production use.")
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
