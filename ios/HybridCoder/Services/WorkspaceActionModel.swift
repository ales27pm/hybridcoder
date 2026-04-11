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

nonisolated enum AgentActionStatus: String, Sendable {
    case planned
    case running
    case succeeded
    case blocked
    case skipped
}

nonisolated enum AgentExecutionMode: String, Sendable {
    case patchApproval
    case goalDriven
}

nonisolated struct AgentExecutionPlan: Sendable {
    let goal: String
    let workspace: AgentWorkspaceContext
    let actions: [AgentPlannedAction]
    let fallbackPatchPlan: PatchPlan?
    let executionMode: AgentExecutionMode
}

nonisolated struct AgentPlannedAction: Identifiable, Sendable {
    let id: UUID
    let title: String
    let action: AgentWorkspaceAction
    let detail: String

    init(
        id: UUID = UUID(),
        title: String,
        action: AgentWorkspaceAction,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.detail = detail
    }
}

nonisolated struct AgentActionExecutionResult: Identifiable, Sendable {
    let id: UUID
    let plannedActionID: UUID
    let title: String
    let action: AgentWorkspaceAction
    let status: AgentActionStatus
    let detail: String
    let changedFiles: [String]
    let blockers: [String]

    init(
        id: UUID = UUID(),
        plannedActionID: UUID,
        title: String,
        action: AgentWorkspaceAction,
        status: AgentActionStatus,
        detail: String,
        changedFiles: [String] = [],
        blockers: [String] = []
    ) {
        self.id = id
        self.plannedActionID = plannedActionID
        self.title = title
        self.action = action
        self.status = status
        self.detail = detail
        self.changedFiles = changedFiles
        self.blockers = blockers
    }

    init(
        for action: AgentPlannedAction,
        status: AgentActionStatus,
        detail: String,
        changedFiles: [String] = [],
        blockers: [String] = []
    ) {
        self.init(
            plannedActionID: action.id,
            title: action.title,
            action: action.action,
            status: status,
            detail: detail,
            changedFiles: changedFiles,
            blockers: blockers
        )
    }
}

nonisolated struct AgentWorkspaceFileSnapshot: Sendable {
    let path: String
    let exists: Bool
    let content: String?
}

nonisolated struct AgentValidationOutcome: Sendable {
    let status: AgentActionStatus
    let diagnostics: [ProjectDiagnostic]
    let detail: String
}

nonisolated struct AgentExecutionOutcome: Sendable {
    let executionPlan: AgentExecutionPlan
    let actionResults: [AgentActionExecutionResult]
    let validationOutcome: AgentValidationOutcome
    let patchResult: PatchEngine.PatchResult
    let preflightFailures: [PatchEngine.OperationFailure]
    let blockers: [String]
    let didMakeMeaningfulWorkspaceProgress: Bool
    let attemptCount: Int
    let retryCount: Int

    var executedActions: [AgentActionExecutionResult] {
        actionResults.filter { $0.status != .skipped }
    }

    var succeededActions: [AgentActionExecutionResult] {
        actionResults.filter { $0.status == .succeeded }
    }

    var blockedActions: [AgentActionExecutionResult] {
        actionResults.filter { $0.status == .blocked }
    }
}

nonisolated enum AgentWorkspaceAction: Sendable {
    case inspectFile(path: String, reason: String)
    case createFile(path: String, strategy: WriteStrategy, reason: String)
    case updateFile(path: String, strategy: WriteStrategy, reason: String)
    case createFolder(path: String, reason: String)
    case renameFolder(from: String, to: String, reason: String)
    case deleteFolder(path: String, reason: String)
    case moveFile(from: String, to: String, reason: String)
    case renameFile(from: String, to: String, reason: String)
    case deleteFile(path: String, reason: String)
    case validateWorkspace(reason: String)

    nonisolated enum WriteStrategy: Sendable {
        case direct(contents: String)
        case append(text: String)
        case prepend(text: String)
        case replaceText(search: String, replacement: String)
        case patchPlan(PatchPlan)

        var isPatchBacked: Bool {
            if case .patchPlan = self {
                return true
            }
            return false
        }
    }

    var targetPaths: [String] {
        switch self {
        case .inspectFile(let path, _):
            return [path]
        case .createFile(let path, _, _):
            return [path]
        case .updateFile(let path, _, _):
            return [path]
        case .createFolder(let path, _):
            return [path]
        case .renameFolder(let from, let to, _):
            return [from, to]
        case .deleteFolder(let path, _):
            return [path]
        case .moveFile(let from, let to, _):
            return [from, to]
        case .renameFile(let from, let to, _):
            return [from, to]
        case .deleteFile(let path, _):
            return [path]
        case .validateWorkspace:
            return []
        }
    }

    var isWriteAction: Bool {
        switch self {
        case .createFile, .updateFile, .createFolder, .renameFolder, .deleteFolder, .moveFile, .renameFile, .deleteFile:
            return true
        case .inspectFile, .validateWorkspace:
            return false
        }
    }

    var summary: String {
        switch self {
        case .inspectFile(let path, _):
            return "Inspect \(path)"
        case .createFile(let path, _, _):
            return "Create \(path)"
        case .updateFile(let path, _, _):
            return "Update \(path)"
        case .createFolder(let path, _):
            return "Create folder \(path)"
        case .renameFolder(let from, let to, _):
            return "Rename folder \(from) to \(to)"
        case .deleteFolder(let path, _):
            return "Delete folder \(path)"
        case .moveFile(let from, let to, _):
            return "Move \(from) to \(to)"
        case .renameFile(let from, let to, _):
            return "Rename \(from) to \(to)"
        case .deleteFile(let path, _):
            return "Delete \(path)"
        case .validateWorkspace:
            return "Validate workspace"
        }
    }
}
