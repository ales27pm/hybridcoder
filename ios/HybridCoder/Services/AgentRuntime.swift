import Foundation

nonisolated struct AgentPlannerLayerSummary: Sendable {
    let strategy: String
    let detail: String
}

nonisolated struct AgentCoordinatorLayerSummary: Sendable {
    let phase: String
    let detail: String
}

nonisolated struct AgentRuntimeReport: Sendable {
    let executionPlan: AgentExecutionPlan
    let plannedActions: [AgentPlannedAction]
    let executedActions: [AgentActionExecutionResult]
    let blockedActions: [AgentActionExecutionResult]
    let validationOutcome: AgentValidationOutcome
    let patchResult: PatchEngine.PatchResult
    let preflightFailures: [PatchEngine.OperationFailure]
    let workspaceDiagnostics: [ProjectDiagnostic]
    let didMakeMeaningfulWorkspaceProgress: Bool
    let blockers: [String]
    let plannerSummary: AgentPlannerLayerSummary
    let coordinatorSummary: AgentCoordinatorLayerSummary

    var didExecuteWorkspaceActions: Bool {
        didMakeMeaningfulWorkspaceProgress
    }

    var chatSummary: String {
        var lines: [String] = []
        let changedFiles = patchResult.changedFiles
        let succeededWriteActions = executedActions.filter { result in
            guard result.status == .succeeded else { return false }
            switch result.action {
            case .createFile, .updateFile, .renameFile, .deleteFile:
                return true
            case .inspectFile, .validateWorkspace:
                return false
            }
        }

        if didMakeMeaningfulWorkspaceProgress {
            lines.append("Agent runtime completed \(succeededWriteActions.count) workspace action\(succeededWriteActions.count == 1 ? "" : "s") and made meaningful progress.")
        } else if let firstBlocked = blockedActions.first {
            lines.append("Agent runtime blocked on \(firstBlocked.action.summary.lowercased()).")
        } else {
            lines.append("Agent runtime finished its action pass without meaningful workspace changes.")
        }

        lines.append("Workspace focus: \(executionPlan.workspace.displayName).")
        lines.append("Planned actions: \(plannedActions.count). Executed actions: \(executedActions.count). Blocked actions: \(blockedActions.count).")
        lines.append("Planner: \(plannerSummary.strategy).")
        lines.append("Coordinator: \(coordinatorSummary.phase).")
        lines.append("Validation: \(validationOutcome.detail)")

        if !changedFiles.isEmpty {
            let preview = changedFiles.prefix(4).joined(separator: ", ")
            lines.append("Changed paths: \(preview).")
        }

        if !blockers.isEmpty {
            lines.append("Blockers: \(blockers.prefix(3).joined(separator: "; ")).")
        }

        return lines.joined(separator: "\n")
    }
}

nonisolated enum AgentRuntime {
    static func makeReport(from outcome: AgentExecutionOutcome) -> AgentRuntimeReport {
        let workspace = outcome.executionPlan.workspace
        let plannedActions = outcome.executionPlan.actions
        let blockedActions = outcome.blockedActions
        let executedActions = outcome.executedActions
        let goalDerivedWriteActions = plannedActions.filter { action in
            switch action.action {
            case .createFile(_, let strategy, _), .updateFile(_, let strategy, _):
                if case .direct = strategy {
                    return true
                }
                return false
            case .renameFile, .deleteFile:
                return true
            case .inspectFile, .validateWorkspace:
                return false
            }
        }

        let plannerDetail: String
        if let fallbackPlan = outcome.executionPlan.fallbackPatchPlan, fallbackPlan.pendingCount > 0 {
            if goalDerivedWriteActions.isEmpty {
                plannerDetail = "Planner turned \(fallbackPlan.pendingCount) pending patch operation\(fallbackPlan.pendingCount == 1 ? "" : "s") into ordered workspace actions for \(workspace.displayName.lowercased())."
            } else {
                plannerDetail = "Planner turned \(fallbackPlan.pendingCount) pending patch operation\(fallbackPlan.pendingCount == 1 ? "" : "s") into ordered workspace actions and appended \(goalDerivedWriteActions.count) goal-derived write action\(goalDerivedWriteActions.count == 1 ? "" : "s")."
            }
        } else if !goalDerivedWriteActions.isEmpty {
            plannerDetail = "Planner built \(goalDerivedWriteActions.count) goal-derived write action\(goalDerivedWriteActions.count == 1 ? "" : "s") directly from the user goal and workspace context."
        } else {
            plannerDetail = "Planner built an exploratory workspace-action sequence from the user goal and current workspace context."
        }

        let coordinatorPhase: String
        if !blockedActions.isEmpty {
            coordinatorPhase = "Stopped on blocked workspace action"
        } else if outcome.didMakeMeaningfulWorkspaceProgress {
            coordinatorPhase = "Executed ordered workspace actions and validated"
        } else {
            coordinatorPhase = "Inspected workspace and validated without writes"
        }

        return AgentRuntimeReport(
            executionPlan: outcome.executionPlan,
            plannedActions: plannedActions,
            executedActions: executedActions,
            blockedActions: blockedActions,
            validationOutcome: outcome.validationOutcome,
            patchResult: outcome.patchResult,
            preflightFailures: outcome.preflightFailures,
            workspaceDiagnostics: outcome.validationOutcome.diagnostics,
            didMakeMeaningfulWorkspaceProgress: outcome.didMakeMeaningfulWorkspaceProgress,
            blockers: outcome.blockers,
            plannerSummary: .init(
                strategy: "Action-oriented workspace planning with patch fallback",
                detail: plannerDetail
            ),
            coordinatorSummary: .init(
                phase: coordinatorPhase,
                detail: "Coordinator inspected files before writes, executed actions in order, stopped on blockers, and collected validation output."
            )
        )
    }
}
