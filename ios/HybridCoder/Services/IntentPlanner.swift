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
            case .createFolder(let path):
                let key = "createFolder|\(path.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Create folder \(path)",
                        action: .createFolder(
                            path: path,
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived folder create action for \(path)"
                    )
                )

            case .renameFolder(let from, let to):
                let key = "renameFolder|\(from.lowercased())|\(to.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Rename folder \(from) to \(to)",
                        action: .renameFolder(
                            from: from,
                            to: to,
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived folder rename action for \(from)"
                    )
                )

            case .deleteFolder(let path):
                let key = "deleteFolder|\(path.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Delete folder \(path)",
                        action: .deleteFolder(
                            path: path,
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived folder delete action for \(path)"
                    )
                )

            case .create(let path):
                let key = "create|\(path.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                let contents = defaultContentsForGoalCreate(path: path)
                actions.append(
                    AgentPlannedAction(
                        title: "Create \(path)",
                        action: .createFile(
                            path: path,
                            strategy: .direct(contents: contents),
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived create action for \(path)"
                    )
                )

            case .replace(let path):
                let key = "replace|\(path.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                let contents = defaultContentsForGoalCreate(path: path)
                actions.append(
                    AgentPlannedAction(
                        title: "Overwrite \(path)",
                        action: .updateFile(
                            path: path,
                            strategy: .direct(contents: contents),
                            reason: "Explicit overwrite requested by the goal: \(goal)"
                        ),
                        detail: "Goal-derived direct overwrite action for \(path)"
                    )
                )

            case .appendText(let path, let text):
                let key = "append|\(path.lowercased())|\(text.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Append text to \(path)",
                        action: .updateFile(
                            path: path,
                            strategy: .append(text: text),
                            reason: "Explicit append requested by the goal: \(goal)"
                        ),
                        detail: "Goal-derived direct append action for \(path)"
                    )
                )

            case .prependText(let path, let text):
                let key = "prepend|\(path.lowercased())|\(text.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Prepend text to \(path)",
                        action: .updateFile(
                            path: path,
                            strategy: .prepend(text: text),
                            reason: "Explicit prepend requested by the goal: \(goal)"
                        ),
                        detail: "Goal-derived direct prepend action for \(path)"
                    )
                )

            case .replaceText(let path, let search, let replacement):
                let key = "replaceText|\(path.lowercased())|\(search.lowercased())|\(replacement.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Replace text in \(path)",
                        action: .updateFile(
                            path: path,
                            strategy: .replaceText(search: search, replacement: replacement),
                            reason: "Explicit in-file replace requested by the goal: \(goal)"
                        ),
                        detail: "Goal-derived direct replace action for \(path)"
                    )
                )

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

            case .move(let from, let to):
                let key = "move|\(from.lowercased())|\(to.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                actions.append(
                    AgentPlannedAction(
                        title: "Move \(from) to \(to)",
                        action: .moveFile(
                            from: from,
                            to: to,
                            reason: "Requested directly by the goal: \(goal)"
                        ),
                        detail: "Goal-derived move action for \(from)"
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
        parseCreateFolderIntents(goal)
        + parseRenameFolderIntents(goal)
        + parseDeleteFolderIntents(goal)
        + parseCreateIntents(goal)
        + parseReplaceIntents(goal)
        + parseAppendIntents(goal)
        + parsePrependIntents(goal)
        + parseReplaceTextIntents(goal)
        + parseMoveFileIntents(goal)
        + parseRenameIntents(goal)
        + parseDeleteIntents(goal)
    }

    private static func parseCreateFolderIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let paths = regexCaptures(
            pattern: #"(?i)\b(?:create|add|make|generate)\s+(?:a\s+)?(?:new\s+)?(?:folder|directory)\s+[`'"]?([A-Za-z0-9_./\-]+)[`'"]?"#,
            in: goal,
            captureGroup: 1
        )
        return paths.compactMap { rawPath in
            let path = normalizeFolderPath(rawPath)
            guard !path.isEmpty else { return nil }
            return .createFolder(path: path)
        }
    }

    private static func parseRenameFolderIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let matches = regexCapturePairs(
            pattern: #"(?i)\b(?:rename|move)\s+(?:the\s+)?(?:folder|directory)\s+[`'"]?([A-Za-z0-9_./\-]+)[`'"]?\s+(?:to|into)\s+[`'"]?([A-Za-z0-9_./\-]+)[`'"]?"#,
            in: goal,
            firstGroup: 1,
            secondGroup: 2
        )
        return matches.compactMap { pair in
            let from = normalizeFolderPath(pair.0)
            let to = normalizeFolderPath(pair.1)
            guard !from.isEmpty, !to.isEmpty, from.lowercased() != to.lowercased() else { return nil }
            return .renameFolder(from: from, to: to)
        }
    }

    private static func parseDeleteFolderIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let paths = regexCaptures(
            pattern: #"(?i)\b(?:delete|remove)\s+(?:the\s+)?(?:folder|directory)\s+[`'"]?([A-Za-z0-9_./\-]+)[`'"]?"#,
            in: goal,
            captureGroup: 1
        )
        return paths.compactMap { rawPath in
            let path = normalizeFolderPath(rawPath)
            guard !path.isEmpty else { return nil }
            return .deleteFolder(path: path)
        }
    }

    private static func parseCreateIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let paths = regexCaptures(
            pattern: #"(?i)\b(?:create|add|make|generate)\s+(?:a\s+)?(?:new\s+)?(?:empty\s+)?(?:file\s+)?[`'"]?((?=[A-Za-z0-9_./\-]*[/.])[A-Za-z0-9_./\-]+)[`'"]?"#,
            in: goal,
            captureGroup: 1
        )
        return paths.compactMap { rawPath in
            let path = normalizeWorkspacePath(rawPath)
            guard !path.isEmpty else { return nil }
            return .create(path: path)
        }
    }

    private static func parseReplaceIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let paths = regexCaptures(
            pattern: #"(?i)\b(?:overwrite|replace)\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?(?!\s+(?:to|into)\s+[`'"]?[A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)"#,
            in: goal,
            captureGroup: 1
        )
        return paths.compactMap { rawPath in
            let path = normalizeWorkspacePath(rawPath)
            guard !path.isEmpty else { return nil }
            return .replace(path: path)
        }
    }

    private static func parseAppendIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let captures = regexCapturePairs(
            pattern: #"(?i)\bappend\s+[`'"]([^`'"]+)[`'"]\s+(?:to|into)\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
            in: goal,
            firstGroup: 1,
            secondGroup: 2
        )
        return captures.compactMap { text, rawPath in
            let path = normalizeWorkspacePath(rawPath)
            guard !path.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .appendText(path: path, text: text)
        }
    }

    private static func parsePrependIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let captures = regexCapturePairs(
            pattern: #"(?i)\bprepend\s+[`'"]([^`'"]+)[`'"]\s+(?:to|into)\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
            in: goal,
            firstGroup: 1,
            secondGroup: 2
        )
        return captures.compactMap { text, rawPath in
            let path = normalizeWorkspacePath(rawPath)
            guard !path.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .prependText(path: path, text: text)
        }
    }

    private static func parseReplaceTextIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let captures = regexCaptureTriples(
            pattern: #"(?i)\breplace\s+[`'"]([^`'"]+)[`'"]\s+with\s+[`'"]([^`'"]*)[`'"]\s+(?:in|inside)\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
            in: goal,
            firstGroup: 1,
            secondGroup: 2,
            thirdGroup: 3
        )
        return captures.compactMap { search, replacement, rawPath in
            let path = normalizeWorkspacePath(rawPath)
            guard !path.isEmpty, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .replaceText(path: path, search: search, replacement: replacement)
        }
    }

    private static func parseRenameIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let matches = regexCapturePairs(
            pattern: #"(?i)\brename\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?\s+(?:to|into)\s+[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
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

    private static func parseMoveFileIntents(_ goal: String) -> [GoalFileOperationIntent] {
        let matches = regexCapturePairs(
            pattern: #"(?i)\bmove\s+(?:the\s+)?(?:file\s+)?[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?\s+(?:to|into)\s+[`'"]?([A-Za-z0-9_./\-]+\.[A-Za-z0-9]+)[`'"]?"#,
            in: goal,
            firstGroup: 1,
            secondGroup: 2
        )
        return matches.compactMap { pair in
            let from = normalizeWorkspacePath(pair.0)
            let to = normalizeWorkspacePath(pair.1)
            guard !from.isEmpty, !to.isEmpty, from.lowercased() != to.lowercased() else { return nil }
            return .move(from: from, to: to)
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

    private static func normalizeFolderPath(_ rawPath: String) -> String {
        var path = normalizeWorkspacePath(rawPath)
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func defaultContentsForGoalCreate(path: String) -> String {
        let componentName = componentName(for: path)
        let componentTitle = titleForComponent(from: componentName)
        let extensionName = (path as NSString).pathExtension.lowercased()

        switch extensionName {
        case "tsx":
            return """
            import { Text, View } from "react-native";

            export default function \(componentName)() {
              return (
                <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
                  <Text>\(componentTitle)</Text>
                </View>
              );
            }
            """

        case "jsx":
            return """
            import { Text, View } from "react-native";

            export default function \(componentName)() {
              return (
                <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
                  <Text>\(componentTitle)</Text>
                </View>
              );
            }
            """

        case "ts":
            return "export {};\n"

        case "js":
            return "export {};\n"

        case "json":
            return "{}\n"

        default:
            return ""
        }
    }

    private static func componentName(for path: String) -> String {
        let baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let sanitized = baseName.replacingOccurrences(of: "[^A-Za-z0-9]+", with: " ", options: .regularExpression)
        let tokens = sanitized
            .split(separator: " ")
            .map { fragment in
                let text = String(fragment)
                guard let first = text.first else { return "" }
                return String(first).uppercased() + text.dropFirst().lowercased()
            }
            .joined()

        let fallback = tokens.isEmpty ? "Screen" : tokens
        if let first = fallback.first, first.isNumber {
            return "Screen\(fallback)"
        }
        return fallback
    }

    private static func titleForComponent(from componentName: String) -> String {
        let spaced = componentName.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return spaced.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func regexCaptureTriples(
        pattern: String,
        in text: String,
        firstGroup: Int,
        secondGroup: Int,
        thirdGroup: Int
    ) -> [(String, String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > max(firstGroup, max(secondGroup, thirdGroup)) else { return nil }
            let firstRange = match.range(at: firstGroup)
            let secondRange = match.range(at: secondGroup)
            let thirdRange = match.range(at: thirdGroup)
            guard firstRange.location != NSNotFound,
                  secondRange.location != NSNotFound,
                  thirdRange.location != NSNotFound else { return nil }
            return (
                nsText.substring(with: firstRange),
                nsText.substring(with: secondRange),
                nsText.substring(with: thirdRange)
            )
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
    case createFolder(path: String)
    case renameFolder(from: String, to: String)
    case deleteFolder(path: String)
    case create(path: String)
    case replace(path: String)
    case appendText(path: String, text: String)
    case prependText(path: String, text: String)
    case replaceText(path: String, search: String, replacement: String)
    case move(from: String, to: String)
    case rename(from: String, to: String)
    case delete(path: String)
}
