import Foundation

nonisolated enum IntentPlanner {
    static func planActions(
        goal: String,
        workspace: AgentWorkspaceContext,
        patchPlan: PatchPlan? = nil
    ) -> AgentExecutionPlan {
        let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGoal = normalizedGoal.isEmpty ? (patchPlan?.summary ?? workspace.displayName) : normalizedGoal
        var actions: [AgentPlannedAction] = []

        if let patchPlan {
            actions.append(contentsOf: planPatchBackedActions(goal: safeGoal, patchPlan: patchPlan))
        }

        if actions.isEmpty {
            actions.append(contentsOf: exploratoryActions(goal: safeGoal, workspace: workspace))
        }

        actions.append(
            AgentPlannedAction(
                title: "Validate workspace after actions",
                action: .validateWorkspace(
                    reason: workspace.isExpoFocused
                        ? "Check Expo / React Native diagnostics after the planned workspace actions"
                        : "Check workspace diagnostics after the planned actions"
                ),
                detail: workspace.isExpoFocused
                    ? "Expo-focused validation for \(workspace.projectName)"
                    : "General workspace validation for \(workspace.projectName)"
            )
        )

        return AgentExecutionPlan(
            goal: safeGoal,
            workspace: workspace,
            actions: actions,
            fallbackPatchPlan: patchPlan
        )
    }

    private static func planPatchBackedActions(
        goal: String,
        patchPlan: PatchPlan
    ) -> [AgentPlannedAction] {
        let pendingOperations = patchPlan.operations.filter { $0.status == .pending }
        guard !pendingOperations.isEmpty else { return [] }

        return groupedOperations(pendingOperations).flatMap { group in
            let filePlan = PatchPlan(
                summary: patchPlan.summary,
                operations: group.operations,
                createdAt: patchPlan.createdAt
            )
            let operationCount = group.operations.count
            let operationLabel = "\(operationCount) patch operation\(operationCount == 1 ? "" : "s")"

            let inspectAction = AgentPlannedAction(
                title: "Inspect \(group.filePath)",
                action: .inspectFile(
                    path: group.filePath,
                    reason: "Read current file state before deciding whether to write \(group.filePath) for goal: \(goal)"
                ),
                detail: "Pre-write inspection for \(group.filePath)"
            )

            let writeAction: AgentPlannedAction
            if isCreateOnlyGroup(group.operations) {
                writeAction = AgentPlannedAction(
                    title: "Create \(group.filePath)",
                    action: .createFile(
                        path: group.filePath,
                        strategy: .patchPlan(filePlan),
                        reason: "Materialize a new file through the guarded patch fallback using \(operationLabel)"
                    ),
                    detail: "Patch-backed create action for \(group.filePath)"
                )
            } else {
                writeAction = AgentPlannedAction(
                    title: "Update \(group.filePath)",
                    action: .updateFile(
                        path: group.filePath,
                        strategy: .patchPlan(filePlan),
                        reason: "Apply \(operationLabel) to \(group.filePath) for goal: \(goal)"
                    ),
                    detail: "Patch-backed update action for \(group.filePath)"
                )
            }

            return [inspectAction, writeAction]
        }
    }

    private static func exploratoryActions(
        goal: String,
        workspace: AgentWorkspaceContext
    ) -> [AgentPlannedAction] {
        let defaultPath = workspace.entryFile ?? defaultInspectionPath(for: workspace)
        guard let defaultPath else { return [] }

        return [
            AgentPlannedAction(
                title: "Inspect \(defaultPath)",
                action: .inspectFile(
                    path: defaultPath,
                    reason: "Inspect the most likely starting file for goal: \(goal)"
                ),
                detail: "Exploratory inspection anchored to the active workspace"
            )
        ]
    }

    private static func defaultInspectionPath(for workspace: AgentWorkspaceContext) -> String? {
        if workspace.hasExpoRouter {
            return "app/_layout.tsx"
        }

        if workspace.isExpoFocused {
            return "App.tsx"
        }

        return nil
    }

    private static func isCreateOnlyGroup(_ operations: [PatchOperation]) -> Bool {
        operations.allSatisfy { $0.searchText.isEmpty }
    }

    private static func groupedOperations(_ operations: [PatchOperation]) -> [(filePath: String, operations: [PatchOperation])] {
        var orderedGroups: [(filePath: String, operations: [PatchOperation])] = []

        for operation in operations {
            if let index = orderedGroups.firstIndex(where: { $0.filePath == operation.filePath }) {
                orderedGroups[index].operations.append(operation)
            } else {
                orderedGroups.append((filePath: operation.filePath, operations: [operation]))
            }
        }

        return orderedGroups
    }
}
