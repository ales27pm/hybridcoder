import Foundation

nonisolated struct AgentRuntimeReport: Sendable {
    let executionPlan: AgentExecutionPlan
    let patchResult: PatchEngine.PatchResult
    let preflightFailures: [PatchEngine.OperationFailure]
    let workspaceDiagnostics: [ProjectDiagnostic]
    let didExecuteWorkspaceActions: Bool
    let blockers: [String]

    var chatSummary: String {
        let changedCount = patchResult.changedFiles.count
        let changedNoun = changedCount == 1 ? "file" : "files"
        let diagnosticSummary = Self.diagnosticSummary(workspaceDiagnostics)

        var lines: [String] = []
        if didExecuteWorkspaceActions {
            lines.append("Agent runtime applied guarded workspace actions: \(patchResult.summary).")
        } else if !blockers.isEmpty {
            lines.append("Agent runtime blocked before writing: \(blockers.joined(separator: "; ")).")
        } else {
            lines.append("Agent runtime completed without writing changes.")
        }

        lines.append("Workspace focus: \(executionPlan.workspace.displayName).")

        if changedCount > 0 {
            let changedFiles = patchResult.changedFiles.prefix(4).joined(separator: ", ")
            lines.append("Changed \(changedCount) \(changedNoun): \(changedFiles).")
        }

        if let diagnosticSummary {
            lines.append("Validation: \(diagnosticSummary).")
        }

        return lines.joined(separator: "\n")
    }

    private static func diagnosticSummary(_ diagnostics: [ProjectDiagnostic]) -> String? {
        guard !diagnostics.isEmpty else { return nil }

        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let infos = diagnostics.filter { $0.severity == .info }.count
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        if infos > 0 { parts.append("\(infos) info") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

nonisolated enum AgentRuntime {
    static func makeBlockedPatchReport(
        goal: String,
        patchPlan: PatchPlan,
        workspace: AgentWorkspaceContext,
        preflightFailures: [PatchEngine.OperationFailure],
        workspaceDiagnostics: [ProjectDiagnostic]
    ) -> AgentRuntimeReport {
        let executionPlan = IntentPlanner.planPatchExecution(
            goal: goal,
            patchPlan: patchPlan,
            workspace: workspace,
            validationStatus: .blocked,
            applyStatus: .skipped,
            workspaceValidationStatus: workspaceDiagnostics.isEmpty ? .succeeded : .blocked
        )

        let failedOperationIDs = Set(preflightFailures.map(\.operationID))
        let updatedPlan = PatchPlan(
            id: patchPlan.id,
            summary: patchPlan.summary,
            operations: patchPlan.operations.map { operation in
                guard failedOperationIDs.contains(operation.id) else { return operation }
                return PatchOperation(
                    id: operation.id,
                    filePath: operation.filePath,
                    searchText: operation.searchText,
                    replaceText: operation.replaceText,
                    description: operation.description,
                    status: .failed
                )
            },
            createdAt: patchPlan.createdAt
        )
        let patchResult = PatchEngine.PatchResult(
            updatedPlan: updatedPlan,
            changedFiles: [],
            failures: preflightFailures
        )

        return AgentRuntimeReport(
            executionPlan: executionPlan,
            patchResult: patchResult,
            preflightFailures: preflightFailures,
            workspaceDiagnostics: workspaceDiagnostics,
            didExecuteWorkspaceActions: false,
            blockers: preflightFailures.map { "\($0.filePath): \($0.reason)" }
        )
    }

    static func makeAppliedPatchReport(
        goal: String,
        patchPlan: PatchPlan,
        workspace: AgentWorkspaceContext,
        patchResult: PatchEngine.PatchResult,
        workspaceDiagnostics: [ProjectDiagnostic]
    ) -> AgentRuntimeReport {
        let executionPlan = IntentPlanner.planPatchExecution(
            goal: goal,
            patchPlan: patchPlan,
            workspace: workspace,
            validationStatus: .succeeded,
            applyStatus: patchResult.failures.isEmpty ? .succeeded : .blocked,
            workspaceValidationStatus: workspaceDiagnostics.contains { $0.severity == .error } ? .blocked : .succeeded
        )

        return AgentRuntimeReport(
            executionPlan: executionPlan,
            patchResult: patchResult,
            preflightFailures: [],
            workspaceDiagnostics: workspaceDiagnostics,
            didExecuteWorkspaceActions: !patchResult.changedFiles.isEmpty,
            blockers: patchResult.failures.map { "\($0.filePath): \($0.reason)" }
        )
    }
}
