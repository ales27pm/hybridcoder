import Foundation

nonisolated struct AgentWorkspaceContext: Sendable {
    let kind: Kind
    let projectName: String
    let projectKind: ProjectKind?
    let entryFile: String?
    let hasExpoRouter: Bool
    let dependencies: [String]

    nonisolated enum Kind: String, Sendable {
        case prototype
        case importedExpo
        case importedGeneric
        case unknown
    }

    var isExpoFocused: Bool {
        kind == .prototype || kind == .importedExpo || projectKind?.isExpo == true
    }

    var displayName: String {
        switch kind {
        case .prototype:
            return "Prototype Expo workspace"
        case .importedExpo:
            return "Imported Expo workspace"
        case .importedGeneric:
            return "Imported generic workspace"
        case .unknown:
            return "Unknown workspace"
        }
    }
}

nonisolated struct AgentExecutionPlan: Sendable {
    let goal: String
    let workspace: AgentWorkspaceContext
    let steps: [AgentExecutionStep]
}

nonisolated struct AgentExecutionStep: Identifiable, Sendable {
    let id: UUID
    let title: String
    let action: AgentWorkspaceAction
    let status: Status
    let detail: String

    nonisolated enum Status: String, Sendable {
        case planned
        case running
        case succeeded
        case blocked
        case skipped
    }

    init(
        id: UUID = UUID(),
        title: String,
        action: AgentWorkspaceAction,
        status: Status,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.status = status
        self.detail = detail
    }
}

nonisolated enum AgentWorkspaceAction: Sendable, Equatable {
    case decomposeIntent
    case validatePatchPlan(operationCount: Int)
    case applyPatchPlan(operationCount: Int)
    case validateReactNativeWorkspace
}

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
    static func makePatchExecutionPlan(
        goal: String,
        patchPlan: PatchPlan,
        workspace: AgentWorkspaceContext,
        validationStatus: AgentExecutionStep.Status = .planned,
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
                    title: "Validate exact-match patch plan",
                    action: .validatePatchPlan(operationCount: operationCount),
                    status: validationStatus,
                    detail: "\(operationCount) pending operation\(operationCount == 1 ? "" : "s")"
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

    static func makeBlockedPatchReport(
        goal: String,
        patchPlan: PatchPlan,
        workspace: AgentWorkspaceContext,
        preflightFailures: [PatchEngine.OperationFailure],
        workspaceDiagnostics: [ProjectDiagnostic]
    ) -> AgentRuntimeReport {
        let executionPlan = makePatchExecutionPlan(
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
        let executionPlan = makePatchExecutionPlan(
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
