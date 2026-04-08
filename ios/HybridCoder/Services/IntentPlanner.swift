import Foundation

nonisolated enum IntentPlanner {
    static func planActions(
        goal: String,
        workspace: AgentWorkspaceContext,
        patchPlan: PatchPlan? = nil,
        executionMode: AgentExecutionMode = .goalDriven
    ) -> AgentExecutionPlan {
        let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeGoal = normalizedGoal.isEmpty ? (patchPlan?.summary ?? workspace.displayName) : normalizedGoal
        var actions: [AgentPlannedAction] = []

        if let patchPlan {
            actions.append(contentsOf: planPatchBackedActions(goal: safeGoal, patchPlan: patchPlan))
        }

        if executionMode == .goalDriven {
            actions.append(contentsOf: planGoalBackedActions(goal: safeGoal))
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
            fallbackPatchPlan: patchPlan,
            executionMode: executionMode
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

    private static func planGoalBackedActions(goal: String) -> [AgentPlannedAction] {
        var actions: [AgentPlannedAction] = []
        var seenKeys: Set<String> = []

        for intent in goalFileOperationIntents(goal: goal) {
            switch intent {
            case .rename(let from, let to):
                let key = "rename|\(from.lowercased())|\(to.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Rename \(from) to \(to)",
                        action: .renameFile(
                            from: from,
                            to: to,
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived rename action for \(from)"
                    )
                )

            case .delete(let path):
                let key = "delete|\(path.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Delete \(path)",
                        action: .deleteFile(
                            path: path,
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived delete action for \(path)"
                    )
                )
            }
        }

        return actions
    }

    private static func goalFileOperationIntents(goal: String) -> [GoalFileOperationIntent] {
        parseRenameIntents(goal) + parseDeleteIntents(goal)
    }

    private static func parseRenameIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let matches = regexCapturePairs(
            pattern: #"(?i)\b(?:rename|move)\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?\s+(?:to|into)\s+[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
            in: goal,
            firstGroup: 1,
            secondGroup: 2
        )
        return matches.compactMap { pair in
            let from = normalizeWorkspacePath(pair.0)
            let to = normalizeWorkspacePath(pair.1)
            guard !from.isEmpty, !to.isEmpty, from.lowercased() != to.lowercased() else { return nil }
            return .rename(from: from, to: to)
        }
    }

    private static func parseDeleteIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let paths = regexCaptures(
            pattern: #"(?i)\b(?:delete|remove)\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
            in: goal,
            captureGroup: 1
        )
        return paths.compactMap { rawPath in
            let path = normalizeWorkspacePath(rawPath)
            guard !path.isEmpty else { return nil }
            return .delete(path: path)
        }
    }

    private static func normalizeWorkspacePath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        path = path.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        while path.hasPrefix("/") {
            path.removeFirst()
        }
        return path
    }

    private static func regexCapturePairs(
        pattern: String,
        in text: String,
        firstGroup: Int,
        secondGroup: Int
    ) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > max(firstGroup, secondGroup) else { return nil }
            let firstRange = match.range(at: firstGroup)
            let secondRange = match.range(at: secondGroup)
            guard firstRange.location != NSNotFound, secondRange.location != NSNotFound else { return nil }
            return (nsText.substring(with: firstRange), nsText.substring(with: secondRange))
        }
    }

    private static func regexCaptures(
        pattern: String,
        in text: String,
        captureGroup: Int
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup else { return nil }
            let captureRange = match.range(at: captureGroup)
            guard captureRange.location != NSNotFound else { return nil }
            return nsText.substring(with: captureRange)
        }
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

private enum GoalFileOperationIntent {
    case rename(from: String, to: String)
    case delete(path: String)
}
