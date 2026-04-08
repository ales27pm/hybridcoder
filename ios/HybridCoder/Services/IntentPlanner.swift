import Foundation

nonisolated enum IntentPlanner {
    static func planPatchExecution(
        goal: String,
        patchPlan: PatchPlan,
        workspace: AgentWorkspaceContext,
        strategyStatus: AgentExecutionStep.Status = .planned,
        validationStatus: AgentExecutionStep.Status = .planned,
        coordinationStatus: AgentExecutionStep.Status = .planned,
        applyStatus: AgentExecutionStep.Status = .planned,
        workspaceValidationStatus: AgentExecutionStep.Status = .planned
    ) -> AgentExecutionPlan {
        let operationCount = patchPlan.operations.filter { $0.status == .pending }.count
        let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGoal = normalizedGoal.isEmpty ? patchPlan.summary : normalizedGoal

        return AgentExecutionPlan(
            goal: safeGoal,
            workspace: workspace,
            steps: [
                AgentExecutionStep(
                    title: "Decompose chat request",
                    action: .decomposeIntent,
                    status: .succeeded,
                    detail: safeGoal
                ),
                AgentExecutionStep(
                    title: "Inspect active workspace context",
                    action: .inspectWorkspaceContext,
                    status: .succeeded,
                    detail: workspace.displayName
                ),
                AgentExecutionStep(
                    title: "Select guarded execution strategy",
                    action: .selectExecutionStrategy,
                    status: strategyStatus,
                    detail: "Stay on guarded exact-match patch execution until broader file actions are implemented"
                ),
                AgentExecutionStep(
                    title: "Validate exact-match patch plan",
                    action: .validatePatchPlan(operationCount: operationCount),
                    status: validationStatus,
                    detail: "\(operationCount) pending operation\(operationCount == 1 ? "" : "s")"
                ),
                AgentExecutionStep(
                    title: "Coordinate guarded patch execution",
                    action: .coordinateGuardedPatchExecution,
                    status: coordinationStatus,
                    detail: "Sequence preflight validation, apply, and workspace diagnostics through the runtime coordinator"
                ),
                AgentExecutionStep(
                    title: "Apply guarded workspace edits",
                    action: .applyPatchPlan(operationCount: operationCount),
                    status: applyStatus,
                    detail: "Executed through PatchEngine against the active workspace"
                ),
                AgentExecutionStep(
                    title: "Validate React Native / Expo workspace",
                    action: .validateReactNativeWorkspace,
                    status: workspaceValidationStatus,
                    detail: workspace.isExpoFocused
                        ? "Expo-focused diagnostics"
                        : "Generic workspace guardrail; Expo support not confirmed"
                )
            ]
        )
    }
}
