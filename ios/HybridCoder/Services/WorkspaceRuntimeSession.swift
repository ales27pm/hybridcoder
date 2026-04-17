import Foundation

actor WorkspaceRuntimeSession {
    let id: UUID
    let goal: String
    let workspace: AgentWorkspaceContext
    let workspaceRoot: URL

    init(
        id: UUID = UUID(),
        goal: String,
        workspace: AgentWorkspaceContext,
        workspaceRoot: URL
    ) {
        self.id = id
        self.goal = goal
        self.workspace = workspace
        self.workspaceRoot = workspaceRoot
    }

    func prepareBlueprint(
        repoAccess: RepoAccessService
    ) async -> RuntimeBlueprint {
        await RuntimeBlueprintBuilder.build(
            goal: goal,
            workspace: workspace,
            repoAccess: repoAccess,
            workspaceRoot: workspaceRoot
        )
    }
}
