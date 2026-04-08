import Foundation

enum ExecutionCoordinator {
    struct Dependencies {
        let validatePatchPlan: @Sendable (PatchPlan) async -> [PatchEngine.OperationFailure]
        let applyPatchPlan: @Sendable (PatchPlan) async throws -> PatchEngine.PatchResult
        let validateWorkspace: @Sendable () async -> [ProjectDiagnostic]
    }

    static func executePatchPlan(
        goal: String,
        patchPlan: PatchPlan,
        workspace: AgentWorkspaceContext,
        dependencies: Dependencies
    ) async throws -> AgentRuntimeReport {
        let preflightFailures = await dependencies.validatePatchPlan(patchPlan)

        if !preflightFailures.isEmpty {
            let workspaceDiagnostics = await dependencies.validateWorkspace()
            return AgentRuntime.makeBlockedPatchReport(
                goal: goal,
                patchPlan: patchPlan,
                workspace: workspace,
                preflightFailures: preflightFailures,
                workspaceDiagnostics: workspaceDiagnostics
            )
        }

        let patchResult = try await dependencies.applyPatchPlan(patchPlan)
        let workspaceDiagnostics = await dependencies.validateWorkspace()

        return AgentRuntime.makeAppliedPatchReport(
            goal: goal,
            patchPlan: patchPlan,
            workspace: workspace,
            patchResult: patchResult,
            workspaceDiagnostics: workspaceDiagnostics
        )
    }
}
