import Foundation

/// Owns the agent-runtime loop: goal execution, phase planning, retry
/// policy, workspace-mutation callbacks, KPI recording.
///
/// Forwarding protocol today — the concrete implementation still lives
/// on `AIOrchestrator`. This is the single mutation entry point: every
/// workspace change goes through `AgentRuntime` and its strategies
/// (see `AgentActionStrategy`), never through `PatchEngine` directly.
@MainActor
protocol RuntimeExecutionServicing: AnyObject {
    func executeGoalWithAgentRuntime(
        goal: String,
        patchPlanningContext: String,
        includesRouteClassifier: Bool
    ) async throws -> AgentRuntimeReport

    func executePatchPlanWithAgentRuntime(_ plan: PatchPlan, userGoal: String?) async throws -> AgentRuntimeReport

    func applyPatch(_ plan: PatchPlan) async throws -> PatchEngine.PatchResult
}

extension AIOrchestrator: RuntimeExecutionServicing {}
