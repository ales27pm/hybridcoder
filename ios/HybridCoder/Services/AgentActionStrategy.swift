import Foundation

/// Strategy contract for workspace mutations executed by `AgentRuntime`.
///
/// This reframes the runtime so that patching becomes one strategy among
/// many (create/update/rename/delete/patch) rather than a conceptual
/// fallback backbone. The concrete strategy types below are defined as
/// namespaces today — `IntentPlanner` and `ExecutionCoordinator` continue
/// to drive dispatch, but every mutation conceptually flows through one
/// of these strategies and future work can make the dispatch explicit.
nonisolated protocol AgentActionStrategy: Sendable {
    static var name: String { get }
}

nonisolated enum CreateFileStrategy: AgentActionStrategy {
    static let name = "create-file"
}

nonisolated enum UpdateFileStrategy: AgentActionStrategy {
    static let name = "update-file"
}

nonisolated enum RenameStrategy: AgentActionStrategy {
    static let name = "rename"
}

nonisolated enum DeleteStrategy: AgentActionStrategy {
    static let name = "delete"
}

nonisolated enum PatchStrategy: AgentActionStrategy {
    static let name = "patch"
}

nonisolated enum AgentActionStrategyKind: String, Sendable {
    case createFile
    case updateFile
    case rename
    case delete
    case patch
    case inspect
    case validate

    init(for action: AgentWorkspaceAction) {
        switch action {
        case .inspectFile:
            self = .inspect
        case .validateWorkspace:
            self = .validate
        case .createFile(_, let strategy, _):
            self = strategy.isPatchBacked ? .patch : .createFile
        case .updateFile(_, let strategy, _):
            self = strategy.isPatchBacked ? .patch : .updateFile
        case .createFolder:
            self = .createFile
        case .renameFolder, .renameFile, .moveFile:
            self = .rename
        case .deleteFolder, .deleteFile:
            self = .delete
        }
    }
}
