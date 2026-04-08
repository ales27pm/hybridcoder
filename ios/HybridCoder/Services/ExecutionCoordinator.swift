import Foundation

enum ExecutionCoordinator {
    struct Dependencies {
        let inspectFile: @Sendable (String) async -> AgentWorkspaceFileSnapshot
        let validatePatchPlan: @Sendable (PatchPlan) async -> [PatchEngine.OperationFailure]
        let applyPatchPlan: @Sendable (PatchPlan) async throws -> PatchEngine.PatchResult
        let createFile: @Sendable (String, String) async throws -> Void
        let updateFile: @Sendable (String, String) async throws -> Void
        let renameFile: @Sendable (String, String) async throws -> Void
        let deleteFile: @Sendable (String) async throws -> Void
        let validateWorkspace: @Sendable () async -> [ProjectDiagnostic]
    }

    static func executeActionPlan(
        _ plan: AgentExecutionPlan,
        dependencies: Dependencies
    ) async throws -> AgentExecutionOutcome {
        var actionResults: [AgentActionExecutionResult] = []
        var blockers: [String] = []
        var preflightFailures: [PatchEngine.OperationFailure] = []
        var changedFiles: Set<String> = []
        var inspectedFiles: [String: AgentWorkspaceFileSnapshot] = [:]
        var aggregatedPlan = plan.fallbackPatchPlan ?? PatchPlan(summary: plan.goal, operations: [])
        var patchFailures: [PatchEngine.OperationFailure] = []
        var didMakeMeaningfulWorkspaceProgress = false
        var didBlock = false
        var validationOutcome: AgentValidationOutcome?

        for action in plan.actions {
            if didBlock {
                actionResults.append(
                    AgentActionExecutionResult(
                        for: action,
                        status: .skipped,
                        detail: "Skipped because an earlier workspace action was blocked."
                    )
                )
                continue
            }

            switch action.action {
            case .inspectFile(let path, _):
                let snapshot = await dependencies.inspectFile(path)
                inspectedFiles[path] = snapshot
                let detail = snapshot.exists
                    ? "Inspected \(path) before any write action."
                    : "Inspected \(path); file does not exist yet."
                actionResults.append(
                    AgentActionExecutionResult(
                        for: action,
                        status: .succeeded,
                        detail: detail
                    )
                )

            case .createFile(let path, let strategy, _):
                let snapshot = await ensureInspection(
                    for: path,
                    inspectedFiles: &inspectedFiles,
                    dependencies: dependencies
                )
                if snapshot.exists {
                    let blocker = "\(path): file already exists, so create action was blocked."
                    let failures = patchBackedFailures(
                        for: strategy,
                        reason: "File already exists"
                    )
                    preflightFailures.append(contentsOf: failures)
                    aggregatedPlan = mergeStatuses(
                        from: patchPlan(from: strategy),
                        failures: failures,
                        into: aggregatedPlan
                    )
                    blockers.append(blocker)
                    actionResults.append(
                        AgentActionExecutionResult(
                            for: action,
                            status: .blocked,
                            detail: "Create action blocked because \(path) already exists.",
                            blockers: [blocker]
                        )
                    )
                    didBlock = true
                    continue
                }

                let execution = try await executeWriteAction(
                    action,
                    strategy: strategy,
                    path: path,
                    directWrite: dependencies.createFile,
                    aggregatedPlan: &aggregatedPlan,
                    preflightFailures: &preflightFailures,
                    patchFailures: &patchFailures,
                    changedFiles: &changedFiles,
                    didMakeMeaningfulWorkspaceProgress: &didMakeMeaningfulWorkspaceProgress,
                    allowMissingInspectedFile: true,
                    existingSnapshot: snapshot,
                    dependencies: dependencies
                )
                actionResults.append(execution.result)
                blockers.append(contentsOf: execution.result.blockers)
                if execution.didBlock {
                    didBlock = true
                } else {
                    inspectedFiles[path] = AgentWorkspaceFileSnapshot(path: path, exists: true, content: nil)
                }

            case .updateFile(let path, let strategy, _):
                let snapshot = await ensureInspection(
                    for: path,
                    inspectedFiles: &inspectedFiles,
                    dependencies: dependencies
                )
                if !snapshot.exists {
                    let blocker = "\(path): file does not exist, so update action was blocked."
                    let failures = patchBackedFailures(
                        for: strategy,
                        reason: "File not found"
                    )
                    preflightFailures.append(contentsOf: failures)
                    aggregatedPlan = mergeStatuses(
                        from: patchPlan(from: strategy),
                        failures: failures,
                        into: aggregatedPlan
                    )
                    blockers.append(blocker)
                    actionResults.append(
                        AgentActionExecutionResult(
                            for: action,
                            status: .blocked,
                            detail: "Update action blocked because \(path) could not be inspected as an existing file.",
                            blockers: [blocker]
                        )
                    )
                    didBlock = true
                    continue
                }

                let execution = try await executeWriteAction(
                    action,
                    strategy: strategy,
                    path: path,
                    directWrite: dependencies.updateFile,
                    aggregatedPlan: &aggregatedPlan,
                    preflightFailures: &preflightFailures,
                    patchFailures: &patchFailures,
                    changedFiles: &changedFiles,
                    didMakeMeaningfulWorkspaceProgress: &didMakeMeaningfulWorkspaceProgress,
                    allowMissingInspectedFile: false,
                    existingSnapshot: snapshot,
                    dependencies: dependencies
                )
                actionResults.append(execution.result)
                blockers.append(contentsOf: execution.result.blockers)
                if execution.didBlock {
                    didBlock = true
                } else {
                    inspectedFiles[path] = AgentWorkspaceFileSnapshot(path: path, exists: true, content: nil)
                }

            case .renameFile(let from, let to, _):
                let sourceSnapshot = await ensureInspection(
                    for: from,
                    inspectedFiles: &inspectedFiles,
                    dependencies: dependencies
                )
                if !sourceSnapshot.exists {
                    let blocker = "\(from): source file does not exist, so rename action was blocked."
                    blockers.append(blocker)
                    actionResults.append(
                        AgentActionExecutionResult(
                            for: action,
                            status: .blocked,
                            detail: "Rename action blocked because the source file was not found.",
                            blockers: [blocker]
                        )
                    )
                    didBlock = true
                    continue
                }

                let destinationSnapshot = await ensureInspection(
                    for: to,
                    inspectedFiles: &inspectedFiles,
                    dependencies: dependencies
                )
                if destinationSnapshot.exists {
                    let blocker = "\(to): destination already exists, so rename action was blocked."
                    blockers.append(blocker)
                    actionResults.append(
                        AgentActionExecutionResult(
                            for: action,
                            status: .blocked,
                            detail: "Rename action blocked because the destination path already exists.",
                            blockers: [blocker]
                        )
                    )
                    didBlock = true
                    continue
                }

                try await dependencies.renameFile(from, to)
                changedFiles.insert(from)
                changedFiles.insert(to)
                didMakeMeaningfulWorkspaceProgress = true
                actionResults.append(
                    AgentActionExecutionResult(
                        for: action,
                        status: .succeeded,
                        detail: "Renamed \(from) to \(to).",
                        changedFiles: [from, to]
                    )
                )
                inspectedFiles[from] = AgentWorkspaceFileSnapshot(path: from, exists: false, content: nil)
                inspectedFiles[to] = AgentWorkspaceFileSnapshot(path: to, exists: true, content: nil)

            case .deleteFile(let path, _):
                let snapshot = await ensureInspection(
                    for: path,
                    inspectedFiles: &inspectedFiles,
                    dependencies: dependencies
                )
                if !snapshot.exists {
                    let blocker = "\(path): file does not exist, so delete action was blocked."
                    blockers.append(blocker)
                    actionResults.append(
                        AgentActionExecutionResult(
                            for: action,
                            status: .blocked,
                            detail: "Delete action blocked because the file was not found.",
                            blockers: [blocker]
                        )
                    )
                    didBlock = true
                    continue
                }

                try await dependencies.deleteFile(path)
                changedFiles.insert(path)
                didMakeMeaningfulWorkspaceProgress = true
                actionResults.append(
                    AgentActionExecutionResult(
                        for: action,
                        status: .succeeded,
                        detail: "Deleted \(path).",
                        changedFiles: [path]
                    )
                )
                inspectedFiles[path] = AgentWorkspaceFileSnapshot(path: path, exists: false, content: nil)

            case .validateWorkspace:
                let diagnostics = await dependencies.validateWorkspace()
                validationOutcome = makeValidationOutcome(from: diagnostics)
                if validationOutcome?.status == .blocked, let detail = validationOutcome?.detail {
                    blockers.append(detail)
                }
                actionResults.append(
                    AgentActionExecutionResult(
                        for: action,
                        status: validationOutcome?.status ?? .succeeded,
                        detail: validationOutcome?.detail ?? "Validation completed."
                    )
                )
            }
        }

        if validationOutcome == nil {
            let diagnostics = await dependencies.validateWorkspace()
            validationOutcome = makeValidationOutcome(from: diagnostics)
        }

        let finalPatchResult = PatchEngine.PatchResult(
            updatedPlan: aggregatedPlan,
            changedFiles: Array(changedFiles).sorted(),
            failures: preflightFailures + patchFailures
        )

        return AgentExecutionOutcome(
            executionPlan: plan,
            actionResults: actionResults,
            validationOutcome: validationOutcome ?? AgentValidationOutcome(
                status: .succeeded,
                diagnostics: [],
                detail: "Validation completed without diagnostics."
            ),
            patchResult: finalPatchResult,
            preflightFailures: preflightFailures,
            blockers: blockers,
            didMakeMeaningfulWorkspaceProgress: didMakeMeaningfulWorkspaceProgress
        )
    }

    private static func ensureInspection(
        for path: String,
        inspectedFiles: inout [String: AgentWorkspaceFileSnapshot],
        dependencies: Dependencies
    ) async -> AgentWorkspaceFileSnapshot {
        if let existing = inspectedFiles[path] {
            return existing
        }

        let snapshot = await dependencies.inspectFile(path)
        inspectedFiles[path] = snapshot
        return snapshot
    }

    private static func executeWriteAction(
        _ action: AgentPlannedAction,
        strategy: AgentWorkspaceAction.WriteStrategy,
        path: String,
        directWrite: @Sendable (String, String) async throws -> Void,
        aggregatedPlan: inout PatchPlan,
        preflightFailures: inout [PatchEngine.OperationFailure],
        patchFailures: inout [PatchEngine.OperationFailure],
        changedFiles: inout Set<String>,
        didMakeMeaningfulWorkspaceProgress: inout Bool,
        allowMissingInspectedFile: Bool,
        existingSnapshot: AgentWorkspaceFileSnapshot,
        dependencies: Dependencies
    ) async throws -> (result: AgentActionExecutionResult, didBlock: Bool) {
        switch strategy {
        case .direct(let contents):
            if !allowMissingInspectedFile && !existingSnapshot.exists {
                let blocker = "\(path): direct write requires an existing file."
                return (
                    AgentActionExecutionResult(
                        for: action,
                        status: .blocked,
                        detail: "Write action blocked because the inspected file was missing.",
                        blockers: [blocker]
                    ),
                    true
                )
            }

            try await directWrite(path, contents)
            changedFiles.insert(path)
            didMakeMeaningfulWorkspaceProgress = true
            return (
                AgentActionExecutionResult(
                    for: action,
                    status: .succeeded,
                    detail: "Executed \(action.action.summary.lowercased()).",
                    changedFiles: [path]
                ),
                false
            )

        case .patchPlan(let patchPlan):
            let failures = await dependencies.validatePatchPlan(patchPlan)
            if !failures.isEmpty {
                preflightFailures.append(contentsOf: failures)
                aggregatedPlan = mergeStatuses(from: patchPlan, failures: failures, into: aggregatedPlan)
                let blockerMessages = failures.map { "\($0.filePath): \($0.reason)" }
                return (
                    AgentActionExecutionResult(
                        for: action,
                        status: .blocked,
                        detail: "Write action blocked during patch preflight validation.",
                        blockers: blockerMessages
                    ),
                    true
                )
            }

            let patchResult = try await dependencies.applyPatchPlan(patchPlan)
            aggregatedPlan = mergeStatuses(from: patchResult.updatedPlan, into: aggregatedPlan)
            patchFailures.append(contentsOf: patchResult.failures)
            changedFiles.formUnion(patchResult.changedFiles)

            if !patchResult.changedFiles.isEmpty {
                didMakeMeaningfulWorkspaceProgress = true
            }

            if !patchResult.failures.isEmpty {
                let blockerMessages = patchResult.failures.map { "\($0.filePath): \($0.reason)" }
                return (
                    AgentActionExecutionResult(
                        for: action,
                        status: .blocked,
                        detail: "Patch-backed write action stopped after apply failures.",
                        changedFiles: patchResult.changedFiles,
                        blockers: blockerMessages
                    ),
                    true
                )
            }

            return (
                AgentActionExecutionResult(
                    for: action,
                    status: .succeeded,
                    detail: "Executed \(action.action.summary.lowercased()) through the guarded patch fallback.",
                    changedFiles: patchResult.changedFiles
                ),
                false
            )
        }
    }

    private static func mergeStatuses(
        from partialPlan: PatchPlan,
        into aggregatedPlan: PatchPlan
    ) -> PatchPlan {
        let statuses = Dictionary(uniqueKeysWithValues: partialPlan.operations.map { ($0.id, $0.status) })
        let updatedOperations = aggregatedPlan.operations.map { operation in
            guard let status = statuses[operation.id] else { return operation }
            return PatchOperation(
                id: operation.id,
                filePath: operation.filePath,
                searchText: operation.searchText,
                replaceText: operation.replaceText,
                description: operation.description,
                status: status
            )
        }

        return PatchPlan(
            id: aggregatedPlan.id,
            summary: aggregatedPlan.summary,
            operations: updatedOperations,
            createdAt: aggregatedPlan.createdAt
        )
    }

    private static func mergeStatuses(
        from partialPlan: PatchPlan?,
        failures: [PatchEngine.OperationFailure],
        into aggregatedPlan: PatchPlan
    ) -> PatchPlan {
        guard let partialPlan else { return aggregatedPlan }
        let failedIDs = Set(failures.map(\.operationID))
        let failedPlan = PatchPlan(
            id: partialPlan.id,
            summary: partialPlan.summary,
            operations: partialPlan.operations.map { operation in
                guard failedIDs.contains(operation.id) else { return operation }
                return PatchOperation(
                    id: operation.id,
                    filePath: operation.filePath,
                    searchText: operation.searchText,
                    replaceText: operation.replaceText,
                    description: operation.description,
                    status: .failed
                )
            },
            createdAt: partialPlan.createdAt
        )
        return mergeStatuses(from: failedPlan, into: aggregatedPlan)
    }

    private static func patchPlan(from strategy: AgentWorkspaceAction.WriteStrategy) -> PatchPlan? {
        switch strategy {
        case .direct:
            return nil
        case .patchPlan(let patchPlan):
            return patchPlan
        }
    }

    private static func patchBackedFailures(
        for strategy: AgentWorkspaceAction.WriteStrategy,
        reason: String
    ) -> [PatchEngine.OperationFailure] {
        guard case .patchPlan(let patchPlan) = strategy else { return [] }
        return patchPlan.operations.map { operation in
            PatchEngine.OperationFailure(
                operationID: operation.id,
                filePath: operation.filePath,
                reason: reason
            )
        }
    }

    private static func makeValidationOutcome(from diagnostics: [ProjectDiagnostic]) -> AgentValidationOutcome {
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        let infos = diagnostics.filter { $0.severity == .info }.count

        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        if infos > 0 { parts.append("\(infos) info") }

        let summary = parts.isEmpty ? "Validation completed without diagnostics." : "Validation found \(parts.joined(separator: ", "))."

        return AgentValidationOutcome(
            status: errors > 0 ? .blocked : .succeeded,
            diagnostics: diagnostics,
            detail: summary
        )
    }
}
